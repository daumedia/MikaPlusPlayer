import Foundation
import SwiftData

enum ImportError: LocalizedError, Equatable {
    case invalidURL
    case emptyPlaylist
    case fileAccessDenied
    case network(String)
    /// Antwort bzw. Datei über der Größengrenze (B02 · BUG-03)
    case tooLarge(megabytes: Int, file: Bool)
    /// Gesamtfrist überschritten (B02 · BUG-03)
    case deadlineExceeded(seconds: Int)
    /// Server liefert nach der Anlaufzeit zu langsam (B02 · BUG-03)
    case tooSlow
    /// Mehr Einträge als die Grenze (B02 · BUG-03)
    case tooManyChannels(Int)
    /// Zugangsdaten einer M3U-Playlist fehlen im Schlüsselbund (B02 · BUG-01)
    case missingCredentials

    var errorDescription: String? {
        switch self {
        case .invalidURL: return "Die angegebene URL ist ungültig."
        case .emptyPlaylist: return "Die Playlist enthält keine gültigen Sender."
        case .fileAccessDenied: return "Auf die ausgewählte Datei kann nicht zugegriffen werden."
        case .network(let msg): return "Netzwerkfehler: \(msg)"
        case .tooLarge(let megabytes, let file):
            return file
                ? "Die Datei ist zu groß (mehr als \(megabytes) MB)."
                : "Netzwerkfehler: Die Playlist ist zu groß (mehr als \(megabytes) MB)."
        case .deadlineExceeded(let seconds):
            return "Netzwerkfehler: Der Server hat die Playlist nicht innerhalb von \(seconds) Sekunden vollständig geliefert."
        case .tooSlow:
            return "Netzwerkfehler: Der Server liefert die Playlist zu langsam."
        case .tooManyChannels(let maximum):
            return "Die Senderliste ist zu groß (mehr als \(maximum.formatted(.number.locale(Locale(identifier: "de_DE")))) Sender)."
        case .missingCredentials:
            return "Die Zugangsdaten dieser Playlist fehlen auf diesem Gerät. Bitte die Playlist löschen und neu importieren."
        }
    }
}

/// Einziger Einstieg für Import, Aktualisieren und Löschen von Playlists – für alle Importwege gleich
/// (Muster „Reparaturen je Importweg statt im gemeinsamen Pfad", B02/B03):
///
/// - **Abruf** über `PlaylistHTTPLoader` (ohne Plattencache, mit Grenzen), Parsen und Aufbereiten abseits des
///   Main-Actors.
/// - **Zugangsdaten** (Xtream und M3U-Adressen mit `username`/`password` bzw. `user:pass@`) in den Schlüsselbund;
///   Datenbank und Stream-Adressen tragen nur Platzhalter.
/// - **Schreiben** ausschließlich über `PlaylistStore` (eigener Kontext, Blöcke bzw. ein atomarer Speichervorgang).
/// - **Löschen** an einer Stelle: Sender, Playlist, Schlüsselbund, Cache-Einträge, Cookies, Verdichten.
///
/// Der Main-Actor erledigt nur das Abholen der fertigen Objekte in den Kontext der Ansicht (Millisekunden).
@MainActor
@Observable
final class PlaylistImporter {
    /// Grenzen für M3U-Listen per URL und Datei (B02 · BUG-03), analog zu `XtreamClient.Limits`.
    struct M3ULimits: Sendable {
        /// Höchstens so lange ohne neue Daten je Anfrage.
        var idleTimeout: TimeInterval = 60
        /// Gesamtfrist für den Abruf.
        var totalTimeout: TimeInterval = 180
        /// Größte angenommene Antwort bzw. Datei.
        var maxBytes = 64 * 1024 * 1024
        /// Mindestdurchsatz, sobald die Antwort begonnen hat (tröpfelnde Server).
        var throughput = PlaylistHTTPLoader.Throughput(bytesPerSecond: 2_048, grace: 20)
        /// Feldlängen, Schemata und Höchstzahl der Sender.
        var parser = M3UParser.Limits(maxChannels: 100_000)

        static let standard = M3ULimits()
    }

    private let modelContext: ModelContext
    private let credentialStore: XtreamCredentialStore
    private let xtreamLimits: XtreamClient.Limits
    private let m3uLimits: M3ULimits
    private let loginThrottle: XtreamLoginThrottle
    private let loader: PlaylistHTTPLoader
    private let store: PlaylistStore

    /// True, während ein Import/Refresh läuft (für UI-Spinner).
    var isWorking = false

