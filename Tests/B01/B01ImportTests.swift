import XCTest
import SwiftData
@testable import MikaPlusPlayer

/// B01 · Xtream-Codes-Login — Anmeldung, Import, Fehlerfälle (QA 2026-09-15).
/// Alle Netzwerkfälle laufen gegen `MockXtreamServer` auf 127.0.0.1 mit erfundenen Zugangsdaten.
final class B01ImportTests: B01MockTestCase {

    // MARK: - Anmeldung und Import

    /// AK-06: Import mit N ≥ 1 Streams legt eine Playlist mit N Sendern an (Xtream, Remote).
    @MainActor func testAK06_ErfolgreicherImportLegtPlaylistMitNSendernAn() async throws {
        let container = try B01.inMemoryContainer()
        let ctx = container.mainContext
        let result = await B01.importXtream(host: mock.hostPort, pass: "qa-pass-ak06", context: ctx)
        let playlist = try result.get()
        let all = try ctx.fetch(FetchDescriptor<Playlist>())
        XCTAssertEqual(all.count, 1)
        XCTAssertEqual(playlist.channelCount, MockXtreamServer.streams.count)
        XCTAssertEqual(try ctx.fetchCount(FetchDescriptor<Channel>()), MockXtreamServer.streams.count)
        XCTAssertTrue(playlist.isXtream)
        XCTAssertTrue(playlist.isRemote, "Globus-Symbol hängt an isRemote")
        XCTAssertEqual(playlist.xtreamOutput, "mpegts")
        XCTAssertNotNil(playlist.lastRefreshed)
        XCTAssertTrue(playlist.channels.allSatisfy { $0.playlistID == playlist.id })
    }

    /// AK-07: Leerer Name → Host ohne Schema und Port; eingegebener Name exakt, auch nur Leerzeichen.
    @MainActor func testAK07_NameAusHostOderEingabeUngekuerzt() async throws {
        let container = try B01.inMemoryContainer()
        let ctx = container.mainContext
        let a = try await B01.importXtream(host: "http://\(mock.hostPort)/", pass: "qa-pass-ak07", name: "", context: ctx).get()
        XCTAssertEqual(a.name, "127.0.0.1")
        let b = try await B01.importXtream(host: mock.hostPort, pass: "qa-pass-ak07", name: "  Mein Anbieter ", context: ctx).get()
        XCTAssertEqual(b.name, "  Mein Anbieter ")
        let c = try await B01.importXtream(host: mock.hostPort, pass: "qa-pass-ak07", name: "   ", context: ctx).get()
        XCTAssertEqual(c.name, "   ")
    }

    /// AK-08: ein Sender je Live-Stream; Gruppe über category_id (erste gewinnt, unbekannt/fehlend → nil);
    /// Logo aus stream_icon, tvg-ID aus epg_channel_id, leer/null → nil. Kein VOD/Serien-Abruf.
    @MainActor func testAK08_SenderZuordnungAusLiveStreams() async throws {
        let container = try B01.inMemoryContainer()
        let ctx = container.mainContext
        let playlist = try await B01.importXtream(host: mock.hostPort, pass: "qa-pass-ak08", context: ctx).get()
        let byName = Dictionary(uniqueKeysWithValues: playlist.channels.map { ($0.name, $0) })
        XCTAssertEqual(byName.count, 4)

        let int = try XCTUnwrap(byName["Kanal Int"])
        XCTAssertEqual(int.group, "News", "Duplikat-Kategorie 'News-Duplikat' darf nicht gewinnen")
        XCTAssertEqual(int.logoURL?.absoluteString, "http://logos.example/a.png")
        XCTAssertEqual(int.tvgID, "kanal.int")

        let str = try XCTUnwrap(byName["Kanal String"])
        XCTAssertEqual(str.group, "Sport")
        XCTAssertNil(str.logoURL, "leeres stream_icon → nil")
        XCTAssertNil(str.tvgID, "leere epg_channel_id → nil")

        let none = try XCTUnwrap(byName["Kanal ohne Kategorie"])
        XCTAssertNil(none.group)
        XCTAssertNil(none.logoURL, "null → nil")
        XCTAssertNil(none.tvgID, "null → nil")

        XCTAssertNil(try XCTUnwrap(byName["Kanal unbekannte Kategorie"]).group)

        let actions = mock.apiRequests.map { $0.action ?? "-" }
        XCTAssertFalse(actions.contains { $0.contains("vod") || $0.contains("series") }, "\(actions)")
    }

