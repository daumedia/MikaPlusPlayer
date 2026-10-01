import Foundation

/// Zugangsdaten, die in einer M3U-Adresse stecken (B02 · BUG-01). Liegen ausschließlich im Schlüsselbund
/// (`XtreamCredentialStore`, Konto = `Playlist.id`), nie in der Datenbank.
struct M3USecret: Codable, Equatable, Sendable {
    /// Die eingegebene Adresse unverändert, einschließlich Zugangsdaten – nur für den Abruf beim Aktualisieren.
    var sourceURL: String
    var username: String?
    var password: String
    /// Nur wenn die Adresse Benutzerinfo **und** ein anderes Passwort in der Query trägt (Review R-03): Zugangsdaten
    /// der Benutzerinfo. Sonst `nil` – dann gilt `username`/`password` auch für die Benutzerinfo.
    var infoUsername: String? = nil
    var infoPassword: String? = nil
}

/// Trennt Zugangsdaten aus M3U-Adressen heraus und setzt sie beim Abspielen wieder ein.
///
/// Erkannt werden die Query-Parameter `username`/`password` (z. B. `get.php`-Links der Anbieter) und eine
/// Benutzerinfo `user:pass@host`. Gespeichert wird die Adresse mit **Platzhaltern** an denselben Stellen,
/// damit sie ohne Geheimnis in der Datenbank stehen kann und trotzdem erkennbar bleibt, dass sie Zugangsdaten
/// braucht. Stream-Adressen der Liste werden genauso behandelt: Jeder Pfadabschnitt und jeder Query-Wert, der
/// dem Passwort entspricht, wird ersetzt; der Benutzername nur direkt vor dem Passwort (`/user/pass/…`), in
/// Query-Parametern `username`/`user` und in der Benutzerinfo. Das Ersetzen ist verlustfrei: `restore` bildet
/// wieder die abspielbare Adresse.
enum M3UCredentials {
    /// Platzhalter nur aus nicht reservierten URL-Zeichen, damit sie jede Adressbildung unverändert überstehen.
    enum Marker {
        static let pathUser = "_mikaplus_pfad_benutzer_"
        static let pathPassword = "_mikaplus_pfad_passwort_"
        static let queryUser = "_mikaplus_query_benutzer_"
        static let queryPassword = "_mikaplus_query_passwort_"
        static let infoUser = "_mikaplus_info_benutzer_"
        static let infoPassword = "_mikaplus_info_passwort_"
        /// Benutzerinfo mit eigenen Zugangsdaten (`M3USecret.infoUsername`/`infoPassword`, Review R-03)
        static let secondInfoUser = "_mikaplus_info2_benutzer_"
        static let secondInfoPassword = "_mikaplus_info2_passwort_"
        static let all = [pathUser, pathPassword, queryUser, queryPassword, infoUser, infoPassword,
                          secondInfoUser, secondInfoPassword]
    }

    private static let userQueryNames: Set<String> = ["username", "user"]

    /// Zerlegt eine M3U-Adresse. `nil`, wenn sie kein Passwort trägt (dann wird sie unverändert gespeichert) oder
    /// schon Platzhalter statt Zugangsdaten hat.
    static func split(_ url: URL) -> (stored: URL, secret: M3USecret)? {
        guard !needsSecret(url), let comps = URLComponents(url: url, resolvingAgainstBaseURL: false) else { return nil }
        let items = comps.queryItems ?? []
        let queryPassword = items.first { $0.name.lowercased() == "password" }?.value.flatMap { $0.isEmpty ? nil : $0 }
        let infoPassword = comps.password.flatMap { $0.isEmpty ? nil : $0 }
        guard let password = queryPassword ?? infoPassword else { return nil }
        let username: String?
        if queryPassword != nil {
            username = items.first { $0.name.lowercased() == "username" }?.value ?? comps.user
        } else {
            username = comps.user
        }
        var secret = M3USecret(sourceURL: url.absoluteString, username: username, password: password)
        // Review R-03: Benutzerinfo mit eigenem Passwort neben `password=` in der Query → beide in den Schlüsselbund.
        if queryPassword != nil, let infoPassword, infoPassword != password {
            secret.infoPassword = infoPassword
            secret.infoUsername = comps.user
        }
        return (redact(url, secret: secret), secret)
    }