    /// Laufende Aktualisierungen, über alle Fenster: Ein zweiter Aufruf für dieselbe Playlist bleibt ohne Wirkung
    /// und sendet keine Zugangsdaten (B03 · BUG-04).
    private(set) static var refreshing: Set<UUID> = []

    init(
        modelContext: ModelContext,
        credentialStore: XtreamCredentialStore = .standard,
        xtreamLimits: XtreamClient.Limits = .standard,
        m3uLimits: M3ULimits = .standard,
        loginThrottle: XtreamLoginThrottle = .shared,
        loader: PlaylistHTTPLoader = .shared,
        store: PlaylistStore = .shared
    ) {
        self.modelContext = modelContext
        self.credentialStore = credentialStore
        self.xtreamLimits = xtreamLimits
        self.m3uLimits = m3uLimits
        self.loginThrottle = loginThrottle
        self.loader = loader
        self.store = store
    }

    // MARK: - Import

    /// Importiert eine Playlist von einer Remote-URL.
    ///
    /// Zugangsdaten in der Adresse gehen in den Schlüsselbund (B02 · BUG-01), der Abruf läuft ohne Plattencache und
    /// mit Grenzen (BUG-02, BUG-03), Parsen und Speichern abseits des Main-Actors (BUG-04). Wird die aufrufende
    /// Aufgabe abgebrochen, entsteht nichts (BUG-08).
    @discardableResult
    func importFromURL(_ urlString: String, name: String) async throws -> Playlist {
        guard let url = URL(string: urlString.trimmingCharacters(in: .whitespacesAndNewlines)),
              url.scheme != nil else {
            throw ImportError.invalidURL
        }
        isWorking = true
        defer { isWorking = false }

        let split = M3UCredentials.split(url)
        let parsed = try await Self.loadM3U(from: url, secret: split?.secret, limits: m3uLimits, loader: loader)
        try Task.checkCancellation()

        let id = UUID()
        let displayName = name.isEmpty ? (url.host ?? "Playlist") : name
        let now = Date()
        if let secret = split?.secret { try credentialStore.saveM3U(secret, for: id) }
        let draft = PlaylistStore.Draft(id: id, name: displayName, sourceURL: split?.stored ?? url, lastRefreshed: now)
        try await persist(draft, parsed, credentialsSaved: split != nil)
        return try adopt(id, lastRefreshed: now)
    }

    /// Importiert eine Playlist über die Xtream-Codes-API (player_api.php).
    ///
    /// - Zugangsdaten gehen in den Schlüsselbund, Datenbank und Stream-Adressen bleiben ohne
    ///   Geheimnis (B01 · BUG-01).
    /// - Die Sender werden über `PlaylistStore` abseits des Main-Actors in Blöcken gespeichert (B01 · BUG-12).
    /// - Wird die aufrufende Aufgabe vor dem Speichern abgebrochen, entsteht nichts (B01 · BUG-11).
    @discardableResult
    func importFromXtream(
        _ credentials: XtreamCredentials,
        output: XtreamOutput,
        name: String
    ) async throws -> Playlist {
        isWorking = true
        defer { isWorking = false }

        let client = XtreamClient(credentials: credentials, limits: xtreamLimits, throttle: loginThrottle, loader: loader)
        let parsed = try await client.fetchLiveChannels(output: output)
        guard !parsed.isEmpty else { throw ImportError.emptyPlaylist }
        try Task.checkCancellation()

        guard let secret = credentials.secret(), let sourceURL = credentials.storedSourceURL() else {
            throw XtreamClient.XtreamError.invalidHost
        }
        let displayName = name.isEmpty ? (credentials.baseURL()?.host ?? "Xtream") : name
        let id = UUID()
        let now = Date()
        try credentialStore.save(secret, for: id)
        let draft = PlaylistStore.Draft(id: id, name: displayName, sourceURL: sourceURL, lastRefreshed: now,
                                        isXtream: true, xtreamOutput: output.rawValue)
        try await persist(draft, parsed, credentialsSaved: true)
        return try adopt(id, lastRefreshed: now)
    }