    /// AK-09 ⚠ (OF-01): zweiter Import mit denselben Zugangsdaten → zweite, unabhängige Playlist, keine Warnung.
    /// Ist-Verhalten wird festgehalten. BUG-09 ist nur im Teil „Doppelklick" behoben (EC-19); ob eine Dublette
    /// verhindert werden soll, ist eine Produktentscheidung (OF-01) und bleibt offen.
    @MainActor func testAK09_DoppelterImportLegtZweitePlaylistAn() async throws {
        let container = try B01.inMemoryContainer()
        let ctx = container.mainContext
        let a = try await B01.importXtream(host: mock.hostPort, pass: "qa-pass-ak09", context: ctx).get()
        let b = try await B01.importXtream(host: mock.hostPort, pass: "qa-pass-ak09", context: ctx).get()
        XCTAssertNotEqual(a.id, b.id)
        XCTAssertEqual(try ctx.fetchCount(FetchDescriptor<Playlist>()), 2, "Ist: zwei Playlists")
        XCTAssertEqual(try ctx.fetchCount(FetchDescriptor<Channel>()), 2 * MockXtreamServer.streams.count)
        let count = try ctx.fetchCount(FetchDescriptor<Playlist>())
        XCTExpectFailure("BUG-09 (Teil Dublette) nicht behoben · Produktentscheidung offen (AK-09, OF-01)") {
            XCTAssertEqual(count, 1,
                           "Gleicher Host + Benutzer sollte keine zweite Playlist erzeugen")
        }
    }

    /// AK-10: genau drei GETs an /player_api.php in fester Reihenfolge, username+password in jeder Query, kein get.php.
    @MainActor func testAK10_DreiAnfragenInReihenfolgeOhneGetPhp() async throws {
        let container = try B01.inMemoryContainer()
        _ = try await B01.importXtream(host: mock.hostPort, pass: "qa-pass-ak10", context: container.mainContext).get()
        let reqs = mock.requests
        for r in reqs {  // tatsächlicher Payload (erfundene Zugangsdaten)
            print("B01QA|AK-10|payload|\(r.requestLine)|kopfzeilen=\(r.headers.map { "\($0.key): \($0.value)" }.sorted())")
        }
        XCTAssertEqual(reqs.count, 3, reqs.map(\.requestLine).joined(separator: "\n"))
        XCTAssertTrue(reqs.allSatisfy { $0.method == "GET" && $0.path == "/player_api.php" })
        XCTAssertEqual(reqs.map { $0.action ?? "(ohne)" }, ["(ohne)", "get_live_categories", "get_live_streams"])
        XCTAssertTrue(reqs.allSatisfy { $0.username == "qa-user" && $0.password == "qa-pass-ak10" })
        XCTAssertFalse(reqs.contains { $0.path.contains("get.php") })
    }

    /// AK-10 (Kehrseite): Scheitert eine Anfrage, folgt keine weitere.
    @MainActor func testAK10_NachFehlschlagKeineWeitereAnfrage() async throws {
        let container = try B01.inMemoryContainer()
        // Anmeldung scheitert
        mock.handler = MockXtreamServer.panel(auth: ["user_info": ["auth": 0]])
        _ = await B01.importXtream(host: mock.hostPort, pass: "qa-pass-ak10", context: container.mainContext)
        XCTAssertEqual(mock.requests.map { $0.action ?? "(ohne)" }, ["(ohne)"])
        // Kategorien scheitern mit HTTP 500
        mock.resetLog()
        mock.handler = { req in
            req.action == "get_live_categories" ? .raw(status: 500, contentType: "text/plain", body: Data())
                                                : MockXtreamServer.panel()(req)
        }
        _ = await B01.importXtream(host: mock.hostPort, pass: "qa-pass-ak10", context: container.mainContext)
        XCTAssertEqual(mock.requests.map { $0.action ?? "(ohne)" }, ["(ohne)", "get_live_categories"])
    }

