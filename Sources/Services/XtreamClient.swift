import Foundation

/// Holt Live-Sender direkt über die Xtream-Codes **player_api.php** und baut
/// daraus `ParsedChannel`-DTOs. Wird genutzt, weil viele Panels den klassischen
/// `get.php`-M3U-Link blockieren (HTTP 885 hinter Cloudflare), die player_api
/// aber bedienen.
///
/// Die Stream-Adressen der DTOs enthalten **keine** Zugangsdaten
/// (`XtreamStreamAddress.stored`); abspielbar macht sie erst der `StreamURLResolver`.
struct XtreamClient {
    let credentials: XtreamCredentials
    var limits: Limits = .standard
    var throttle: XtreamLoginThrottle = .shared
    var loader: XtreamHTTPLoader = .shared

    /// Grenzen für unvertraute Antworten des Panels (B01 · BUG-08).
    struct Limits: Sendable {
        /// Höchstens so lange ohne neue Daten je Anfrage.
        var idleTimeout: TimeInterval = 60
        /// Gemeinsame Frist für alle Anfragen eines Imports.
        var totalTimeout: TimeInterval = 180
        /// Größte angenommene Antwort je Anfrage.
        var maxResponseBytes: Int = 64 * 1024 * 1024
        /// Größte angenommene Anzahl Live-Streams.
        var maxStreams: Int = 100_000
        /// Längere Namen, Gruppen und tvg-IDs werden gekürzt.
        var maxTextLength: Int = 512
        /// Längere Logo-Adressen werden verworfen.
        var maxLogoURLLength: Int = 2_048

        static let standard = Limits()
    }

    enum XtreamError: LocalizedError, Equatable {
        case invalidHost
        case auth
        case network(String)
        case http(Int)
        case throttled(seconds: Int)
        case responseTooLarge(megabytes: Int)
        case deadlineExceeded(seconds: Int)
        case tooManyStreams(Int)
        case redirectBlocked

        var errorDescription: String? {
            switch self {
            case .invalidHost: return "Host ungültig. Bitte prüfe die Eingabe."
            case .auth: return "Anmeldung fehlgeschlagen. Benutzername/Passwort prüfen."
            case .network(let m): return "Netzwerkfehler: \(m)"
            case .http(let status): return "Netzwerkfehler: HTTP \(status)"
            case .throttled(let seconds):
                return "Zu viele fehlgeschlagene Anmeldungen. Bitte in \(seconds) Sekunden erneut versuchen."
            case .responseTooLarge(let megabytes):
                return "Netzwerkfehler: Die Antwort des Anbieters ist zu groß (mehr als \(megabytes) MB)."
            case .deadlineExceeded(let seconds):
                return "Netzwerkfehler: Der Anbieter hat nicht innerhalb von \(seconds) Sekunden vollständig geantwortet."
            case .tooManyStreams(let maximum):
                return "Die Senderliste ist zu groß (mehr als \(maximum.formatted(.number.locale(Locale(identifier: "de_DE")))) Sender)."
            case .redirectBlocked:
                return "Netzwerkfehler: Der Anbieter leitet auf einen anderen Server weiter. Die Zugangsdaten wurden dorthin nicht gesendet."
            }
        }
    }

    /// Lädt Kategorien + Live-Streams und liefert fertige Channel-DTOs.
    func fetchLiveChannels(output: XtreamOutput) async throws -> [ParsedChannel] {
        guard let base = credentials.baseURL(), let storedBase = credentials.storedBaseURL() else {
            throw XtreamError.invalidHost
        }
        let deadline = Date().addingTimeInterval(limits.totalTimeout)

        // 1) Auth prüfen – gebremst nach wiederholten Fehlschlägen (BUG-07).
        let throttleKey = XtreamLoginThrottle.key(for: base)
        if let remaining = throttle.remainingLock(for: throttleKey) {
            throw XtreamError.throttled(seconds: Int(remaining.rounded(.up)))
        }
        let auth: AuthResponse
        do {
            auth = try await get(action: nil, deadline: deadline)
        } catch XtreamError.http(let status) where status == 401 || status == 403 {
            throttle.recordFailure(for: throttleKey)
            throw XtreamError.http(status)
        }
        guard auth.userInfo?.auth == 1 else {
            throttle.recordFailure(for: throttleKey)
            throw XtreamError.auth
        }
        throttle.recordSuccess(for: throttleKey)

        // 2) Kategorien (id -> Name) für group-title. Defekte Einträge werden übersprungen (BUG-06).
        let categories: LossyList<Category> = try await get(action: "get_live_categories", deadline: deadline)
        let groupByID = Dictionary(
            categories.elements.compactMap { category in
                category.categoryName.map { (category.categoryId, String($0.prefix(limits.maxTextLength))) }
            },
            uniquingKeysWith: { first, _ in first }
        )

        // 3) Live-Streams -> ParsedChannel.
        let streams: LossyList<Stream> = try await get(action: "get_live_streams", deadline: deadline)
        let ext = output.streamExtension

        return streams.elements.compactMap { stream in
            guard let url = XtreamStreamAddress.stored(base: storedBase, streamID: stream.streamId,
                                                       fileExtension: ext) else { return nil }
            let tvg = stream.epgChannelId.flatMap { $0.isEmpty ? nil : String($0.prefix(limits.maxTextLength)) }
            let logo = stream.streamIcon.flatMap { icon -> URL? in
                guard !icon.isEmpty, icon.count <= limits.maxLogoURLLength else { return nil }
                return URL(string: icon)
            }
            return ParsedChannel(
                name: String(stream.name.prefix(limits.maxTextLength)),
                streamURL: url,
                logoURL: logo,
                group: stream.categoryId.flatMap { groupByID[$0] },
                tvgID: tvg
            )
        }
    }

