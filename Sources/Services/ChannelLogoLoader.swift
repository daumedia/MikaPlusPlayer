import Foundation
import ImageIO
import CoreGraphics

/// Lädt Senderlogos für die Senderliste und den Favoriten-Tab – beide zeigen dieselbe Karte (`ChannelRowView`),
/// also gibt es genau einen Weg (B04 · BUG-04 bis BUG-07, gilt ebenso für den Favoriten-Tab aus B05).
///
/// - **Nur `http`/`https`.** Andere Schemata (`file:`, `data:`, `javascript:` …) und fehlende Adressen ergeben sofort
///   den Platzhalter, ohne Anfrage (BUG-04; wie die Importregel für Logos in B02 · BUG-05).
/// - **Grenzen** (BUG-05): höchstens `Limits.maxBytes` je Antwort (größere werden schon an `Content-Length` bzw.
///   beim Überschreiten abgebrochen), eine Gesamtfrist und eine Leerlauffrist je Logo ab dem Senden (Anfragen, die auf
///   eine Verbindung zum Host warten, warten abbrechbar in `RequestGate`), höchstens `Limits.maxPixels` Bildpunkte laut
///   Bildkopf. Das Bild wird nie in voller Größe dekodiert, sondern über ImageIO als
///   Vorschaubild mit höchstens `Limits.thumbnailPixels` Kantenlänge erzeugt.
/// - **Weitergabe** (BUG-06): eigene Session ohne Cookies und ohne Zugangsdatenspeicher, Weiterleitungen nur auf
///   denselben Host und Port (einzige Ausnahme: `http` → `https` desselben Hosts), neutrale Kopfzeilen (kein
///   App-Name, kein Build, keine Systemversion, keine Systemsprache).
/// - **Kein Plattencache** (BUG-07): weder `URLCache.shared` noch ein anderer Cache auf der Platte. Fertige
///   Vorschaubilder liegen nur im Arbeitsspeicher (begrenzt, Antworten mit `Cache-Control: no-store` nie) und werden
///   beim Löschen einer Playlist und bei „Alle Daten entfernen" geleert.
/// - Jeder Fehler (HTTP-Fehler, kein Bild, zu groß, zu langsam, Weiterleitung auf einen fremden Host, Schleife,
///   Verbindungsfehler) ergibt `nil` – die Ansicht zeigt dann den Platzhalter statt eines Ladeindikators.
final class ChannelLogoLoader: @unchecked Sendable {
    static let shared = ChannelLogoLoader()

    struct Limits: Sendable {
        /// Größte angenommene Antwort.
        var maxBytes = 1_048_576
        /// Höchstens so viele Bildpunkte (Breite × Höhe laut Bildkopf); größere Bilder werden nicht dekodiert.
        var maxPixels = 2_048 * 2_048
        /// Kantenlänge des erzeugten Vorschaubilds in Pixeln (Logofeld 40 pt, bis 3-fache Auflösung).
        var thumbnailPixels = 128
        /// Höchstens so lange ohne neue Daten.
        var idleTimeout: TimeInterval = 10
        /// Gesamtfrist je Logo, auch wenn die Daten tröpfeln.
        var totalTimeout: TimeInterval = 15
        /// Höchstens so viele Weiterleitungen, nur auf denselben Host und Port (bzw. `http` → `https`).
        var maxRedirects = 3
        /// Höchstens so viele Logo-Anfragen je Host gleichzeitig (wie `URLSession` Verbindungen je Host öffnet). Weitere
        /// warten hier, abbrechbar, und ihre Fristen beginnen erst mit dem Senden – sonst liefen sie schon in der
        /// Warteschlange ab (bei vielen langsamen Logos eines Hosts).
        var maxConcurrentPerHost = 6
        /// Arbeitsspeicher-Cache: Anzahl und Größe der Vorschaubilder.
        var cacheCount = 400
        var cacheBytes = 24 * 1_048_576

        static let standard = Limits()
    }