    /// Importiert eine Playlist aus einer lokalen Datei (.m3u/.m3u8), auch aus „Öffnen mit" (B02 · BUG-06).
    /// Erwartet eine über `fileImporter` bzw. vom System erhaltene, ggf. security-scoped URL.
    /// Lesen, Parsen und Speichern laufen abseits des Main-Actors (B02 · BUG-04), mit Größengrenze (BUG-03).
    @discardableResult
    func importFromFile(_ fileURL: URL, name: String? = nil) async throws -> Playlist {
        isWorking = true
        defer { isWorking = false }

        let parsed = try await Self.loadFile(fileURL, limits: m3uLimits)
        try Task.checkCancellation()

        let id = UUID()
        let displayName = name ?? fileURL.deletingPathExtension().lastPathComponent
        // Lokale Datei: sourceURL bleibt nil -> nicht refreshbar.
        try await persist(PlaylistStore.Draft(id: id, name: displayName), parsed, credentialsSaved: false)
        return try adopt(id, lastRefreshed: nil)
    }

    private func persist(_ draft: PlaylistStore.Draft, _ channels: [ParsedChannel], credentialsSaved: Bool) async throws {
        do {
            try await store.create(draft, channels: channels, in: modelContext.container)
        } catch {
            if credentialsSaved { try? credentialStore.delete(for: draft.id) }
            throw error
        }
    }

