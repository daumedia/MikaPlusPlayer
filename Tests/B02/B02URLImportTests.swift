import XCTest
import SwiftData
import Security
@testable import MikaPlusPlayer

/// B02 · M3U-Import — Import per URL über den echten Pfad (`PlaylistImporter.importFromURL` → `URLSession.shared`)
/// gegen `B02Server` auf 127.0.0.1. AK-06 … AK-15, AK-25 (URL), AK-26, AK-28 (schnelle Fälle), AK-33, AK-36, EC-15 … EC-17.
final class B02URLImportTests: B02TestCase {

    // MARK: AK-06

    /// AK-06 (Datenteil): HTTP 200 mit N = 2 gültigen Einträgen → Playlist mit Quelladresse, aktualisierbar, „2 Sender".
    @MainActor func testAK06_ImportLegtPlaylistMitNSendernAn() async throws {
        let c = try B02.memory()
        let p = try await B02.importURL(server.url("/liste.m3u"), c.mainContext).get()
        B02.log("AK-06|\(B02.describe(p))|anfragen=\(server.requests.map(\.requestLine))")
        XCTAssertEqual(p.channelCount, 2)
        XCTAssertEqual(p.channels.count, 2)
        XCTAssertTrue(p.isRemote)
        XCTAssertFalse(p.isXtream)
        XCTAssertNotNil(p.lastRefreshed)
        XCTAssertEqual(Set(p.channels.map(\.playlistID)), [p.id])
        XCTAssertEqual(B02.count(Playlist.self, c.mainContext), 1)
    }

    // MARK: AK-07

    /// AK-07: ohne Namen → Host ohne Schema und Port; ohne Host → „Playlist"; eingegebener Name exakt (auch „   ").
    @MainActor func testAK07_NameAusHostOderEingabe() async throws {
        let c = try B02.memory()
        let dir = try tempDir("ak07")
        let file = dir.appendingPathComponent("lokal.m3u")
        try B02.zweiSenderData.write(to: file)
        let data = "data:audio/x-mpegurl;base64," + B02.zweiSenderData.base64EncodedString()
        let cases: [(String, String, String)] = [
            (server.url("/liste.m3u"), "", "127.0.0.1"),
            ("http://localhost:\(server.port)/liste.m3u", "", "localhost"),
            (file.absoluteString, "", "Playlist"),
            (data, "", "Playlist"),
            (server.url("/liste.m3u"), "   ", "   "),
            (server.url("/liste.m3u"), "  Mein Name  ", "  Mein Name  ")
        ]
        for (input, name, expected) in cases {
            let p = try await B02.importURL(input, name: name, c.mainContext).get()
            B02.log("AK-07|eingabe=\(input.prefix(60))|name=\(name.debugDescription)|ergebnis=\(p.name.debugDescription)")
            XCTAssertEqual(p.name, expected, input)
        }
    }

    // MARK: AK-08

