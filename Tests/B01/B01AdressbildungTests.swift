import XCTest
import SwiftData
@testable import MikaPlusPlayer

/// B01 · Xtream-Codes-Login — Adressbildung (AK-11 … AK-15) und Adress-Edge-Cases (QA 2026-09-15).
final class B01AdressbildungTests: B01MockTestCase {

    /// AK-11: Leerzeichen/Zeilenumbruch, fehlendes Schema, Port, Schrägstriche, Pfad und Query → http://host:port/player_api.php
    @MainActor func testAK11_HostNormalisierungAmPayload() async throws {
        // Adresse ohne Netz
        let c = XtreamCredentials(host: " example.com:8080/panel/?x=1 \n", username: "u", password: "p")
        XCTAssertEqual(c.playerAPIURL()?.absoluteString, "http://example.com:8080/player_api.php?username=u&password=p")
        XCTAssertEqual(XtreamCredentials(host: "example.com:8080///", username: "u", password: "p").baseURL()?.absoluteString,
                       "http://example.com:8080")

        // Payload am Mock
        let container = try B01.inMemoryContainer()
        let host = " \n\(mock.hostPort)/panel/sub/?x=1 \n"
        let p = try await B01.importXtream(host: host, pass: "qa-pass-ak11", context: container.mainContext).get()
        let reqs = mock.requests
        XCTAssertEqual(reqs.count, 3)
        XCTAssertTrue(reqs.allSatisfy { $0.path == "/player_api.php" }, reqs.map(\.target).description)
        XCTAssertFalse(reqs.contains { ($0.rawQuery ?? "").contains("x=1") })
        // BUG-01 behoben: gespeicherte Adresse ohne Zugangsdaten
        XCTAssertEqual(p.sourceURL?.absoluteString, "http://\(mock.hostPort)/player_api.php")
    }

    /// AK-12 / BUG-02 behoben: `HTTPS://` bleibt https; gegen einen Klartext-Server kommt keine Anfrage mit Passwort an.
    @MainActor func testAK12_HTTPSBleibtErhalten() async throws {
        // Adressen ohne Netz: Schema bleibt https (auch bei Großschreibung), Port bleibt
        let c = XtreamCredentials(host: " HTTPS://example.com:8443/panel/ ", username: "u", password: "p")
        XCTAssertEqual(c.baseURL()?.absoluteString, "https://example.com:8443")
        XCTAssertTrue(c.usesHTTPS)
        XCTAssertEqual(c.playerAPIURL()?.absoluteString, "https://example.com:8443/player_api.php?username=u&password=p")
        XCTAssertEqual(c.storedSourceURL()?.absoluteString, "https://example.com:8443/player_api.php")
        let secret = try XCTUnwrap(c.secret())
        let stored = try XCTUnwrap(XtreamStreamAddress.stored(base: try XCTUnwrap(c.storedBaseURL()), streamID: "101", fileExtension: "ts"))
        XCTAssertEqual(XtreamStreamAddress.playable(stored: stored, secret: secret)?.absoluteString,
                       "https://example.com:8443/live/u/p/101.ts")
        // Ohne Schema bleibt http (gewollt, README/Kommentar)
        XCTAssertFalse(XtreamCredentials(host: "example.com", username: "u", password: "p").usesHTTPS)

        // Payload: Der Klartext-Mock erhält bei https-Eingabe keine lesbare Anfrage
        let container = try B01.inMemoryContainer()
        let r = await B01.importXtream(host: "HTTPS://\(mock.hostPort)", pass: "qa-pass-ak12",
                                       context: container.mainContext, limits: B01.shortIdleLimits)
        print("B01BUILD|AK-12|https gegen Klartext-Mock|\(B01.message(r) ?? "ok")|anfragen=\(mock.requests.count)")
        XCTAssertEqual(mock.requests.count, 0, "keine Klartext-Anfrage")
        XCTAssertFalse(mock.requests.contains { $0.requestLine.contains("qa-pass-ak12") })
        XCTAssertTrue(B01.message(r)?.hasPrefix("Netzwerkfehler: ") ?? false)
        XCTAssertEqual(try container.mainContext.fetchCount(FetchDescriptor<Playlist>()), 0)
    }