    /// Kopfzeilen, die jede Logo-Anfrage trägt: Sie ersetzen die Vorgaben von CFNetwork
    /// (`User-Agent: Mika+Player/<Build> CFNetwork/… Darwin/…`, `Accept-Language: <Systemsprache>`).
    static let neutralHeaders: [String: String] = [
        "User-Agent": "Mozilla/5.0",
        "Accept-Language": "*",
    ]

    /// Nur diese Schemata werden angefragt.
    static let allowedSchemes: Set<String> = ["http", "https"]

    let limits: Limits
    private let http: PlaylistHTTPLoader
    private let cache = NSCache<NSString, CachedImage>()
    private let gate: RequestGate

    private final class CachedImage {
        let image: CGImage
        init(_ image: CGImage) { self.image = image }
    }

    init(limits: Limits = .standard) {
        self.limits = limits
        let configuration = URLSessionConfiguration.ephemeral
        configuration.urlCache = nil
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        configuration.urlCredentialStorage = nil
        configuration.httpCookieStorage = nil
        configuration.httpShouldSetCookies = false
        configuration.httpCookieAcceptPolicy = .never
        configuration.timeoutIntervalForRequest = limits.idleTimeout
        configuration.timeoutIntervalForResource = limits.totalTimeout
        configuration.httpAdditionalHeaders = Self.neutralHeaders
        configuration.httpMaximumConnectionsPerHost = limits.maxConcurrentPerHost
        http = PlaylistHTTPLoader(configuration: configuration)
        gate = RequestGate(limit: limits.maxConcurrentPerHost)
        cache.countLimit = limits.cacheCount
        cache.totalCostLimit = limits.cacheBytes
    }

    /// Ob für diese Adresse überhaupt eine Anfrage gestellt wird.
    static func accepts(_ url: URL?) -> Bool {
        guard let url, let scheme = url.scheme?.lowercased(), allowedSchemes.contains(scheme) else { return false }
        return url.host?.isEmpty == false
    }

    /// Das zwischengespeicherte Vorschaubild, falls vorhanden (ohne Anfrage).
    func cachedImage(for url: URL) -> CGImage? {
        cache.object(forKey: url.absoluteString as NSString)?.image
    }

    /// Lädt das Logo und liefert ein verkleinertes Bild – oder `nil`, wenn es keines gibt (Platzhalter).
    /// Wird die aufrufende Aufgabe abgebrochen (Karte weggescrollt, Liste verlassen), bricht die Anfrage sofort ab.
    func image(for url: URL) async -> CGImage? {
        guard Self.accepts(url) else { return nil }
        if let hit = cachedImage(for: url) { return hit }
        // Erst einen freien Platz für diesen Host abwarten (abbrechbar), dann senden: Leerlauf- und Gesamtfrist gelten
        // ab dem Senden, nicht ab dem Einreihen.
        let hostKey = "\(url.scheme?.lowercased() ?? "")://\(url.host?.lowercased() ?? ""):\(url.port ?? -1)"
        do { try await gate.acquire(hostKey) } catch { return nil }
        defer { gate.release(hostKey) }
        var request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: limits.idleTimeout)
        for (field, value) in Self.neutralHeaders { request.setValue(value, forHTTPHeaderField: field) }
        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await http.data(
                for: request, maxBytes: limits.maxBytes, deadline: Date().addingTimeInterval(limits.totalTimeout),
                redirects: .sameHost(maxRedirects: limits.maxRedirects))
        } catch {
            return nil
        }
        guard let status = (response as? HTTPURLResponse)?.statusCode, (200..<300).contains(status),
              let image = Self.thumbnail(from: data, limits: limits) else { return nil }
        if !Self.forbidsStoring(response) {
            cache.setObject(CachedImage(image), forKey: url.absoluteString as NSString, cost: image.bytesPerRow * image.height)
        }
        return image
    }

    /// Leert den Arbeitsspeicher-Cache (Löschen einer Playlist, „Alle Daten entfernen").
    func removeAll() {
        cache.removeAllObjects()
    }

    /// Erzeugt ein Vorschaubild, ohne das Bild in voller Größe zu dekodieren. `nil` für Nicht-Bilder und Bilder mit
    /// mehr als `limits.maxPixels` Bildpunkten laut Bildkopf.
    static func thumbnail(from data: Data, limits: Limits) -> CGImage? {
        let sourceOptions = [kCGImageSourceShouldCache: false] as CFDictionary
        guard let source = CGImageSourceCreateWithData(data as CFData, sourceOptions),
              CGImageSourceGetCount(source) > 0,
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, sourceOptions) as? [CFString: Any],
              let width = (properties[kCGImagePropertyPixelWidth] as? NSNumber)?.intValue,
              let height = (properties[kCGImagePropertyPixelHeight] as? NSNumber)?.intValue,
              width > 0, height > 0, width.multipliedReportingOverflow(by: height).partialValue <= limits.maxPixels,
              !width.multipliedReportingOverflow(by: height).overflow else { return nil }
        let options = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceThumbnailMaxPixelSize: limits.thumbnailPixels,
        ] as CFDictionary
        return CGImageSourceCreateThumbnailAtIndex(source, 0, options)
    }

    private static func forbidsStoring(_ response: URLResponse) -> Bool {
        guard let value = (response as? HTTPURLResponse)?.value(forHTTPHeaderField: "Cache-Control") else { return false }
        return value.lowercased().split(separator: ",")
            .contains { $0.trimmingCharacters(in: .whitespaces) == "no-store" }
    }
}