    /// AK-08 (a)–(e): Trimmen, genau ein GET, Prozentkodierung im Pfad, kein Fragment, gespeichert die gekürzte Eingabe.
    @MainActor func testAK08_EingabeAnfrageUndGespeicherteAdresse() async throws {
        let c = try B02.memory()
        let cases: [(input: String, target: String, stored: String)] = [
            ("  \(server.url("/liste.m3u"))  ", "/liste.m3u", server.url("/liste.m3u")),
            ("\n\t\(server.url("/liste.m3u"))\n", "/liste.m3u", server.url("/liste.m3u")),
            ("HTTP://\(server.hostPort)/gross.m3u", "/gross.m3u", "HTTP://\(server.hostPort)/gross.m3u"),
            (server.url("/mit leerzeichen.m3u"), "/mit%20leerzeichen.m3u", server.url("/mit%20leerzeichen.m3u")),
            (server.url("/ümlaut.m3u"), "/%C3%BCmlaut.m3u", server.url("/%C3%BCmlaut.m3u")),
            (server.url("/liste.m3u#fragment"), "/liste.m3u", server.url("/liste.m3u#fragment")),
            (server.url("/liste.m3u?token=qa-token&x=1"), "/liste.m3u?token=qa-token&x=1", server.url("/liste.m3u?token=qa-token&x=1")),
            // B02 · BUG-01: Benutzerinfo mit Passwort → Platzhalter in der Datenbank, Zugangsdaten im Schlüsselbund
            ("http://qa-user:qa-pass-b02ak08@\(server.hostPort)/liste.m3u", "/liste.m3u",
             "http://\(M3UCredentials.Marker.infoUser):\(M3UCredentials.Marker.infoPassword)@\(server.hostPort)/liste.m3u")
        ]
        for tc in cases {
            server.resetLog()
            let p = try await B02.importURL(tc.input, c.mainContext).get()
            let reqs = server.requests
            B02.log("AK-08|eingabe=\(tc.input.debugDescription)|anfragen=\(reqs.map(\.requestLine))|gespeichert=\(p.sourceURL?.absoluteString ?? "nil")")
            XCTAssertEqual(reqs.count, 1, tc.input)
            XCTAssertEqual(reqs.first?.method, "GET")
            XCTAssertEqual(reqs.first?.target, tc.target, tc.input)
            XCTAssertEqual(p.sourceURL?.absoluteString, tc.stored, tc.input)
        }
    }

    // MARK: AK-09 / AK-25 (URL)

    /// AK-09: gültige M3U unabhängig vom `Content-Type`; `charset` wird nicht beachtet. AK-25 über URL: UTF-8 (± BOM), Latin-1.
    @MainActor func testAK09_AK25_ContentTypeUndKodierungUeberURL() async throws {
        let c = try B02.memory()
        for type in ["audio/x-mpegurl", "application/vnd.apple.mpegurl", "text/html", "application/octet-stream", "image/png"] {
            server.handler = { _ in B02Server.ok(B02.zweiSenderData, type: type) }
            let r = await B02.importURL(server.url("/typ"), c.mainContext)
            B02.log("AK-09|contentType=\(type)|ergebnis=\(B02.message(r) ?? "OK")")
            XCTAssertNil(B02.message(r), type)
        }
        let text = "#EXTINF:-1 group-title=\"Österreich\",ORF Eins Ä\nhttp://h/a.ts\n"
        let latin1 = try XCTUnwrap(text.data(using: .isoLatin1))
        let utf8 = Data(text.utf8)
        let bom = Data([0xEF, 0xBB, 0xBF]) + utf8
        let cases: [(String, Data, String)] = [
            ("utf8 + Kopfzeile iso-8859-1", utf8, "text/plain; charset=iso-8859-1"),
            ("latin1 + Kopfzeile utf-8", latin1, "text/plain; charset=utf-8"),
            ("utf8 mit BOM", bom, "audio/x-mpegurl"),
            ("latin1 ohne Angabe", latin1, "audio/x-mpegurl")
        ]
        for (label, body, type) in cases {
            server.handler = { _ in B02Server.ok(body, type: type) }
            let p = try await B02.importURL(server.url("/kodierung"), c.mainContext).get()
            let ch = try XCTUnwrap(p.channels.first)
            B02.log("AK-25|url|\(label)|name=\(ch.name.debugDescription)|gruppe=\(ch.group ?? "nil")")
            XCTAssertEqual(ch.name, "ORF Eins Ä", label)
            XCTAssertEqual(ch.group, "Österreich", label)
        }
    }

    // MARK: AK-10 / EC-16