    /// AK-13 / EC-10: Leerzeichen am Rand von Benutzer/Passwort werden entfernt; Zeilenumbrüche nicht (EC-09).
    @MainActor func testAK13_EC09_EC10_TrimNurLeerzeichen() async throws {
        let container = try B01.inMemoryContainer()
        let p = try await B01.importXtream(host: mock.hostPort, user: " qa-user ", pass: "  qa-pass-ak13 ",
                                           context: container.mainContext).get()
        XCTAssertTrue(mock.requests.allSatisfy { $0.username == "qa-user" && $0.password == "qa-pass-ak13" })
        XCTAssertTrue(try p.channels.allSatisfy { try B01.playable($0).path.hasPrefix("/live/qa-user/qa-pass-ak13/") })

        // EC-09: Zeilenumbruch bleibt und wird als %0A gesendet; Benutzer nur aus Zeilenumbruch gilt als ausgefüllt.
        XCTAssertTrue(XtreamCredentials(host: "h", username: "\n", password: "p").isComplete)
        mock.resetLog()
        _ = await B01.importXtream(host: mock.hostPort, user: "qa-user", pass: "qa-pass-ak13\n", context: container.mainContext)
        XCTAssertTrue(mock.requests.first?.rawQuery?.contains("password=qa-pass-ak13%0A") ?? false,
                      mock.requests.first?.rawQuery ?? "-")
        XCTAssertEqual(mock.requests.first?.password, "qa-pass-ak13\n")
    }

    /// AK-14 (a): Leerzeichen, Umlaute, %, & und = kommen unverändert an (Anfrage und Stream-Pfad).
    @MainActor func testAK14a_SonderzeichenDieUnveraendertAnkommen() async throws {
        let container = try B01.inMemoryContainer()
        for (user, pass) in [("qa user", "a b"), ("qä-user", "ä ö ß"), ("qa-user", "50%"), ("qa-user", "a&b=c")] {
            mock.resetLog()
            let r = await B01.importXtream(host: mock.hostPort, user: user, pass: pass, context: container.mainContext)
            let p = try r.get()
            XCTAssertTrue(mock.requests.allSatisfy { $0.username == user && $0.password == pass },
                          "\(pass.debugDescription): \(mock.requests.first?.rawQuery ?? "-")")
            let comps = try B01.playable(try XCTUnwrap(p.channels.first)).pathComponents
            XCTAssertEqual(Array(comps.prefix(4)), ["/", "live", user, pass], pass.debugDescription)
        }
    }

    /// AK-14 (b) / BUG-05 behoben: `+` geht als `%2B` raus; ein PHP-Panel liest `+`, die Anmeldung gelingt.
    @MainActor func testAK14b_PlusWirdAlsLeerzeichenGelesen() async throws {
        let container = try B01.inMemoryContainer()
        let panel = MockXtreamServer.panel()
        mock.handler = { req in
            // Panel prüft das Passwort so, wie PHP es aus $_GET liest
            req.password == "qa+pass" ? panel(req) : .json(["user_info": ["auth": 0]])
        }
        let r = await B01.importXtream(host: mock.hostPort, pass: "qa+pass", context: container.mainContext)
        let first = try XCTUnwrap(mock.requests.first)
        XCTAssertTrue(first.rawQuery?.contains("password=qa%2Bpass") ?? false, first.rawQuery ?? "-")
        XCTAssertEqual(first.password, "qa+pass", "PHP dekodiert %2B als +")
        XCTAssertNil(B01.message(r), "Passwort mit + muss sich anmelden können")
        XCTAssertEqual(mock.requests.count, 3)
        let playlist = try r.get()
        let comps = try B01.playable(try XCTUnwrap(playlist.channels.first)).pathComponents
        XCTAssertEqual(Array(comps.prefix(4)), ["/", "live", "qa-user", "qa+pass"])
    }

