import Foundation

/// Ausgabeformat einer Xtream-Codes-Playlist. Bestimmt die Datei-Endung der
/// Stream-URLs in der M3U und damit die nötige Wiedergabe-Engine.
enum XtreamOutput: String, CaseIterable, Identifiable {
    /// HLS (.m3u8) – spielt mit dem eingebauten AVKit-Player.
    case hls = "hls"
    /// Roher MPEG-TS (.ts) – benötigt VLCKit (siehe README).
    case mpegts = "mpegts"

    var id: String { rawValue }

    var label: String {
        switch self {
        case .hls: return "HLS (.m3u8)"
        case .mpegts: return "MPEG-TS (.ts)"
        }
    }

    var hint: String {
        switch self {
        case .hls: return "Spielt direkt mit AVKit – kein VLCKit nötig."
        case .mpegts: return "Originalformat des Anbieters – benötigt VLCKit."
        }
    }

    /// Datei-Endung der Live-Stream-URL (`/live/user/pass/<id>.<ext>`).
    var streamExtension: String {
        switch self {
        case .hls: return "m3u8"
        case .mpegts: return "ts"
        }
    }
}

/// Die geheimen Teile eines Xtream-Zugangs. Liegen ausschließlich im Schlüsselbund
/// (`XtreamCredentialStore`), nie in der Datenbank (B01 · BUG-01).
struct XtreamSecret: Codable, Equatable, Sendable {
    /// Normalisierte Basisadresse, wie `XtreamCredentials.baseURL()` sie liefert – einschließlich
    /// einer etwa eingegebenen Benutzerinfo (`u:pw@`).
    var host: String
    /// Benutzername, an den Rändern um Leerzeichen gekürzt.
    var username: String
    /// Passwort, an den Rändern um Leerzeichen gekürzt.
    var password: String
}

/// Xtream-Codes-Zugangsdaten. Baut daraus die player_api-/get.php-Links.
struct XtreamCredentials {
    var host: String
    var username: String
    var password: String

    init(host: String, username: String, password: String) {
        self.host = host
        self.username = username
        self.password = password
    }

    init(secret: XtreamSecret) {
        self.init(host: secret.host, username: secret.username, password: secret.password)
    }

    /// Rekonstruiert die Zugangsdaten aus einer **alten** gespeicherten player_api-URL
    /// (`http://host[:port]/player_api.php?username=…&password=…`), wie sie Versionen bis 1.1
    /// in `Playlist.sourceURL` abgelegt haben. Nur noch für die Migration in den Schlüsselbund.
    /// Die Basis bleibt dabei exakt erhalten, einschließlich Benutzerinfo und Port.
    init?(legacyPlayerAPIURL url: URL) {
        guard var comps = URLComponents(url: url, resolvingAgainstBaseURL: false),
              comps.host != nil else { return nil }
        let items = comps.queryItems ?? []
        guard let user = items.first(where: { $0.name == "username" })?.value,
              let pass = items.first(where: { $0.name == "password" })?.value else { return nil }
        comps.path = ""
        comps.query = nil
        guard let base = comps.url else { return nil }
        self.host = base.absoluteString
        self.username = user
        self.password = pass
    }

    var trimmedUsername: String { username.trimmingCharacters(in: .whitespaces) }
    var trimmedPassword: String { password.trimmingCharacters(in: .whitespaces) }

    /// Normalisierte Basis-URL (`http[s]://host[:port]`), ohne Pfad/Query.
    /// Ohne Schema wird `http://` ergänzt, weil viele IPTV-Panels nur HTTP bedienen.
    /// Ein ausdrücklich eingegebenes `https://` bleibt erhalten (B01 · BUG-02).
    func baseURL() -> URL? {
        var h = host.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !h.isEmpty else { return nil }

        let lower = h.lowercased()
        if lower.hasPrefix("https://") {
            h = "https://" + h.dropFirst("https://".count)
        } else if !lower.hasPrefix("http://") {
            h = "http://" + h
        }
        while h.hasSuffix("/") { h.removeLast() }

        guard var comps = URLComponents(string: h), comps.host != nil else { return nil }
        comps.path = ""
        comps.query = nil
        return comps.url
    }

    /// True, wenn die Anfragen verschlüsselt (`https`) laufen.
    var usesHTTPS: Bool {
        baseURL()?.scheme?.lowercased() == "https"
    }

    /// player_api.php-Adresse **mit** Zugangsdaten – nur für die Anfrage selbst, nie zum Speichern.
    func playerAPIURL(action: String? = nil) -> URL? {
        guard var comps = baseURL().flatMap({ URLComponents(url: $0, resolvingAgainstBaseURL: false) }) else {
            return nil
        }
        comps.path = "/player_api.php"
        var items = [
            URLQueryItem(name: "username", value: trimmedUsername),
            URLQueryItem(name: "password", value: trimmedPassword)
        ]
        if let action { items.append(URLQueryItem(name: "action", value: action)) }
        XtreamURLEncoding.setQueryItems(items, on: &comps)
        return comps.url
    }