    /// AK-10, EC-16: 200/203 importieren; 204 und leerer Körper → „keine gültigen Sender"; sonst „Netzwerkfehler: HTTP <n>".
    @MainActor func testAK10_EC16_Statuscodes() async throws {
        let c = try B02.memory()
        server.handler = { req in
            let code = Int(req.path.dropFirst()) ?? 500
            if code == 204 { return .bytes(B02Server.http(204, reason: "No Content")) }
            if (200..<300).contains(code) { return .bytes(B02Server.http(code, headers: [("Content-Type", "audio/x-mpegurl")], body: B02.zweiSenderData)) }
            return .bytes(B02Server.http(code, headers: [("Content-Type", "audio/x-mpegurl")], body: B02.zweiSenderData))
        }
        var lines: [String] = []
        for code in [200, 203] {
            let r = await B02.importURL(server.url("/\(code)"), c.mainContext)
            lines.append("\(code)=\(B02.message(r) ?? "OK")")
            XCTAssertNil(B02.message(r), "\(code)")
        }
        let r204 = await B02.importURL(server.url("/204"), c.mainContext)
        lines.append("204=\(B02.message(r204) ?? "OK")")
        XCTAssertEqual(B02.message(r204), "Die Playlist enthält keine gültigen Sender.")
        server.handler = { _ in B02Server.ok(Data()) }
        let leer = await B02.importURL(server.url("/leer"), c.mainContext)
        lines.append("200-leer=\(B02.message(leer) ?? "OK")")
        XCTAssertEqual(B02.message(leer), "Die Playlist enthält keine gültigen Sender.")
        server.handler = { req in .bytes(B02Server.http(Int(req.path.dropFirst()) ?? 500, headers: [("Content-Type", "audio/x-mpegurl")], body: B02.zweiSenderData)) }
        for code in [300, 304, 400, 401, 403, 404, 407, 429, 500, 503] {
            server.resetLog()
            let r = await B02.importURL(server.url("/\(code)"), c.mainContext)
            lines.append("\(code)=\(B02.message(r) ?? "OK")(anfragen \(server.requests.count))")
            XCTAssertEqual(B02.message(r), "Netzwerkfehler: HTTP \(code)", "\(code)")
        }
        B02.log("AK-10|\(lines.joined(separator: "|"))")
        XCTAssertEqual(B02.count(Playlist.self, c.mainContext), 2, "nur 200 und 203 legen an")
    }

    // MARK: AK-11

    /// AK-11: Weiterleitungen werden ohne Rückfrage befolgt, auch auf anderen Host/Port; Ziel bekommt genau `Location`;
    /// gespeichert wird die eingegebene Adresse; Schleife → 21 Anfragen und Meldung; `file:` als Ziel → Rechte-Meldung.
    @MainActor func testAK11_Weiterleitungen() async throws {
        let c = try B02.memory()
        let ziel = try extraServer { _ in B02Server.ok(B02.zweiSenderData) }
        let port = server.port
        server.handler = { req in
            switch req.path {
            case "/301": return B02Server.redirect(301, to: "http://127.0.0.1:\(port)/200.m3u")
            case "/302-fremd": return B02Server.redirect(302, to: "http://localhost:\(ziel.port)/ziel.m3u")
            case "/307-query": return B02Server.redirect(307, to: "http://localhost:\(ziel.port)/ziel.m3u?username=qa-user&password=qa-pass-b02ak11")
            case "/schleife": return B02Server.redirect(302, to: "/schleife")
            case "/nach-file": return B02Server.redirect(302, to: "file:///etc/hosts")
            default: return B02Server.ok(B02.zweiSenderData)
            }
        }
        struct Case { let path: String; let message: String?; let sourceCount: Int; let zielTargets: [String] }
        let cases = [
            Case(path: "/301", message: nil, sourceCount: 2, zielTargets: []),
            Case(path: "/302-fremd", message: nil, sourceCount: 1, zielTargets: ["/ziel.m3u"]),
            Case(path: "/307-query", message: nil, sourceCount: 1, zielTargets: ["/ziel.m3u?username=qa-user&password=qa-pass-b02ak11"]),
            Case(path: "/schleife", message: "Netzwerkfehler: too many HTTP redirects", sourceCount: 21, zielTargets: []),
            Case(path: "/nach-file", message: "Netzwerkfehler: You do not have permission to access the requested resource.", sourceCount: 1, zielTargets: [])
        ]
        for tc in cases {
            server.resetLog(); ziel.resetLog()
            let r = await B02.importURL(server.url(tc.path), c.mainContext)
            let stored = (try? r.get())?.sourceURL?.absoluteString
            B02.log("AK-11|\(tc.path)|ergebnis=\(B02.message(r) ?? "OK")|quelle=\(server.requests.count)|ziel=\(ziel.requests.map(\.target))|gespeichert=\(stored ?? "-")")
            XCTAssertEqual(B02.message(r), tc.message, tc.path)
            XCTAssertEqual(server.requests.count, tc.sourceCount, tc.path)
            XCTAssertEqual(ziel.requests.map(\.target), tc.zielTargets, tc.path)
            if tc.message == nil { XCTAssertEqual(stored, server.url(tc.path), tc.path) }
        }
    }