    /// Adresse mit Platzhaltern statt Zugangsdaten.
    static func redact(_ url: URL, secret: M3USecret) -> URL {
        guard var comps = URLComponents(url: url, resolvingAgainstBaseURL: false) else { return url }
        let user = secret.username.flatMap { $0.isEmpty ? nil : $0 }
        let password = secret.password
        var changed = false

        // Benutzerinfo; trägt die Adresse dort eigene Zugangsdaten (Review R-03), bekommen diese eigene Platzhalter
        let secondPassword = secret.infoPassword
        let secondUser = secondPassword == nil ? nil : secret.infoUsername.flatMap { $0.isEmpty ? nil : $0 }
        if let secondPassword, comps.password == secondPassword {
            comps.percentEncodedPassword = Marker.secondInfoPassword
            changed = true
            if let secondUser, comps.user == secondUser {
                comps.percentEncodedUser = Marker.secondInfoUser
            }
        } else {
            if comps.password.map({ $0 == password }) == true {
                comps.percentEncodedPassword = Marker.infoPassword
                changed = true
            }
            if let user, comps.user == user {
                comps.percentEncodedUser = Marker.infoUser
                changed = true
            }
        }

        // Pfadabschnitte: Passwort überall, Benutzername direkt davor
        var segments = comps.percentEncodedPath.components(separatedBy: "/")
        for index in segments.indices where decoded(segments[index]) == password {
            segments[index] = Marker.pathPassword
            changed = true
            if let user, index > 0, decoded(segments[index - 1]) == user {
                segments[index - 1] = Marker.pathUser
            }
        }
        if changed { comps.percentEncodedPath = segments.joined(separator: "/") }

        // Query-Werte
        if var items = comps.percentEncodedQueryItems {
            var queryChanged = false
            for index in items.indices {
                guard let value = items[index].value.flatMap(decoded) else { continue }
                if value == password {
                    items[index].value = Marker.queryPassword
                    queryChanged = true
                } else if let user, value == user, userQueryNames.contains(items[index].name.lowercased()) {
                    items[index].value = Marker.queryUser
                    queryChanged = true
                }
            }
            if queryChanged {
                comps.percentEncodedQueryItems = items
                changed = true
            }
        }
        guard changed, let result = comps.url else { return url }
        return result
    }

    /// True, wenn die gespeicherte Adresse Platzhalter trägt, also Zugangsdaten aus dem Schlüsselbund braucht.
    static func needsSecret(_ url: URL) -> Bool {
        let s = url.absoluteString
        return Marker.all.contains { s.contains($0) }
    }

    /// Setzt die Zugangsdaten wieder ein. `nil`, wenn ein Benutzername gebraucht wird, der fehlt.
    static func restore(_ stored: URL, secret: M3USecret) -> URL? {
        var s = stored.absoluteString
        guard Marker.all.contains(where: { s.contains($0) }) else { return stored }
        let user = secret.username ?? ""
        if user.isEmpty, [Marker.pathUser, Marker.queryUser, Marker.infoUser].contains(where: { s.contains($0) }) { return nil }
        if s.contains(Marker.secondInfoPassword) || s.contains(Marker.secondInfoUser) {
            guard let secondPassword = secret.infoPassword else { return nil }
            let secondUser = secret.infoUsername ?? ""
            if secondUser.isEmpty, s.contains(Marker.secondInfoUser) { return nil }
            s = s.replacingOccurrences(of: Marker.secondInfoPassword, with: userInfo(secondPassword, allowed: .urlPasswordAllowed))
            s = s.replacingOccurrences(of: Marker.secondInfoUser, with: userInfo(secondUser, allowed: .urlUserAllowed))
        }
        s = s.replacingOccurrences(of: Marker.pathPassword, with: XtreamURLEncoding.pathSegment(secret.password))
        s = s.replacingOccurrences(of: Marker.pathUser, with: XtreamURLEncoding.pathSegment(user))
        s = s.replacingOccurrences(of: Marker.queryPassword, with: queryValue(secret.password))
        s = s.replacingOccurrences(of: Marker.queryUser, with: queryValue(user))
        s = s.replacingOccurrences(of: Marker.infoPassword, with: userInfo(secret.password, allowed: .urlPasswordAllowed))
        s = s.replacingOccurrences(of: Marker.infoUser, with: userInfo(user, allowed: .urlUserAllowed))
        return URL(string: s)
    }

    // MARK: - Kodierung

    private static func decoded(_ raw: String) -> String? {
        raw.removingPercentEncoding ?? raw
    }

    private static let queryValueAllowed: CharacterSet = {
        var set = CharacterSet.urlQueryAllowed
        set.remove(charactersIn: "&=+#")
        return set
    }()

    private static func queryValue(_ value: String) -> String {
        value.addingPercentEncoding(withAllowedCharacters: queryValueAllowed) ?? value
    }

    private static func userInfo(_ value: String, allowed: CharacterSet) -> String {
        var set = allowed
        set.remove(charactersIn: ":@/")
        return value.addingPercentEncoding(withAllowedCharacters: set) ?? value
    }
}