/// Begrenzt gleichzeitige Anfragen je Schlüssel (Host). Wartende lassen sich abbrechen und belegen dann keinen Platz.
final class RequestGate: @unchecked Sendable {
    private struct Waiter {
        let id: UUID
        let continuation: CheckedContinuation<Void, Error>
    }

    private let limit: Int
    private let lock = NSLock()
    private var active: [String: Int] = [:]
    private var waiting: [String: [Waiter]] = [:]
    /// Abgebrochen, bevor sie sich einreihen konnten.
    private var cancelledEarly: Set<UUID> = []

    init(limit: Int) {
        self.limit = max(1, limit)
    }

    /// Wartet auf einen freien Platz; wirft `CancellationError`, wenn die Aufgabe vorher abgebrochen wird.
    func acquire(_ key: String) async throws {
        let id = UUID()
        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
                lock.lock()
                if cancelledEarly.remove(id) != nil {
                    lock.unlock()
                    continuation.resume(throwing: CancellationError())
                } else if active[key, default: 0] < limit {
                    active[key, default: 0] += 1
                    lock.unlock()
                    continuation.resume()
                } else {
                    waiting[key, default: []].append(Waiter(id: id, continuation: continuation))
                    lock.unlock()
                }
            }
        } onCancel: {
            lock.lock()
            if let index = waiting[key]?.firstIndex(where: { $0.id == id }) {
                let waiter = waiting[key]!.remove(at: index)
                lock.unlock()
                waiter.continuation.resume(throwing: CancellationError())
            } else {
                // Noch nicht eingereiht (oder schon zugelassen): Ein späteres Einreihen bricht sofort ab.
                cancelledEarly.insert(id)
                lock.unlock()
            }
        }
        // Zugelassen, aber inzwischen abgebrochen: Platz sofort zurückgeben.
        lock.withLock { _ = cancelledEarly.remove(id) }
        if Task.isCancelled {
            release(key)
            throw CancellationError()
        }
    }

    /// Gibt einen Platz frei; der nächste Wartende rückt nach.
    func release(_ key: String) {
        lock.lock()
        if var queue = waiting[key], !queue.isEmpty {
            let next = queue.removeFirst()
            waiting[key] = queue.isEmpty ? nil : queue
            lock.unlock()
            next.continuation.resume()
        } else {
            let remaining = active[key, default: 1] - 1
            active[key] = remaining > 0 ? remaining : nil
            lock.unlock()
        }
    }
}