    // MARK: AK-12 (schnelle Fälle) / EC-17 (schneller Fall)

    /// AK-12: ohne erkennbares Schema → „ungültig", nichts gesendet; Schema ohne abrufbares Ziel → Systemmeldung.
    /// EC-17: `ftp://` mit Benutzerinfo auf geschlossenem Port → sofort „unknown error". (`ftp://` ohne Benutzerinfo: `B02LangsamTests`.)
    @MainActor func testAK12_EC17_OhneSchemaUndNichtAbrufbar() async throws {
        let c = try B02.memory()
        let closed = B02Server(); try closed.start(); let closedPort = closed.port; closed.stop()
        let cases: [(String, String)] = [
            ("\(server.hostPort)/liste.m3u", "Die angegebene URL ist ungültig."),
            ("example.invalid/liste.m3u", "Die angegebene URL ist ungültig."),
            ("   ", "Die angegebene URL ist ungültig."),
            ("", "Die angegebene URL ist ungültig."),
            ("localhost:\(server.port)/liste.m3u", "Netzwerkfehler: unsupported URL"),
            ("javascript:alert(1)", "Netzwerkfehler: unsupported URL"),
            ("http://", "Netzwerkfehler: Could not connect to the server."),
            ("http:///liste.m3u", "Netzwerkfehler: Could not connect to the server."),
            ("ftp://qa-user:qa-pass-b02ec17@127.0.0.1:\(closedPort)/x.m3u", "Netzwerkfehler: unknown error")
        ]
        for (input, expected) in cases {
            server.resetLog()
            let t = Date()
            let r = await B02.importURL(input, c.mainContext)
            B02.log("AK-12|eingabe=\(input.debugDescription)|meldung=\(B02.message(r) ?? "OK")|dauer=\(B02.f2(Date().timeIntervalSince(t)))s|anfragenAmServer=\(server.connectionCount)")
            XCTAssertEqual(B02.message(r), expected, input)
            XCTAssertEqual(server.connectionCount, 0, input)
        }
        XCTAssertEqual(B02.count(Playlist.self, c.mainContext), 0)
    }

    // MARK: AK-13