    // MARK: - Fehlerfälle

    /// AK-16: auth ≠ 1 oder ohne user_info → Anmeldemeldung.
    @MainActor func testAK16_AuthUngleichEinsOderOhneUserInfo() async throws {
        let container = try B01.inMemoryContainer()
        let expected = "Anmeldung fehlgeschlagen. Benutzername/Passwort prüfen."
        let auths: [Any] = [["user_info": ["auth": 0]], ["user_info": ["auth": 2]], [String: Any](), ["user_info": [String: Any]()]]
        for auth in auths {
            mock.handler = MockXtreamServer.panel(auth: auth)
            let r = await B01.importXtream(host: mock.hostPort, pass: "qa-pass-ak16", context: container.mainContext)
            XCTAssertEqual(B01.message(r), expected, "\(auth)")
        }
    }

    /// AK-17: HTTP-Status außerhalb 200–299 → „Netzwerkfehler: HTTP <Status>"; Grenzwerte 299 (ok) und 300.
    @MainActor func testAK17_HTTPStatusAusserhalb2xx() async throws {
        let container = try B01.inMemoryContainer()
        for status in [401, 407, 500, 300] {
            mock.handler = { _ in .raw(status: status, contentType: "application/json", body: Data("{}".utf8)) }
            let r = await B01.importXtream(host: mock.hostPort, pass: "qa-pass-ak17", context: container.mainContext)
            XCTAssertEqual(B01.message(r), "Netzwerkfehler: HTTP \(status)")
        }
        // 299 gilt als Erfolg
        let ok = MockXtreamServer.panel()
        mock.handler = { req in
            if case .json(let o, _) = ok(req) { return .json(o, status: 299) }
            return ok(req)
        }
        let r = await B01.importXtream(host: mock.hostPort, pass: "qa-pass-ak17", context: container.mainContext)
        XCTAssertNil(B01.message(r), "HTTP 299 muss als Erfolg gelten")
    }

    /// AK-18: kein erwartetes JSON → „Netzwerkfehler: Unerwartete Serverantwort (…)" mit englischem Systemtext.
    @MainActor func testAK18_UnerwarteteServerantwort() async throws {
        let container = try B01.inMemoryContainer()
        let cases: [(String, @Sendable (MockXtreamServer.Request) -> MockXtreamServer.Reply)] = [
            ("HTML", { _ in .raw(status: 200, contentType: "text/html", body: Data("<html>blocked</html>".utf8)) }),
            ("leer", { _ in .raw(status: 200, contentType: "application/json", body: Data()) }),
            ("auth als Text", MockXtreamServer.panel(auth: ["user_info": ["auth": "1"]])),
            ("Kategorien null", MockXtreamServer.panel(categories: NSNull())),
            ("Streams als Objekt", { req in
                req.action == "get_live_streams" ? .json(["error": "x"]) : MockXtreamServer.panel()(req)
            })
        ]
        for (label, handler) in cases {
            mock.handler = handler
            let r = await B01.importXtream(host: mock.hostPort, pass: "qa-pass-ak18", context: container.mainContext)
            let msg = B01.message(r) ?? "(kein Fehler)"
            XCTAssertTrue(msg.hasPrefix("Netzwerkfehler: Unerwartete Serverantwort ("), "\(label): \(msg)")
            XCTAssertTrue(msg.hasSuffix(")"), "\(label): \(msg)")
            print("B01QA|AK-18|\(label)|\(msg)")
        }
    }

    /// AK-19: Anmeldung ok, get_live_streams leer → „Die Playlist enthält keine gültigen Sender."
    @MainActor func testAK19_LeereStreamliste() async throws {
        let container = try B01.inMemoryContainer()
        mock.handler = MockXtreamServer.panel(streams: [])
        let r = await B01.importXtream(host: mock.hostPort, pass: "qa-pass-ak19", context: container.mainContext)
        XCTAssertEqual(B01.message(r), "Die Playlist enthält keine gültigen Sender.")
    }