    /// Holt die im Hintergrund angelegte Playlist in den Kontext der Ansicht. Das Speichern hier stößt auch die
    /// `@Query`-Ansichten an.
    private func adopt(_ id: UUID, lastRefreshed: Date?) throws -> Playlist {
        var descriptor = FetchDescriptor<Playlist>(predicate: #Predicate { $0.id == id })
        descriptor.fetchLimit = 1
        guard let playlist = try modelContext.fetch(descriptor).first else { throw ImportError.emptyPlaylist }
        if let lastRefreshed {
            playlist.lastRefreshed = lastRefreshed
        } else {
            playlist.channelCount = playlist.channelCount
        }
        try modelContext.save()
        return playlist
    }

    // MARK: - Refresh

    /// Lädt eine Remote-Playlist neu. Favoriten gehen nach `FavoriteCarryOver` über (tvg-id bzw. Name,
    /// je Schlüssel höchstens so viele wie vorher). Unterstützt M3U-URL- und Xtream-Playlists.
    ///
    /// Läuft für diese Playlist schon eine Aktualisierung, kehrt der Aufruf ohne Wirkung zurück (B03 · BUG-04).
    /// Wird die Playlist währenddessen gelöscht, endet der Aufruf ohne Meldung und ohne Spuren (AK-26, BUG-08).
    func refresh(_ playlist: Playlist) async throws {
        guard let url = playlist.sourceURL else { return }
        let id = playlist.id
        guard !Self.refreshing.contains(id) else { return }
        Self.refreshing.insert(id)
        defer { Self.refreshing.remove(id) }
        isWorking = true
        defer { isWorking = false }

        let persistentID = playlist.persistentModelID
        let parsed: [ParsedChannel]
        var credentialUpdate: PlaylistStore.CredentialUpdate?
        var newSourceURL: URL?
        if playlist.isXtream {
            // B01 · BUG-01: Zugangsdaten aus dem Schlüsselbund. Altbestand mit Zugangsdaten in der
            // Adresse (Umstellung beim Start nicht gelungen) wird hier nachträglich umgestellt.
            let legacy = XtreamCredentials(legacyPlayerAPIURL: url)
            let credentials: XtreamCredentials
            if let legacy {
                credentials = legacy
            } else if let secret = try credentialStore.load(for: id) {
                credentials = XtreamCredentials(secret: secret)
            } else {
                throw StreamURLResolver.ResolveError.missingCredentials
            }
            let output = XtreamOutput(rawValue: playlist.xtreamOutput ?? "") ?? .hls
            parsed = try await XtreamClient(credentials: credentials, limits: xtreamLimits, throttle: loginThrottle, loader: loader)
                .fetchLiveChannels(output: output)
            if let legacy, let secret = legacy.secret() {
                credentialUpdate = .xtream(secret)
                newSourceURL = legacy.storedSourceURL()
            }
        } else {
            // B02 · BUG-01: Adresse mit Platzhaltern → Zugangsdaten aus dem Schlüsselbund; Altbestand mit
            // Zugangsdaten in der Adresse wird hier umgestellt.
            let fetchURL: URL
            let secret: M3USecret?
            if M3UCredentials.needsSecret(url) {
                guard let stored = try credentialStore.loadM3U(for: id), let original = URL(string: stored.sourceURL) else {
                    throw ImportError.missingCredentials
                }
                fetchURL = original
                secret = stored
            } else if let legacy = M3UCredentials.split(url) {
                fetchURL = url
                secret = legacy.secret
                credentialUpdate = .m3u(legacy.secret)
                newSourceURL = legacy.stored
            } else {
                fetchURL = url
                secret = nil
            }
            parsed = try await Self.loadM3U(from: fetchURL, secret: secret, limits: m3uLimits, loader: loader)
        }
        guard !parsed.isEmpty else { throw ImportError.emptyPlaylist }

        let refreshedAt = Date()
        let outcome = try await store.replaceChannels(
            of: id, persistentID: persistentID, with: parsed, refreshedAt: refreshedAt, newSourceURL: newSourceURL,
            credentialUpdate: credentialUpdate, credentialStore: credentialStore, in: modelContext.container)
        guard case .replaced = outcome else { return }
        synchronizeView(id, refreshedAt: refreshedAt)
    }

    /// Holt den neuen Stand in den Kontext der Ansicht: Das erneute Abrufen aktualisiert die gehaltene Playlist
    /// samt Beziehung; das erneute Setzen der angezeigten Werte meldet die Änderung an Ansichten, die die Playlist
    /// beobachten (Kopfzeile der Senderliste, Karte), und das Speichern stößt die `@Query`-Ansichten an. Die Daten selbst
    /// sind zu diesem Zeitpunkt schon gespeichert – scheitert dieses Anstoßen, wird es verworfen, ohne etwas zu verlieren.
    private func synchronizeView(_ id: UUID, refreshedAt: Date) {
        var descriptor = FetchDescriptor<Playlist>(predicate: #Predicate { $0.id == id })
        descriptor.fetchLimit = 1
        guard let playlist = try? modelContext.fetch(descriptor).first else { return }
        playlist.channelCount = playlist.channelCount
        playlist.sourceURL = playlist.sourceURL
        playlist.lastRefreshed = refreshedAt
        do {
            try modelContext.save()
        } catch {
            modelContext.rollback()
        }
    }

    // MARK: - Löschen

    /// Zentraler Löschweg für alle Importwege (B03 · BUG-01, -05, -06, -07, -08):
    /// Ansichten beenden Wiedergabe und Verbindungen, die Sender werden abseits des Main-Actors entfernt, dann die
    /// Playlist, ihr Schlüsselbund-Eintrag, etwaige Cache-Einträge ihrer Adresse und Cookies ihres Hosts; zuletzt
    /// wird die Datei verdichtet. Fehler werden gemeldet, nicht verschluckt.
    func delete(_ playlist: Playlist) async throws {
        let id = playlist.id
        let persistentID = playlist.persistentModelID
        let sourceURL = playlist.sourceURL
        // Vollständige Adresse (mit Zugangsdaten) für das Entfernen alter Cache-Einträge, bevor der Eintrag weg ist.
        let secretSource = sourceURL.flatMap { M3UCredentials.needsSecret($0) ? $0 : nil }
            .flatMap { _ in (try? credentialStore.loadM3U(for: id))?.sourceURL }
            .flatMap(URL.init(string:))

        PlaylistEvents.postWillDelete([id])
        defer { PlaylistEvents.finishDeleting([id]) }
        await store.beginDelete([id])
        do {
            try await store.removeChannels(of: id, persistentID: persistentID, in: modelContext.container)
            try removeRow(id, persistentID: persistentID)
        } catch {
            await store.endDelete([id])
            throw error
        }
        // Direkt nach dem Entfernen der Zeile, ohne Unterbrechung auf dem Main-Actor: Zugangsdaten, Cookies, Cache.
        var credentialError: Error?
        do {
            try credentialStore.delete(for: id)
        } catch {
            credentialError = error
        }
        let hosts = [sourceURL?.host, secretSource?.host].compactMap { $0 }
        for host in Set(hosts) { loader.removeCookies(forHost: host) }
        for address in [sourceURL, secretSource].compactMap({ $0 }) {
            URLCache.shared.removeCachedResponse(for: URLRequest(url: address))
        }
        await store.endDelete([id])
        await store.compact(modelContext.container)
        if let credentialError {
            throw DeleteError.credentialsRemain(credentialError.localizedDescription)
        }
    }

    /// Entfernt die (senderlose) Playlist aus dem Kontext der Ansicht und speichert. Das erneute Abrufen aktualisiert
    /// dabei die gehaltene Playlist samt (jetzt leerer) Beziehung, damit das Löschen nichts mehr kaskadiert.
    private func removeRow(_ id: UUID, persistentID: PersistentIdentifier) throws {
        let matches = try modelContext.fetch(FetchDescriptor<Playlist>(predicate: #Predicate { $0.id == id }))
        let doomed = matches.count > 1 ? matches.filter { $0.persistentModelID == persistentID } : matches
        for playlist in doomed { modelContext.delete(playlist) }
        do {
            try modelContext.save()
        } catch {
            modelContext.rollback()
            throw PlaylistStoreError.saveFailed
        }
    }

    enum DeleteError: LocalizedError, Equatable {
        case credentialsRemain(String)

        var errorDescription: String? {
            switch self {
            case .credentialsRemain(let reason):
                return "Die Playlist wurde gelöscht, ihre Zugangsdaten konnten aber nicht aus dem Schlüsselbund entfernt werden. \(reason)"
            }
        }
    }

    // MARK: - Abruf und Aufbereitung (abseits des Main-Actors)

    /// Lädt eine M3U-Liste über den gemeinsamen Loader, parst sie und ersetzt Zugangsdaten in den Stream-Adressen
    /// durch Platzhalter.
    nonisolated static func loadM3U(from url: URL, secret: M3USecret?, limits: M3ULimits,
                                    loader: PlaylistHTTPLoader) async throws -> [ParsedChannel] {
        let data: Data
        do {
            var request = URLRequest(url: url)
            request.cachePolicy = .reloadIgnoringLocalCacheData
            request.timeoutInterval = limits.idleTimeout
            let (body, response) = try await loader.data(
                for: request, maxBytes: limits.maxBytes, deadline: Date().addingTimeInterval(limits.totalTimeout),
                redirects: .follow, throughput: limits.throughput)
            if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
                throw ImportError.network("HTTP \(http.statusCode)")
            }
            data = body
        } catch let error as ImportError {
            throw error
        } catch let error as PlaylistHTTPLoader.LoadError {
            throw map(error, limits: limits)
        } catch let error as CancellationError {
            throw error
        } catch let error as URLError where error.code == .cancelled && Task.isCancelled {
            throw CancellationError()
        } catch {
            throw ImportError.network(error.localizedDescription)
        }
        try Task.checkCancellation()
        return try prepare(data, secret: secret, limits: limits)
    }

    /// Liest eine lokale Datei mit Größengrenze.
    nonisolated static func loadFile(_ fileURL: URL, limits: M3ULimits) async throws -> [ParsedChannel] {
        let needsScope = fileURL.startAccessingSecurityScopedResource()
        defer { if needsScope { fileURL.stopAccessingSecurityScopedResource() } }

        let values = try? fileURL.resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey])
        if values?.isRegularFile == true, let size = values?.fileSize, size > limits.maxBytes {
            throw ImportError.tooLarge(megabytes: megabytes(limits.maxBytes), file: true)
        }
        let data: Data
        do {
            data = try Data(contentsOf: fileURL, options: .mappedIfSafe)
        } catch {
            throw ImportError.fileAccessDenied
        }
        guard data.count <= limits.maxBytes else {
            throw ImportError.tooLarge(megabytes: megabytes(limits.maxBytes), file: true)
        }
        try Task.checkCancellation()
        return try prepare(data, secret: nil, limits: limits)
    }

    /// Dekodieren, Parsen, Mengengrenze, Platzhalter.
    nonisolated static func prepare(_ data: Data, secret: M3USecret?, limits: M3ULimits) throws -> [ParsedChannel] {
        let parsed = M3UParser(limits: limits.parser).parse(decodeText(data))
        if let maximum = limits.parser.maxChannels, parsed.count > maximum {
            throw ImportError.tooManyChannels(maximum)
        }
        guard !parsed.isEmpty else { throw ImportError.emptyPlaylist }
        guard let secret else { return parsed }
        return parsed.map { channel in
            var copy = channel
            copy.streamURL = M3UCredentials.redact(channel.streamURL, secret: secret)
            return copy
        }
    }

    /// Dekodiert Playlist-Bytes; UTF-8 mit Latin-1-Fallback.
    nonisolated static func decodeText(_ data: Data) -> String {
        String(data: data, encoding: .utf8)
            ?? String(data: data, encoding: .isoLatin1)
            ?? ""
    }

    nonisolated private static func map(_ error: PlaylistHTTPLoader.LoadError, limits: M3ULimits) -> ImportError {
        switch error {
        case .tooLarge: return .tooLarge(megabytes: megabytes(limits.maxBytes), file: false)
        case .deadlineExceeded: return .deadlineExceeded(seconds: Int(limits.totalTimeout))
        case .tooSlow: return .tooSlow
        case .redirectBlocked: return .network("Weiterleitung abgelehnt.")
        }
    }

    nonisolated private static func megabytes(_ bytes: Int) -> Int {
        let megabyte = 1024 * 1024
        return max(1, (bytes + megabyte - 1) / megabyte)
    }
}