    /// AK-13 ⚠ (OF-02): `file:` und `data:` im URL-Feld werden importiert; „Playlist", aktualisierbar; bei `data:` steht der
    /// ganze Inhalt als Quelladresse in der Datenbank.
    @MainActor func testAK13_FileUndDataImURLFeld() async throws {
        let dir = try tempDir("ak13")
        let (container, storeURL) = try B02.fileContainer(in: dir)
        let ctx = container.mainContext
        let file = dir.appendingPathComponent("lokal.m3u")
        try B02.zweiSenderData.write(to: file)
        let pf = try await B02.importURL(file.absoluteString, ctx).get()
        let marker = "qa-b02ak13-\(UInt32.random(in: 1000...9999))"
        let body = Data("#EXTINF:-1,\(marker)\n\(B02.dead)/live/x.ts\n".utf8)
        let dataURL = "data:audio/x-mpegurl;base64," + body.base64EncodedString()
        let pd = try await B02.importURL(dataURL, ctx).get()
        B02.log("AK-13|file|\(B02.describe(pf))")
        B02.log("AK-13|data|\(B02.describe(pd))")
        XCTAssertEqual(pf.name, "Playlist"); XCTAssertTrue(pf.isRemote); XCTAssertEqual(pf.channelCount, 2)
        XCTAssertEqual(pd.name, "Playlist"); XCTAssertTrue(pd.isRemote); XCTAssertEqual(pd.sourceURL?.absoluteString, dataURL)
        XCTAssertEqual(server.requests.count, 0)
        let rows = B02.rows(storeURL.path, "select ZSOURCEURL from ZPLAYLIST where ZSOURCEURL like 'data:%'")
        B02.log("AK-13|sqlite|dataZeilen=\(rows.count)|laenge=\(rows.first?.first?.count ?? -1)")
        XCTAssertEqual(rows.count, 1)
        XCTAssertEqual(rows.first?.first, dataURL)
    }

    // MARK: AK-14

    /// AK-14: Benutzerinfo → erste Anfrage ohne `Authorization`; nach 401 + `WWW-Authenticate` Wiederholung mit Basic-Auth;
    /// ein anderer Host nach der Weiterleitung erhält keine `Authorization`. Zusätzlich beobachtet: Nach einer erfolgreichen
    /// Anmeldung schickt dieselbe Sitzung die Kopfzeile an denselben Host sofort mit.
    @MainActor func testAK14_BasicAuthAusBenutzerinfo() async throws {
        let c = try B02.memory()
        let pass = "qa-pass-b02ak14-\(UInt32.random(in: 1000...9999))"
        let expected = "Basic " + Data("qa-user:\(pass)".utf8).base64EncodedString()
        let ziel = try extraServer { _ in B02Server.ok(B02.zweiSenderData) }
        server.handler = { req in
            let ok = req.header("Authorization") == expected
            switch req.path {
            case "/ohne-challenge.m3u": return B02Server.ok(B02.zweiSenderData)
            case "/basic.m3u": return ok ? B02Server.ok(B02.zweiSenderData) : B02Server.status(401, headers: [("WWW-Authenticate", "Basic realm=\"qa\"")])
            case "/basic-redirect": return ok ? B02Server.redirect(302, to: "http://127.0.0.1:\(ziel.port)/ziel.m3u") : B02Server.status(401, headers: [("WWW-Authenticate", "Basic realm=\"qa2\"")])
            default: return B02Server.status(404)
            }
        }
        var result: [String: [String]] = [:]
        let cases = [("1-ohne-challenge", "127.0.0.1", "/ohne-challenge.m3u"), ("2-basic", "127.0.0.1", "/basic.m3u"),
                     ("3-basic-erneut", "127.0.0.1", "/basic.m3u"), ("4-basic-redirect", "localhost", "/basic-redirect")]
        for (label, host, path) in cases {
            server.resetLog(); ziel.resetLog()
            let r = await B02.importURL("http://qa-user:\(pass)@\(host):\(server.port)\(path)", c.mainContext)
            let quelle = server.requests.map { "\($0.target) auth=\($0.header("Authorization") == nil ? "nein" : ($0.header("Authorization") == expected ? "ja" : "anders"))" }
            let zielReqs = ziel.requests.map { "\($0.target) auth=\($0.header("Authorization") == nil ? "nein" : "ja")" }
            result[label] = quelle + zielReqs.map { "ZIEL " + $0 }
            B02.log("AK-14|\(label)|host=\(host)|ergebnis=\(B02.message(r) ?? "OK")|quelle=\(quelle)|ziel=\(zielReqs)")
            XCTAssertNil(B02.message(r), label)
        }
        XCTAssertEqual(result["1-ohne-challenge"], ["/ohne-challenge.m3u auth=nein"])
        XCTAssertEqual(result["2-basic"], ["/basic.m3u auth=nein", "/basic.m3u auth=ja"])
        XCTAssertEqual(result["4-basic-redirect"], ["/basic-redirect auth=nein", "/basic-redirect auth=ja", "ZIEL /ziel.m3u auth=nein"])
        // Beobachtung (nicht Teil von AK-14): zweiter Abruf desselben Hosts in derselben Sitzung
        B02.log("AK-14|beobachtung|zweiterAbrufDesselbenHosts=\(result["3-basic-erneut"] ?? [])")
        // Legt CFNetwork die Zugangsdaten im Zugangsdatenspeicher ab? (Persistenz 1 = Sitzung, 2 = dauerhaft)
        // Ausgegeben werden nur Einträge des erfundenen Benutzers `qa-user`; fremde Einträge werden weder gelistet noch angefasst.
        var spaces: [String] = []
        for (space, creds) in URLCredentialStorage.shared.allCredentials where ["127.0.0.1", "localhost"].contains(space.host) {
            let own = space.port == Int(server.port)
            for (user, cred) in creds where user == "qa-user" {
                spaces.append("\(space.host):\(own ? "testport" : "anderer-port")|realm=\(own ? (space.realm ?? "-") : "-")|methode=\(space.authenticationMethod)|persistenz=\(cred.persistence.rawValue)|qaUser=\(user == "qa-user")")
            }
        }
        let keychainQA = Self.internetPasswordCount(account: "qa-user")
        B02.log("AK-14|credentialStorage|\(spaces)|schluesselbundInternetPasswoerter(qa-user)=\(keychainQA)")
        XCTAssertEqual(keychainQA, 0, "keine dauerhaften Zugangsdaten des Test-Kontos im Schlüsselbund")
    }