    /// AK-20 (a, b): Port geschlossen / Name nicht auflösbar → englischer Systemtext. (Timeout: B01LangsamTests)
    @MainActor func testAK20_HostNichtErreichbar() async throws {
        let container = try B01.inMemoryContainer()
        // freien Port ermitteln: Mock starten und sofort stoppen
        let closed = MockXtreamServer(); try closed.start(); let closedPort = closed.port; closed.stop()
        let r1 = await B01.importXtream(host: "127.0.0.1:\(closedPort)", pass: "qa-pass-ak20", context: container.mainContext)
        XCTAssertEqual(SystemSprache.englisch(B01.message(r1)), "Netzwerkfehler: Could not connect to the server.")  // B09 · OF-01: Systemtext englisch oder deutsch
        let r2 = await B01.importXtream(host: "qa-host.invalid", pass: "qa-pass-ak20", context: container.mainContext)
        XCTAssertEqual(SystemSprache.englisch(B01.message(r2)), "Netzwerkfehler: A server with the specified hostname could not be found.")
    }

    /// AK-21: Leerzeichen im Host oder nur „http://" → „Host ungültig…", keine Anfrage.
    @MainActor func testAK21_UngueltigerHostOhneAnfrage() async throws {
        let container = try B01.inMemoryContainer()
        for host in ["exa mple.com", "http://", "127.0.0. 1:\(mock.port)"] {
            let r = await B01.importXtream(host: host, pass: "qa-pass-ak21", context: container.mainContext)
            XCTAssertEqual(B01.message(r), "Host ungültig. Bitte prüfe die Eingabe.", host)
        }
        XCTAssertEqual(mock.requests.count, 0)
    }

    /// AK-22: Jeder Fehlschlag aus AK-16…AK-21 hinterlässt keine Playlist und keinen Sender.
    @MainActor func testAK22_FehlschlagLegtNichtsAn() async throws {
        let container = try B01.inMemoryContainer()
        let ctx = container.mainContext
        let handlers: [@Sendable (MockXtreamServer.Request) -> MockXtreamServer.Reply] = [
            MockXtreamServer.panel(auth: ["user_info": ["auth": 0]]),
            { _ in .raw(status: 407, contentType: "text/plain", body: Data()) },
            { req in req.action == "get_live_streams" ? .raw(status: 200, contentType: "text/html", body: Data("x".utf8))
                                                      : MockXtreamServer.panel()(req) },
            MockXtreamServer.panel(streams: [])
        ]
        for h in handlers {
            mock.handler = h
            _ = await B01.importXtream(host: mock.hostPort, pass: "qa-pass-ak22", context: ctx)
        }
        _ = await B01.importXtream(host: "exa mple.com", pass: "qa-pass-ak22", context: ctx)
        _ = await B01.importXtream(host: "qa-host.invalid", pass: "qa-pass-ak22", context: ctx)
        XCTAssertEqual(try ctx.fetchCount(FetchDescriptor<Playlist>()), 0)
        XCTAssertEqual(try ctx.fetchCount(FetchDescriptor<Channel>()), 0)
        XCTAssertFalse(ctx.hasChanges)
    }

    // MARK: - Edge Cases Dekodierung

    /// EC-11 / BUG-06 behoben: category_id als Zahl (Kategorien oder Streams) wird wie Text gelesen.
    @MainActor func testEC11_CategoryIdAlsZahlWirdImportiert() async throws {
        let container = try B01.inMemoryContainer()
        mock.handler = MockXtreamServer.panel(categories: [["category_id": 1, "category_name": "News"]])
        let r1 = await B01.importXtream(host: mock.hostPort, pass: "qa-pass-ec11", context: container.mainContext)
        mock.handler = MockXtreamServer.panel(streams: [["name": "X", "stream_id": 1, "category_id": 1]])
        let r2 = await B01.importXtream(host: mock.hostPort, pass: "qa-pass-ec11", context: container.mainContext)
        print("B01BUILD|EC-11|\(B01.message(r1) ?? "ok")|\(B01.message(r2) ?? "ok")")
        XCTAssertNil(B01.message(r1), "category_id als Int in Kategorien muss importierbar sein")
        XCTAssertNil(B01.message(r2), "category_id als Int in Streams muss importierbar sein")
        XCTAssertEqual(try r1.get().channels.first(where: { $0.name == "Kanal Int" })?.group, "News")
        XCTAssertEqual(try r2.get().channels.first?.group, "News")
    }