    /// AK-14 (c, d) / BUG-05 behoben: `#`, `?`, `/` bleiben innerhalb ihres Pfadabschnitts.
    @MainActor func testAK14cd_RautFrageSchraegstrichZerlegenStreamAdresse() async throws {
        let container = try B01.inMemoryContainer()
        var observed: [String: [String]] = [:]
        for pass in ["a#b", "a?b", "a/b"] {
            mock.resetLog()
            let p = try await B01.importXtream(host: mock.hostPort, pass: pass, context: container.mainContext).get()
            // Anfragen selbst kommen korrekt an
            XCTAssertTrue(mock.requests.allSatisfy { $0.password == pass }, pass)
            let channel = try XCTUnwrap(p.channels.first(where: { $0.name == "Kanal Int" }))
            let url = try B01.playable(channel)
            observed[pass] = url.pathComponents
            print("B01BUILD|AK-14cd|\(pass)|percentEncodedPath=\(url.absoluteString.replacingOccurrences(of: "http://\(mock.hostPort)", with: ""))|query=\(url.query ?? "-")|fragment=\(url.fragment ?? "-")")
            XCTAssertNil(url.query, pass)
            XCTAssertNil(url.fragment, pass)
        }
        for pass in ["a#b", "a?b", "a/b"] {
            XCTAssertEqual(observed[pass], ["/", "live", "qa-user", pass, "101.ts"], pass)
        }
    }

    /// AK-15: abspielbare Adresse http://<eingegebener Host>/live/<u>/<p>/<id>.<ts|m3u8>; server_info ignoriert;
    /// Int und String gleich. Gespeichert wird seit BUG-01 nur http://<host>/live/<id>.<ext>.
    @MainActor func testAK15_StreamAdresseUndFormat() async throws {
        let container = try B01.inMemoryContainer()
        for output in XtreamOutput.allCases {
            let p = try await B01.importXtream(host: mock.hostPort, pass: "qa-pass-ak15", output: output,
                                               context: container.mainContext).get()
            let urls = Dictionary(uniqueKeysWithValues: try p.channels.map { ($0.name, try B01.playable($0).absoluteString) })
            let stored = Dictionary(uniqueKeysWithValues: p.channels.map { ($0.name, $0.streamURL.absoluteString) })
            let ext = output == .hls ? "m3u8" : "ts"
            XCTAssertEqual(urls["Kanal Int"], "http://\(mock.hostPort)/live/qa-user/qa-pass-ak15/101.\(ext)")
            XCTAssertEqual(urls["Kanal String"], "http://\(mock.hostPort)/live/qa-user/qa-pass-ak15/102.\(ext)")
            XCTAssertEqual(stored["Kanal Int"], "http://\(mock.hostPort)/live/101.\(ext)")
            XCTAssertFalse(urls.values.contains { $0.contains("evil.example") })
        }
    }

    // MARK: - Edge Cases

    /// EC-01: Fragment im Host bleibt an der Basis hängen → Anfragen gehen, Stream-Adressen haben /live/… im Fragment.
    /// (Seit BUG-02 bleibt `https` erhalten; gegen den Klartext-Mock läuft der Fall deshalb mit `http://`.)
    @MainActor func testEC01_FragmentImHost() async throws {
        let container = try B01.inMemoryContainer()
        let p = try await B01.importXtream(host: "http://\(mock.hostPort)/panel/?x=1#f", pass: "qa-pass-ec01",
                                           context: container.mainContext).get()
        XCTAssertEqual(mock.requests.count, 3)
        let url = try B01.playable(try XCTUnwrap(p.channels.first))
        print("B01QA|EC-01|\(url.absoluteString.replacingOccurrences(of: "qa-pass-ec01", with: "<pass>"))")
        XCTAssertEqual(url.path, "")
        XCTAssertTrue(url.fragment?.hasPrefix("f/live/qa-user/") ?? false, url.fragment ?? "-")
    }

    /// EC-02: fremdes Schema wird zum Host und nicht abgelehnt; Anfrage scheitert mit Netzwerkfehler.
    @MainActor func testEC02_FremdesSchema() async throws {
        XCTAssertEqual(XtreamCredentials(host: "ftp://example.com", username: "u", password: "p").baseURL()?.absoluteString, "http://ftp")
        XCTAssertEqual(XtreamCredentials(host: "httpx://example.com", username: "u", password: "p").baseURL()?.absoluteString, "http://httpx")
        let container = try B01.inMemoryContainer()
        let r = await B01.importXtream(host: "httpx://qa-host.invalid", pass: "qa-pass-ec02", context: container.mainContext)
        print("B01QA|EC-02|\(B01.message(r) ?? "ok")")
        XCTAssertTrue(B01.message(r)?.hasPrefix("Netzwerkfehler: ") ?? false)
    }

    /// EC-03: Benutzerinfo im Host bleibt in Anfragen und abspielbaren Stream-Adressen erhalten.
    /// Seit BUG-01 steht sie wie das Passwort nur im Schlüsselbund, nicht in der Datenbank; H-1 (Verlust beim
    /// Aktualisieren) entfällt dadurch.
    @MainActor func testEC03_BenutzerinfoImHost() async throws {
        let container = try B01.inMemoryContainer()
        let p = try await B01.importXtream(host: "http://qa-u:qa-pw@\(mock.hostPort)", pass: "qa-pass-ec03",
                                           context: container.mainContext).get()
        XCTAssertEqual(mock.requests.count, 3)
        print("B01BUILD|EC-03|authorization=\(mock.requests.first?.headers["authorization"] != nil)|sourceUser=\(p.sourceURL?.user ?? "-")")
        XCTAssertEqual(try B01.playable(try XCTUnwrap(p.channels.first)).user, "qa-u")
        XCTAssertNil(p.sourceURL?.user)
        XCTAssertNil(p.channels.first?.streamURL.user)
        let secret = try XCTUnwrap(try XtreamCredentialStore.standard.load(for: p.id))
        XCTAssertEqual(XtreamCredentials(secret: secret).baseURL()?.absoluteString, "http://qa-u:qa-pw@\(mock.hostPort)")
    }

    /// EC-04: internationalisierter Host wird Punycode, so heißt auch die Playlist ohne Namen.
    @MainActor func testEC04_IDNHost() {
        let c = XtreamCredentials(host: "müller.de", username: "u", password: "p")
        XCTAssertEqual(c.baseURL()?.host, "xn--mller-kva.de")
    }

    /// EC-05: IPv6-Host → Anfragen und Stream-Adressen korrekt, Name „::1", Rekonstruktion http://[::1]:port.
    @MainActor func testEC05_IPv6Host() async throws {
        let v6 = MockXtreamServer(bindHost: "::1")
        try v6.start()
        defer { v6.stop() }
        let container = try B01.inMemoryContainer()
        let p = try await B01.importXtream(host: "[::1]:\(v6.port)", pass: "qa-pass-ec05", context: container.mainContext).get()
        XCTAssertEqual(v6.requests.count, 3)
        XCTAssertEqual(p.name, "::1")
        XCTAssertEqual(try B01.playable(try XCTUnwrap(p.channels.first(where: { $0.name == "Kanal Int" }))).absoluteString,
                       "http://[::1]:\(v6.port)/live/qa-user/qa-pass-ec05/101.ts")
        let secret = try XCTUnwrap(try XtreamCredentialStore.standard.load(for: p.id))
        XCTAssertEqual(secret.host, "http://[::1]:\(v6.port)")
    }

    /// EC-06: Panel unter Unterpfad → Pfad verworfen, Anfrage an /player_api.php im Wurzelverzeichnis.
    @MainActor func testEC06_UnterpfadWirdVerworfen() async throws {
        let container = try B01.inMemoryContainer()
        let panel = MockXtreamServer.panel()
        mock.handler = { req in
            req.path == "/panel/player_api.php" ? panel(req) : .raw(status: 404, contentType: "text/plain", body: Data())
        }
        let r = await B01.importXtream(host: "\(mock.hostPort)/panel/", pass: "qa-pass-ec06", context: container.mainContext)
        XCTAssertEqual(mock.requests.first?.path, "/player_api.php")
        XCTAssertEqual(B01.message(r), "Netzwerkfehler: HTTP 404")
    }

    /// EC-07: https-Panel auf TLS-Port → Adresse bleibt https://host:8443 (BUG-02 behoben). Gegen einen Port ohne TLS
    /// scheitert der Aufbau mit einem Netzwerkfehler, ohne dass eine Klartext-Anfrage ankommt.
    @MainActor func testEC07_HTTPSNurTLSPanel() async throws {
        XCTAssertEqual(XtreamCredentials(host: "https://example.com:8443", username: "u", password: "p").baseURL()?.absoluteString,
                       "https://example.com:8443")
        let container = try B01.inMemoryContainer()
        mock.handler = { _ in .raw(status: 400, contentType: "text/html",
                                   body: Data("The plain HTTP request was sent to HTTPS port".utf8)) }
        let r = await B01.importXtream(host: "https://\(mock.hostPort)", pass: "qa-pass-ec07",
                                       context: container.mainContext, limits: B01.shortIdleLimits)
        print("B01BUILD|EC-07|\(B01.message(r) ?? "ok")")
        XCTAssertTrue(B01.message(r)?.hasPrefix("Netzwerkfehler: ") ?? false)
        XCTAssertEqual(mock.requests.count, 0)
    }

    /// EC-08: Host `//host` → Basisadresse ohne Host.
    @MainActor func testEC08_DoppelterSchraegstrichOhneSchema() async throws {
        let base = XtreamCredentials(host: "//example.com", username: "u", password: "p").baseURL()
        print("B01QA|EC-08|base=\(base?.absoluteString ?? "nil")|host=\(base?.host.debugDescription ?? "nil")")
        let container = try B01.inMemoryContainer()
        let r = await B01.importXtream(host: "//\(mock.hostPort)", pass: "qa-pass-ec08", context: container.mainContext)
        print("B01QA|EC-08|message=\(B01.message(r) ?? "ok")|mockRequests=\(mock.requests.count)")
        XCTAssertNotNil(B01.message(r))
        XCTAssertEqual(mock.requests.count, 0)
    }

    /// EC-14: stream_id mit Schrägstrich → unkodiert im Pfad.
    @MainActor func testEC14_StreamIdMitSchraegstrich() async throws {
        let container = try B01.inMemoryContainer()
        mock.handler = MockXtreamServer.panel(streams: [["name": "S", "stream_id": "abc/def"]])
        let p = try await B01.importXtream(host: mock.hostPort, pass: "qa-pass-ec14", context: container.mainContext).get()
        XCTAssertEqual(try B01.playable(try XCTUnwrap(p.channels.first)).path, "/live/qa-user/qa-pass-ec14/abc/def.ts")
    }
}