    /// Anzahl Internet-Passwörter im Schlüsselbund für das erfundene Konto (nur Attribute, keine Oberfläche).
    static func internetPasswordCount(account: String) -> Int {
        let q: [String: Any] = [kSecClass as String: kSecClassInternetPassword, kSecAttrAccount as String: account,
                                kSecMatchLimit as String: kSecMatchLimitAll, kSecReturnAttributes as String: true,
                                kSecUseAuthenticationUI as String: kSecUseAuthenticationUIFail]
        var out: CFTypeRef?
        let status = SecItemCopyMatching(q as CFDictionary, &out)
        return status == errSecItemNotFound ? 0 : ((out as? [[String: Any]])?.count ?? Int(status))
    }

    // MARK: AK-15

    /// AK-15 ⚠ (OF-01): zweiter Import derselben URL legt eine zweite, unabhängige Playlist an; keine Warnung.
    @MainActor func testAK15_DoppelterImportLegtZweitePlaylistAn() async throws {
        let c = try B02.memory()
        let a = try await B02.importURL(server.url("/liste.m3u"), c.mainContext).get()
        let b = try await B02.importURL(server.url("/liste.m3u"), c.mainContext).get()
        B02.log("AK-15|playlists=\(B02.count(Playlist.self, c.mainContext))|sender=\(B02.count(Channel.self, c.mainContext))|anfragen=\(server.requests.count)|gleicheID=\(a.id == b.id)")
        XCTAssertEqual(B02.count(Playlist.self, c.mainContext), 2)
        XCTAssertEqual(B02.count(Channel.self, c.mainContext), 4)
        XCTAssertNotEqual(a.id, b.id)
        XCTAssertEqual(server.requests.count, 2)
    }

    // MARK: AK-26 (Import)