    // MARK: - HTTP

    private func get<T: Decodable>(action: String?, deadline: Date) async throws -> T {
        guard let url = credentials.playerAPIURL(action: action) else { throw XtreamError.invalidHost }

        do {
            var request = URLRequest(url: url)
            request.cachePolicy = .reloadIgnoringLocalCacheData
            request.timeoutInterval = limits.idleTimeout
            let (data, response) = try await loader.data(for: request, maxBytes: limits.maxResponseBytes,
                                                        deadline: deadline)
            if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
                throw XtreamError.http(http.statusCode)
            }
            let decoder = JSONDecoder()
            decoder.userInfo[LossyList<Stream>.maxCountKey] = limits.maxStreams
            return try decoder.decode(T.self, from: data)
        } catch let error as XtreamError {
            throw error
        } catch let error as XtreamHTTPLoader.LoadError {
            switch error {
            case .tooLarge:
                let megabyte = 1024 * 1024
                throw XtreamError.responseTooLarge(megabytes: max(1, (limits.maxResponseBytes + megabyte - 1) / megabyte))
            case .deadlineExceeded, .tooSlow: throw XtreamError.deadlineExceeded(seconds: Int(limits.totalTimeout))
            case .redirectBlocked: throw XtreamError.redirectBlocked
            }
        } catch let error as LossyListError {
            switch error {
            case .tooMany(let maximum): throw XtreamError.tooManyStreams(maximum)
            }
        } catch let error as DecodingError {
            throw XtreamError.network("Unerwartete Serverantwort (\(error.localizedDescription))")
        } catch let error as CancellationError {
            throw error
        } catch let error as URLError where error.code == .cancelled && Task.isCancelled {
            throw CancellationError()
        } catch {
            throw XtreamError.network(error.localizedDescription)
        }
    }

    // MARK: - DTOs (player_api.php)

    private struct AuthResponse: Decodable {
        let userInfo: UserInfo?
        enum CodingKeys: String, CodingKey { case userInfo = "user_info" }
        struct UserInfo: Decodable {
            let auth: Int?
        }
    }

    private struct Category: Decodable {
        let categoryId: String
        let categoryName: String?
        enum CodingKeys: String, CodingKey {
            case categoryId = "category_id"
            case categoryName = "category_name"
        }

        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            categoryId = try c.decode(FlexibleID.self, forKey: .categoryId).value
            categoryName = try? c.decodeIfPresent(String.self, forKey: .categoryName)
        }
    }

    private struct Stream: Decodable {
        let name: String
        let streamId: String
        let streamIcon: String?
        let epgChannelId: String?
        let categoryId: String?
        enum CodingKeys: String, CodingKey {
            case name
            case streamId = "stream_id"
            case streamIcon = "stream_icon"
            case epgChannelId = "epg_channel_id"
            case categoryId = "category_id"
        }

        /// Nur `stream_id` ist Pflicht; fehlt sie, wird der Eintrag übersprungen. Alle übrigen Felder
        /// werden tolerant gelesen, ein fehlender oder `null`-Name wird zu `""` (wie ein leerer Name).
        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            streamId = try c.decode(FlexibleID.self, forKey: .streamId).value
            name = (try? c.decodeIfPresent(String.self, forKey: .name)) ?? ""
            streamIcon = try? c.decodeIfPresent(String.self, forKey: .streamIcon)
            epgChannelId = try? c.decodeIfPresent(String.self, forKey: .epgChannelId)
            categoryId = (try? c.decodeIfPresent(FlexibleID.self, forKey: .categoryId))?.value
        }
    }

    /// `stream_id`/`category_id` kommen je nach Panel als Int ODER String.
    private struct FlexibleID: Decodable {
        let value: String
        init(from decoder: Decoder) throws {
            let c = try decoder.singleValueContainer()
            if let i = try? c.decode(Int.self) { value = String(i) }
            else { value = try c.decode(String.self) }
        }
    }
}

private enum LossyListError: Error {
    case tooMany(Int)
}

/// Liste, die defekte Einträge überspringt, statt die ganze Antwort zu verwerfen (B01 · BUG-06).
/// Ist die Antwort selbst keine Liste (z. B. `null` oder ein Objekt), scheitert die Dekodierung weiterhin.
private struct LossyList<Element: Decodable>: Decodable {
    static var maxCountKey: CodingUserInfoKey { CodingUserInfoKey(rawValue: "b01.maxCount")! }

    let elements: [Element]

    init(from decoder: Decoder) throws {
        var container = try decoder.unkeyedContainer()
        if let maximum = decoder.userInfo[Self.maxCountKey] as? Int, let count = container.count, count > maximum {
            throw LossyListError.tooMany(maximum)
        }
        var result: [Element] = []
        result.reserveCapacity(container.count ?? 0)
        while !container.isAtEnd {
            if let element = try? container.decode(Element.self) {
                result.append(element)
            } else {
                _ = try? container.decode(Skipped.self)
            }
        }
        elements = result
    }

    private struct Skipped: Decodable {
        init(from decoder: Decoder) throws {}
    }
}