    /// EC-12 / BUG-06 behoben: Ein Stream mit `name: null` wird mit leerem Namen übernommen, ein Eintrag ohne
    /// gültige `stream_id` übersprungen – die übrigen Sender kommen an.
    @MainActor func testEC12_DefekteEintraegeKippenImportNichtMehr() async throws {
        let container = try B01.inMemoryContainer()
        mock.handler = MockXtreamServer.panel(
            streams: [
                ["name": NSNull(), "stream_id": 1, "category_id": "1"],
                ["name": "Y", "stream_id": 2],
                ["name": "ohne ID"],
                ["name": "ID als Objekt", "stream_id": ["x": 1]],
                ["name": "Logo als Zahl", "stream_id": 3, "stream_icon": 5, "epg_channel_id": false]
            ],
            categories: [["category_id": "1", "category_name": "News"], ["category_name": "ohne ID"], "kaputt"]
        )
        let r = await B01.importXtream(host: mock.hostPort, pass: "qa-pass-ec12", context: container.mainContext)
        print("B01BUILD|EC-12|\(B01.message(r) ?? "ok")")
        XCTAssertNil(B01.message(r))
        let p = try r.get()
        XCTAssertEqual(p.channelCount, 3)
        XCTAssertEqual(Set(p.channels.map(\.name)), ["", "Y", "Logo als Zahl"])
        XCTAssertEqual(p.channels.first(where: { $0.name == "" })?.group, "News")
        XCTAssertNil(p.channels.first(where: { $0.name == "Logo als Zahl" })?.logoURL)
    }

    /// EC-13: stream_id 5.0 → „5"; EC-15: leerer Name → Sender ohne Namen.
    @MainActor func testEC13_EC15_KommazahlIdUndLeererName() async throws {
        let container = try B01.inMemoryContainer()
        mock.handler = MockXtreamServer.panel(streams: [["name": "", "stream_id": 5.0]])
        let p = try await B01.importXtream(host: mock.hostPort, pass: "qa-pass-ec13", context: container.mainContext).get()
        let ch = try XCTUnwrap(p.channels.first)
        XCTAssertEqual(ch.streamURL.lastPathComponent, "5.ts")
        XCTAssertEqual(ch.name, "")
    }

    /// EC-16 (OF-03): auth 1 + status „Expired" → Import gelingt ohne Hinweis.
    @MainActor func testEC16_AbgelaufenesKontoWirdImportiert() async throws {
        let container = try B01.inMemoryContainer()
        mock.handler = MockXtreamServer.panel(auth: ["user_info": ["auth": 1, "status": "Expired", "exp_date": "1"]])
        let r = await B01.importXtream(host: mock.hostPort, pass: "qa-pass-ec16", context: container.mainContext)
        XCTAssertNil(B01.message(r))
    }

    /// EC-22 (OF-07): HLS gewählt, Panel sperrt HLS → Import gelingt, kein Abruf eines Streams.
    @MainActor func testEC22_HLSGesperrtImportGelingtTrotzdem() async throws {
        let container = try B01.inMemoryContainer()
        let panel = MockXtreamServer.panel()
        mock.handler = { req in
            req.path.hasSuffix(".m3u8") ? .raw(status: 407, contentType: "text/plain", body: Data()) : panel(req)
        }
        let p = try await B01.importXtream(host: mock.hostPort, pass: "qa-pass-ec22", output: .hls,
                                           context: container.mainContext).get()
        XCTAssertTrue(p.channels.allSatisfy { $0.streamURL.pathExtension == "m3u8" })
        XCTAssertFalse(mock.requests.contains { $0.path.hasPrefix("/live/") })
    }
}