    /// AK-26 / EC-01 / EC-15: keine gültigen Einträge (leer, HTML-Loginseite mit 200, JSON, nur Adressen) → Meldung, nichts angelegt.
    @MainActor func testAK26_EC01_EC15_KeineGueltigenSenderLegtNichtsAn() async throws {
        let c = try B02.memory()
        let bodies: [(String, String, String)] = [
            ("leer", "", "audio/x-mpegurl"),
            ("Captive Portal", "<!doctype html><html><body><form action=/login>Bitte anmelden</form></body></html>", "text/html"),
            ("JSON", "{\"user_info\":{\"auth\":0}}", "application/json"),
            ("nur Adressen", "#EXTM3U\n\(B02.dead)/a.ts\n\(B02.dead)/b.ts\n", "audio/x-mpegurl")
        ]
        for (label, body, type) in bodies {
            server.handler = { _ in B02Server.ok(Data(body.utf8), type: type) }
            let r = await B02.importURL(server.url("/x"), c.mainContext)
            B02.log("AK-26|\(label)|meldung=\(B02.message(r) ?? "OK")")
            XCTAssertEqual(B02.message(r), "Die Playlist enthält keine gültigen Sender.", label)
        }
        XCTAssertEqual(B02.count(Playlist.self, c.mainContext), 0)
        XCTAssertEqual(B02.count(Channel.self, c.mainContext), 0)
    }

    // MARK: AK-28 (schnelle Fälle)

    /// AK-28: nicht erreichbar → „Netzwerkfehler:" + englischer Systemtext (geschlossener Port, unbekannter Host).
    /// 60 s ohne Daten: `B02LangsamTests`.
    @MainActor func testAK28_ServerNichtErreichbar() async throws {
        let c = try B02.memory()
        let closed = B02Server(); try closed.start(); let closedPort = closed.port; closed.stop()
        let port = await B02.importURL("http://127.0.0.1:\(closedPort)/liste.m3u", c.mainContext)
        let host = await B02.importURL("http://b02-qa-nicht-vorhanden.invalid/liste.m3u", c.mainContext)
        B02.log("AK-28|portZu=\(B02.message(port) ?? "OK")|hostUnbekannt=\(B02.message(host) ?? "OK")")
        XCTAssertEqual(B02.message(port), "Netzwerkfehler: Could not connect to the server.")
        XCTAssertEqual(B02.message(host), "Netzwerkfehler: A server with the specified hostname could not be found.")
    }

    // MARK: AK-33

    /// AK-33: Fehlermeldungen enthalten weder Benutzer noch Passwort noch Adresse — auch wenn sie in Query oder Benutzerinfo stehen.
    @MainActor func testAK33_FehlermeldungOhneZugangsdatenUndAdresse() async throws {
        let c = try B02.memory()
        let marker = "qa-pass-b02ak33-\(UInt32.random(in: 1000...9999))"
        let closed = B02Server(); try closed.start(); let closedPort = closed.port; closed.stop()
        server.handler = { req in
            switch req.path {
            case "/404.m3u": return B02Server.status(404)
            case "/schleife": return B02Server.redirect(302, to: "/schleife?password=\(marker)")
            case "/leer": return B02Server.ok(Data("<html>\(marker)</html>".utf8), type: "text/html")
            case "/500": return B02Server.status(500, body: Data("password=\(marker)".utf8))
            default: return B02Server.status(404)
            }
        }
        let inputs = [
            server.url("/404.m3u?username=qa-user-b02&password=\(marker)"),
            server.url("/schleife?password=\(marker)"),
            server.url("/leer?password=\(marker)"),
            server.url("/500?username=qa-user-b02&password=\(marker)"),
            "http://127.0.0.1:\(closedPort)/get.php?username=qa-user-b02&password=\(marker)",
            "http://qa-user-b02:\(marker)@b02-qa-nicht-vorhanden.invalid/get.php?password=\(marker)",
            "ftp://qa-user-b02:\(marker)@127.0.0.1:\(closedPort)/x.m3u",
            "qa-user-b02:\(marker)@ohne-schema/x.m3u",
            "\(server.hostPort)/get.php?username=qa-user-b02&password=\(marker)"
        ]
        for input in inputs {
            let r = await B02.importURL(input, c.mainContext)
            let m = B02.message(r) ?? "OK"
            let masked = input.replacingOccurrences(of: marker, with: "<PASSWORT>")
            B02.log("AK-33|eingabe=\(masked)|meldung=\(m)|passwort=\(m.contains(marker))|benutzer=\(m.contains("qa-user-b02"))|adresse=\(m.contains("127.0.0.1") || m.contains(".invalid") || m.contains("get.php"))")
            XCTAssertNotNil(r.b02Failure, masked)
            XCTAssertFalse(m.contains(marker), masked)
            XCTAssertFalse(m.contains("qa-user-b02"), masked)
            XCTAssertFalse(m.contains("127.0.0.1") || m.contains("nicht-vorhanden") || m.contains("get.php") || m.contains("ohne-schema"), masked)
        }
    }