    /// Basis-URL ohne Benutzerinfo – Grundlage aller gespeicherten Adressen.
    func storedBaseURL() -> URL? {
        guard var comps = baseURL().flatMap({ URLComponents(url: $0, resolvingAgainstBaseURL: false) }) else {
            return nil
        }
        comps.user = nil
        comps.password = nil
        return comps.url
    }

    /// Gespeicherte `sourceURL` einer Xtream-Playlist: `http[s]://host[:port]/player_api.php`,
    /// **ohne** Zugangsdaten (B01 · BUG-01).
    func storedSourceURL() -> URL? {
        guard var comps = storedBaseURL().flatMap({ URLComponents(url: $0, resolvingAgainstBaseURL: false) }) else {
            return nil
        }
        comps.path = "/player_api.php"
        return comps.url
    }

    /// Geheime Teile für den Schlüsselbund.
    func secret() -> XtreamSecret? {
        guard let base = baseURL() else { return nil }
        return XtreamSecret(host: base.absoluteString, username: trimmedUsername, password: trimmedPassword)
    }

    /// Erzeugt den `get.php`-Playlist-Link für das gewählte Ausgabeformat.
    /// Hinweis: Manche Panels (z. B. hinter Cloudflare) blockieren `get.php` –
    /// dann wird stattdessen die player_api genutzt (siehe `XtreamClient`).
    func playlistURL(output: XtreamOutput) -> URL? {
        guard var comps = baseURL().flatMap({ URLComponents(url: $0, resolvingAgainstBaseURL: false) }) else {
            return nil
        }
        comps.path = "/get.php"
        XtreamURLEncoding.setQueryItems([
            URLQueryItem(name: "username", value: trimmedUsername),
            URLQueryItem(name: "password", value: trimmedPassword),
            URLQueryItem(name: "type", value: "m3u_plus"),
            URLQueryItem(name: "output", value: output.rawValue)
        ], on: &comps)
        return comps.url
    }

    var isComplete: Bool {
        ![host, username, password].contains { $0.trimmingCharacters(in: .whitespaces).isEmpty }
    }
}

/// Kodierung von Benutzername und Passwort (B01 · BUG-05).
enum XtreamURLEncoding {
    /// Erlaubte Zeichen in einem Pfadabschnitt: wie `urlPathAllowed`, aber ohne `/`.
    private static let pathSegmentAllowed: CharacterSet = {
        var set = CharacterSet.urlPathAllowed
        set.remove(charactersIn: "/")
        return set
    }()

    /// Kodiert einen Wert als **einen** Pfadabschnitt (`/`, `?`, `#`, `%` werden maskiert).
    static func pathSegment(_ value: String) -> String {
        value.addingPercentEncoding(withAllowedCharacters: pathSegmentAllowed) ?? value
    }

    /// Setzt Query-Parameter und kodiert zusätzlich `+`, das PHP-Panels sonst als Leerzeichen lesen.
    static func setQueryItems(_ items: [URLQueryItem], on comps: inout URLComponents) {
        comps.queryItems = items
        comps.percentEncodedQuery = comps.percentEncodedQuery?.replacingOccurrences(of: "+", with: "%2B")
    }
}

/// Stream-Adressen einer Xtream-Playlist.
///
/// Gespeichert wird `<Basis ohne Benutzerinfo>/live/<stream_id>.<ext>` – ohne Zugangsdaten.
/// Abspielbar wird die Adresse erst durch `playable(stored:secret:)`, die Benutzername und
/// Passwort aus dem Schlüsselbund einsetzt (B01 · BUG-01). Aufrufer: `StreamURLResolver`.
enum XtreamStreamAddress {
    static let liveMarker = "/live/"

    /// Gespeicherte Adresse ohne Zugangsdaten.
    static func stored(base: URL, streamID: String, fileExtension: String) -> URL? {
        URL(string: base.absoluteString + liveMarker + streamID + "." + fileExtension)
    }

    /// Abspielbare Adresse `<Basis>/live/<benutzer>/<passwort>/<stream_id>.<ext>`.
    static func playable(stored: URL, secret: XtreamSecret) -> URL? {
        guard let rest = liveSuffix(of: stored.absoluteString) else { return nil }
        let user = XtreamURLEncoding.pathSegment(secret.username)
        let pass = XtreamURLEncoding.pathSegment(secret.password)
        return URL(string: secret.host + liveMarker + user + "/" + pass + "/" + rest)
    }

    /// Alles nach dem ersten `/live/` hinter `://`.
    static func liveSuffix(of address: String) -> Substring? {
        guard let schemeEnd = address.range(of: "://"),
              let marker = address.range(of: liveMarker, range: schemeEnd.upperBound..<address.endIndex) else {
            return nil
        }
        return address[marker.upperBound...]
    }
}