    // MARK: AK-36

    /// AK-36: Kopfzeilen der Anfrage; kein `Referer`; ein vom Server gesetztes Cookie wird gespeichert und beim nächsten
    /// Abruf desselben Hosts mitgeschickt, auch beim Aktualisieren (B03-Pfad `refresh`).
    @MainActor func testAK36_KopfzeilenUndCookies() async throws {
        let c = try B02.memory()
        let marker = "qa-b02ak36-\(UInt32.random(in: 1000...9999))"
        server.handler = { _ in B02Server.ok(B02.zweiSenderData, headers: [("Set-Cookie", "b02qaSess=\(marker); Path=/")]) }
        let p = try await B02.importURL(server.url("/liste.m3u"), c.mainContext).get()
        _ = try await B02.importURL(server.url("/andere.m3u"), c.mainContext).get()
        try await PlaylistImporter(modelContext: c.mainContext).refresh(p)
        let reqs = server.requests
        XCTAssertEqual(reqs.count, 3)
        for (i, r) in reqs.enumerated() {
            B02.log("AK-36|anfrage\(i + 1)|\(r.target)|kopfzeilen=\(r.headerNames)|user-agent=\(r.header("User-Agent") ?? "-")|accept=\(r.header("Accept") ?? "-")|accept-language=\(r.header("Accept-Language") ?? "-")|accept-encoding=\(r.header("Accept-Encoding") ?? "-")|connection=\(r.header("Connection") ?? "-")|cookie=\(r.header("Cookie")?.replacingOccurrences(of: marker, with: "<marker>") ?? "-")|referer=\(r.header("Referer") ?? "-")")
        }
        let first = try XCTUnwrap(reqs.first)
        XCTAssertEqual(first.headerNames, ["accept", "accept-encoding", "accept-language", "connection", "host", "user-agent"])
        let ua = first.header("User-Agent") ?? ""
        let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "?"
        XCTAssertNotNil(ua.range(of: "^Mika\\+Player/\(build) CFNetwork/[0-9.]+ Darwin/[0-9.]+$", options: .regularExpression), ua)
        XCTAssertEqual(first.header("Accept"), "*/*")
        XCTAssertNil(first.header("Referer"))
        XCTAssertNil(first.header("Cookie"))
        XCTAssertEqual(reqs[1].header("Cookie"), "b02qaSess=\(marker)", "zweiter Import desselben Hosts")
        XCTAssertEqual(reqs[2].header("Cookie"), "b02qaSess=\(marker)", "Aktualisieren (B03)")
        // Seit B02 · BUG-02 hält der Loader Cookies nur im eigenen Arbeitsspeicher, nicht im gemeinsamen Speicher.
        let shared = HTTPCookieStorage.shared.cookies?.filter { $0.name == "b02qaSess" } ?? []
        let stored = PlaylistHTTPLoader.shared.cookies.filter { $0.name == "b02qaSess" }
        B02.log("AK-36|cookieImLoader=\(stored.count)|imGemeinsamenSpeicher=\(shared.count)|sitzungscookie=\(stored.first?.isSessionOnly ?? false)|domain=\(stored.first?.domain ?? "-")")
        XCTAssertEqual(stored.count, 1)
        XCTAssertEqual(shared.count, 0)
    }
}

extension Result {
    var b02Failure: Failure? { if case .failure(let e) = self { return e }; return nil }
}
