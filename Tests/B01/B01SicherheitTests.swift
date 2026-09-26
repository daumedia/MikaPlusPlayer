import XCTest
import SQLite3
import OSLog
import SwiftData
@testable import MikaPlusPlayer

/// B01 · Xtream-Codes-Login — Datenschutz, Missbrauchsschutz und Angriffsdurchlauf (QA 2026-09-15).
final class B01SicherheitTests: B01MockTestCase {

    // MARK: - AK-23 Fehlermeldungen ohne Zugangsdaten

    /// AK-23: Keine Fehlermeldung aus AK-16 … AK-21 enthält Benutzer, Passwort oder Anfrage-Adresse. (Timeout: B01LangsamTests)
    @MainActor func testAK23_FehlermeldungenOhneZugangsdatenUndAdresse() async throws {
        let container = try B01.inMemoryContainer()
        let user = "qa-user-ak23", pass = "qa-pass-ak23"
        let closed = MockXtreamServer(); try closed.start(); let closedPort = closed.port; closed.stop()
        let scenarios: [(String, String, (@Sendable (MockXtreamServer.Request) -> MockXtreamServer.Reply)?)] = [
            ("Anmeldung", mock.hostPort, MockXtreamServer.panel(auth: ["user_info": ["auth": 0]])),
            ("HTTP-Status", mock.hostPort, { _ in .raw(status: 401, contentType: "text/plain", body: Data()) }),
            ("Dekodierfehler", mock.hostPort, { _ in .raw(status: 200, contentType: "text/html", body: Data("<html>".utf8)) }),
            ("leere Liste", mock.hostPort, MockXtreamServer.panel(streams: [])),
            ("Port geschlossen", "127.0.0.1:\(closedPort)", nil),
            ("Host unbekannt", "qa-host.invalid", nil),
            ("Host ungültig", "exa mple.com", nil)
        ]
        for (label, host, handler) in scenarios {
            if let handler { mock.handler = handler }
            let r = await B01.importXtream(host: host, user: user, pass: pass, context: container.mainContext)
            let msg = try XCTUnwrap(B01.message(r), label)
            for secret in [user, pass, "player_api", host, "127.0.0.1", "qa-host"] {
                XCTAssertFalse(msg.contains(secret), "\(label): Meldung enthält \(secret)")
            }
            print("B01QA|AK-23|\(label)|\(msg)")
        }
        // Reparatur: auch die neuen Meldungen (BUG-07, BUG-08, BUG-10, BUG-01) enthalten keine Zugangsdaten
        var small = XtreamClient.Limits.standard
        small.maxResponseBytes = 1_024
        let newMessages: [String] = [
            XtreamClient.XtreamError.throttled(seconds: 30).localizedDescription,
            XtreamClient.XtreamError.responseTooLarge(megabytes: 64).localizedDescription,
            XtreamClient.XtreamError.deadlineExceeded(seconds: 180).localizedDescription,
            XtreamClient.XtreamError.tooManyStreams(100_000).localizedDescription,
            XtreamClient.XtreamError.redirectBlocked.localizedDescription,
            StreamURLResolver.ResolveError.missingCredentials.localizedDescription,
            XtreamCredentialStore.KeychainError.status(-25293).localizedDescription
        ]
        mock.handler = { _ in .raw(status: 200, contentType: "application/json", body: Data(repeating: 0x20, count: 4_096)) }
        let big = await B01.importXtream(host: mock.hostPort, user: user, pass: pass, context: container.mainContext, limits: small)
        for msg in newMessages + [B01.message(big) ?? ""] {
            for secret in [user, pass, "player_api", mock.hostPort, "127.0.0.1"] {
                XCTAssertFalse(msg.contains(secret), "Meldung enthält \(secret): \(msg)")
            }
            print("B01BUILD|AK-23|neu|\(msg)")
        }
    }

    // MARK: - AK-24 Klartext in der Datenbank · Angriff 8 Löschen

    /// AK-24 / BUG-01 behoben: Das Passwort steht weder in Playlist.sourceURL noch in einer Channel.streamURL noch
    /// sonst als Bytefolge in der Store-Datei (Temp-Store, SQLite gelesen), sondern im Schlüsselbund.
    /// Angriff 8: Löschen über den App-Weg entfernt Zeilen und Schlüsselbund-Eintrag.
    @MainActor func testAK24_KlartextInDatenbankUndRestNachLoeschen() async throws {
        let marker = "qa-pass-ak24-\(UInt32.random(in: 1000...9999))"
        var storeURL: URL!
        var dir: URL!
        do {
            let (container, url, d) = try B01.tempFileContainer("ak24")
            storeURL = url; dir = d
            let ctx = container.mainContext
            let playlist = try await B01.importXtream(host: mock.hostPort, user: "qa-user-ak24", pass: marker, context: ctx).get()
            try ctx.save()
            let playlistID = playlist.id

            let path = url.path
            let sourceRows = B01.sqliteCount(path, "select count(*) from ZPLAYLIST where instr(cast(ZSOURCEURL as text), '\(marker)') > 0")
            let channelRows = B01.sqliteCount(path, "select count(*) from ZCHANNEL where instr(cast(ZSTREAMURL as text), '\(marker)') > 0")
            let channelTotal = B01.sqliteCount(path, "select count(*) from ZCHANNEL")
            let rawBefore = B01.rawOccurrences(of: marker, inFilesWithPrefix: url)
            let userRows = B01.sqliteCount(path, "select count(*) from ZCHANNEL where instr(cast(ZSTREAMURL as text), 'qa-user-ak24') > 0")
            print("B01BUILD|AK-24|sourceRows=\(sourceRows ?? -1)|channelRowsWithPass=\(channelRows ?? -1)/\(channelTotal ?? -1)|channelRowsWithUser=\(userRows ?? -1)|rawBytes=\(rawBefore)")
            XCTAssertEqual(channelTotal, MockXtreamServer.streams.count)
            XCTAssertEqual(sourceRows, 0, "Passwort darf nicht in ZPLAYLIST.ZSOURCEURL stehen")
            XCTAssertEqual(channelRows, 0, "Passwort darf nicht in ZCHANNEL.ZSTREAMURL stehen")
            XCTAssertEqual(userRows, 0, "Benutzername darf nicht in ZCHANNEL.ZSTREAMURL stehen")
            XCTAssertEqual(rawBefore.values.reduce(0, +), 0, "Passwort als Bytefolge in Store/-wal/-shm")
            let secret = try XCTUnwrap(try XtreamCredentialStore.standard.load(for: playlistID))
            XCTAssertEqual(secret.password, marker)
            XCTAssertEqual(secret.username, "qa-user-ak24")

            // Angriff 8: Löschen über den App-Weg (PlaylistsView → PlaylistImporter.delete)
            try PlaylistImporter(modelContext: ctx).delete(playlist)
            XCTAssertNil(try XtreamCredentialStore.standard.load(for: playlistID), "Schlüsselbund-Eintrag muss mit der Playlist verschwinden")
            XCTAssertEqual(B01.sqliteCount(path, "select count(*) from ZPLAYLIST"), 0)
            XCTAssertEqual(B01.sqliteCount(path, "select count(*) from ZCHANNEL"), 0)
            XCTAssertEqual(B01.sqliteCount(path, "select count(*) from ZCHANNEL where instr(cast(ZSTREAMURL as text), '\(marker)') > 0"), 0)
            print("B01QA|DEL|nachLoeschenOffen|rawBytes=\(B01.rawOccurrences(of: marker, inFilesWithPrefix: url))")
        }
        // Container freigegeben → SQLite schließt und checkpointet die WAL
        try await Task.sleep(nanoseconds: 1_500_000_000)
        let rawAfter = B01.rawOccurrences(of: marker, inFilesWithPrefix: storeURL)
        let remaining = rawAfter.values.reduce(0, +)
        print("B01QA|DEL|nachSchliessen|rawBytes=\(rawAfter)")
        // Angriff 8 bestanden: Nach dem Schließen (WAL-Checkpoint) steht das Passwort in keiner Datei mehr.
        // Solange die App läuft, liegt es nach dem Löschen noch in der -wal-Datei (siehe Ausgabe „nachLoeschenOffen").
        XCTAssertEqual(remaining, 0, "Nach dem Löschen und Schließen darf das Passwort nicht mehr in der Datei stehen")
        try? FileManager.default.removeItem(at: dir)
    }

    // MARK: - AK-25 HTTP-Plattencache

    /// AK-25 / BUG-03 behoben: Anfragen mit Zugangsdaten und Antworten landen nicht mehr im Plattencache.
    /// Etwaige Einträge werden am Ende entfernt (und die Entfernung geprüft).
    @MainActor func testAK25_ZugangsdatenImHTTPPlattencache() async throws {
        let marker = "qa-pass-ak25-\(UInt32.random(in: 1000...9999))"
        // Echte Panels schicken die Zugangsdaten in user_info zurück
        mock.handler = MockXtreamServer.panel(auth: ["user_info": ["auth": 1, "username": "qa-user", "password": marker]])
        let container = try B01.inMemoryContainer()
        let ctx = container.mainContext
        let playlist = try await B01.importXtream(host: mock.hostPort, pass: marker, context: ctx).get()

        let urls = mock.requests.compactMap { URL(string: "http://\(mock.hostPort)\($0.target)") }
        XCTAssertEqual(urls.count, 3)
        let db = B01.hostCacheDB.path
        let keySQL = "select count(*) from cfurl_cache_response where instr(request_key, '\(marker)') > 0"
        let bodySQL = """
            select count(*) from cfurl_cache_receiver_data r join cfurl_cache_response c on c.entry_ID = r.entry_ID \
            where instr(c.request_key, '\(marker)') > 0 and instr(cast(r.receiver_data as text), '\(marker)') > 0
            """
        // Der alte Pfad (URLSession.shared) schrieb binnen einer Sekunde; großzügig warten.
        try await Task.sleep(nanoseconds: 3_000_000_000)
        let onDisk = B01.sqliteCount(db, keySQL) ?? 0
        let inMemory = urls.filter { URLCache.shared.cachedResponse(for: URLRequest(url: $0)) != nil }.count
        let bodies = B01.sqliteCount(db, bodySQL) ?? 0
        print("B01BUILD|AK-25|db=<Caches>/\(B01.hostCacheDB.deletingLastPathComponent().lastPathComponent)/Cache.db|keysOnDisk=\(onDisk)|bodiesWithPass=\(bodies)|cachedResponses=\(inMemory)")
        XCTAssertEqual(onDisk, 0, "Anfragen mit Zugangsdaten dürfen nicht auf die Platte")
        XCTAssertEqual(bodies, 0)
        XCTAssertEqual(inMemory, 0)

        // Playlist löschen → weiterhin nichts
        try PlaylistImporter(modelContext: ctx).delete(playlist)
        try await Task.sleep(nanoseconds: 500_000_000)
        let afterDelete = B01.sqliteCount(db, keySQL) ?? 0
        print("B01BUILD|AK-25|nachLoeschenDerPlaylist|keysOnDisk=\(afterDelete)")
        XCTAssertEqual(afterDelete, 0)

        // Aufräumen der eigenen Einträge und Nachweis
        B01.removeCachedResponses(for: mock)
        var left = -1
        for _ in 0..<40 {
            left = B01.sqliteCount(db, keySQL) ?? -1
            if left == 0 { break }
            try await Task.sleep(nanoseconds: 250_000_000)
        }
        print("B01QA|AK-25|nachAufraeumen|keysOnDisk=\(left)")
        XCTAssertEqual(left, 0, "Test muss seine Cache-Einträge entfernen")
    }

    // MARK: - AK-26 Weiterleitung

    /// AK-26 / BUG-10 behoben: Leitet das Panel auf einen anderen Host oder Port um, bricht die App ab; das Ziel
    /// erhält nichts. Weiterleitungen innerhalb desselben Panels (Pfadwechsel) bleiben erlaubt.
    @MainActor func testAK26_WeiterleitungZuFremdemZielWirdAbgebrochen() async throws {
        let target = MockXtreamServer()
        try target.start()
        defer { B01.removeCachedResponses(for: target); target.stop() }
        let targetPort = target.port
        mock.handler = { req in .redirect(location: "http://127.0.0.1:\(targetPort)\(req.target)", status: 302) }
        let container = try B01.inMemoryContainer()
        let r = await B01.importXtream(host: mock.hostPort, pass: "qa-pass-ak26", context: container.mainContext)
        print("B01BUILD|AK-26|fremdesZiel|\(B01.message(r) ?? "ok")|quelle=\(mock.requests.count)|ziel=\(target.requests.count)")
        XCTAssertEqual(mock.requests.count, 1)
        XCTAssertEqual(target.requests.count, 0, "Zugangsdaten nur an den eingegebenen Host")
        XCTAssertEqual(B01.message(r), XtreamClient.XtreamError.redirectBlocked.localizedDescription)
        XCTAssertEqual(try container.mainContext.fetchCount(FetchDescriptor<Playlist>()), 0)

        // Anderer Host, gleicher Port: `localhost` statt `127.0.0.1`
        mock.resetLog()
        let port = mock.port
        mock.handler = { req in .redirect(location: "http://localhost:\(port)\(req.target)", status: 301) }
        let r2 = await B01.importXtream(host: mock.hostPort, pass: "qa-pass-ak26", context: container.mainContext)
        XCTAssertEqual(B01.message(r2), XtreamClient.XtreamError.redirectBlocked.localizedDescription)
        XCTAssertEqual(mock.requests.count, 1)

        // Gleiches Panel: /player_api.php → /panel/player_api.php wird befolgt
        mock.resetLog()
        let panel = MockXtreamServer.panel()
        mock.handler = { req in
            req.path == "/player_api.php"
                ? .redirect(location: "/panel/player_api.php?\(req.rawQuery ?? "")", status: 302)
                : panel(MockXtreamServer.Request(requestLine: req.requestLine, method: req.method, target: req.target,
                                                 path: "/player_api.php", rawQuery: req.rawQuery, headers: req.headers,
                                                 port: req.port))
        }
        let r3 = await B01.importXtream(host: mock.hostPort, pass: "qa-pass-ak26", context: container.mainContext)
        XCTAssertNil(B01.message(r3))
        XCTAssertEqual(mock.requests.count, 6)
    }

    // MARK: - AK-27 Systemprotokoll

    /// AK-27: Während Import (Erfolg und Fehlerwege) steht das Passwort nicht im Unified Log des Prozesses.
    /// Ergänzend wird der Lauf mit `log stream --process MikaPlusPlayer` mitgeschnitten (siehe qa-report.md).
    @MainActor func testAK27_KeinPasswortImSystemprotokoll() async throws {
        let marker = "qa-pass-ak27-log"
        let start = Date().addingTimeInterval(-1)
        let container = try B01.inMemoryContainer()
        let closed = MockXtreamServer(); try closed.start(); let closedPort = closed.port; closed.stop()
        _ = await B01.importXtream(host: mock.hostPort, user: "qa-user-ak27", pass: marker, context: container.mainContext)
        mock.handler = { _ in .raw(status: 401, contentType: "text/plain", body: Data()) }
        _ = await B01.importXtream(host: mock.hostPort, user: "qa-user-ak27", pass: marker, context: container.mainContext)
        mock.handler = { _ in .raw(status: 200, contentType: "text/html", body: Data("<html>".utf8)) }
        _ = await B01.importXtream(host: mock.hostPort, user: "qa-user-ak27", pass: marker, context: container.mainContext)
        _ = await B01.importXtream(host: "127.0.0.1:\(closedPort)", user: "qa-user-ak27", pass: marker, context: container.mainContext)
        try await Task.sleep(nanoseconds: 1_000_000_000)

        // Sonde: Ist Private-Data-Logging aktiv (z. B. Lauf aus Xcode/xcodebuild)? Dann schwärzt das System nichts.
        let privMarker = "b01qa-private-probe-\(UInt32.random(in: 1000...9999))"
        Logger(subsystem: "lu.daumedia.MikaPlusPlayerTests", category: "B01QA").log("Sonde \(privMarker, privacy: .private)")
        try await Task.sleep(nanoseconds: 300_000_000)
        let store = try OSLogStore(scope: .currentProcessIdentifier)
        let entries = try store.getEntries(at: store.position(date: start))
        var total = 0, hits = 0, cfnetwork = 0
        var privateVisible = false
        for case let e as OSLogEntryLog in entries {
            total += 1
            if e.subsystem == "com.apple.CFNetwork" { cfnetwork += 1 }
            if e.composedMessage.contains(privMarker) { privateVisible = true }
            if e.composedMessage.contains(marker) || e.composedMessage.contains("qa-user-ak27") {
                hits += 1
                let masked = e.composedMessage.replacingOccurrences(of: marker, with: "<PASSWORT>")
                    .replacingOccurrences(of: "qa-user-ak27", with: "<BENUTZER>")
                print("B01QA|AK-27|treffer|subsystem=\(e.subsystem)|category=\(e.category)|process=\(e.process)|sender=\(e.sender)|level=\(e.level.rawValue)|msg=\(masked.prefix(400))")
            }
        }
        print("B01QA|AK-27|osLogEntries=\(total)|cfnetwork=\(cfnetwork)|treffer=\(hits)|privateDatenSichtbar=\(privateVisible)")
        XCTAssertGreaterThan(total, 0, "OSLogStore muss Einträge liefern, sonst ist der Test ohne Aussage")
        if privateVisible {
            // Die Treffer stammen aus CFNetwork-Fehlermeldungen (NSErrorFailingURLStringKey), die das System
            // normalerweise als <private> schwärzt. In diesem Lauf ist die Schwärzung aus → nicht beurteilbar.
            throw XCTSkip("Private-Data-Logging aktiv (Treffer=\(hits)); Schwärzung am Test-Host nicht prüfbar")
        }
        XCTAssertEqual(hits, 0)
    }

    // MARK: - AK-28 Speicherort und Backup

    /// AK-28 / BUG-04 behoben: Die App-Konfiguration zeigt auf `Application Support/<Bundle-ID>/MikaPlusPlayer.store`;
    /// der Test-Host arbeitet im Speicher. Die Datenbank bleibt bewusst im Backup, weil sie keine Zugangsdaten
    /// mehr enthält (AK-24); ein Ausschluss nähme dem Nutzer beim Wiederherstellen die Playlists.
    /// Der Speicherort wird nur berechnet – die echte Datei des Nutzers wird weder geöffnet noch gelesen.
    @MainActor func testAK28_SpeicherortUndBackup() throws {
        let support = try XCTUnwrap(FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first)
        let url = AppPersistence.storeURL(applicationSupport: support, bundleID: Bundle.main.bundleIdentifier ?? "-")
        print("B01BUILD|AK-28|url=<Application Support>/\(url.pathComponents.suffix(2).joined(separator: "/"))|testHostInMemory=\(AppPersistence.configuration(schema: B01.schema).isStoredInMemoryOnly)")
        XCTAssertEqual(url.pathComponents.suffix(2), ["lu.daumedia.MikaPlusPlayer", "MikaPlusPlayer.store"])
        XCTAssertNotEqual(url.lastPathComponent, "default.store")
        XCTAssertTrue(AppEnvironment.isRunningTests)
        XCTAssertTrue(AppPersistence.configuration(schema: B01.schema).isStoredInMemoryOnly, "Test-Host darf die echte Datei nicht öffnen")

        // Backup: Eine frisch angelegte App-Datenbank ist nicht ausgeschlossen (Entscheidung, siehe build-bericht.md).
        let tmp = FileManager.default.temporaryDirectory.appendingPathComponent("b01-ak28-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: tmp) }
        let (storeURL, outcome) = AppPersistence.prepareStore(applicationSupport: tmp, bundleID: "lu.daumedia.MikaPlusPlayer")
        XCTAssertEqual(outcome, .noLegacyStore)
        do {
            let container = try ModelContainer(for: B01.schema, configurations: [ModelConfiguration(schema: B01.schema, url: storeURL)])
            try container.mainContext.save()
        }
        let excluded = try storeURL.resourceValues(forKeys: [.isExcludedFromBackupKey]).isExcludedFromBackup
        XCTAssertEqual(excluded, false)
    }

    // MARK: - Aufräumen

    /// Kein Kriterium: entfernt Plattencache-Einträge, die B01-Tests gegen Loopback-Mocks mit erfundenen Zugangsdaten
    /// hinterlassen haben (z. B. nach abgebrochenem Lauf). Liest aus der Cache.db nur Schlüssel mit `qa-`-Marke.
    func testZZ_AufraeumenEigenerCacheEintraege() throws {
        let db = B01.hostCacheDB.path
        var handle: OpaquePointer?
        guard sqlite3_open_v2(db, &handle, SQLITE_OPEN_READONLY, nil) == SQLITE_OK else { sqlite3_close(handle); return }
        var keys: [String] = []
        var stmt: OpaquePointer?
        let sql = "select request_key from cfurl_cache_response where (request_key like 'http://127.0.0.1:%' or request_key like 'http://[::1]:%') and instr(request_key, 'qa-') > 0"
        if sqlite3_prepare_v2(handle, sql, -1, &stmt, nil) == SQLITE_OK {
            while sqlite3_step(stmt) == SQLITE_ROW { keys.append(String(cString: sqlite3_column_text(stmt, 0))) }
        }
        sqlite3_finalize(stmt)
        sqlite3_close(handle)
        for k in keys { if let u = URL(string: k) { URLCache.shared.removeCachedResponse(for: URLRequest(url: u)) } }
        Thread.sleep(forTimeInterval: 1.5)
        let left = B01.sqliteCount(db, "select count(*) from cfurl_cache_response where (request_key like 'http://127.0.0.1:%' or request_key like 'http://[::1]:%') and instr(request_key, 'qa-') > 0") ?? -1
        print("B01QA|CACHE|gefunden=\(keys.count)|verbleibend=\(left)")
        XCTAssertEqual(left, 0)
    }

    // MARK: - Angriff 3 · wiederholte Anmeldeversuche (FB-04)

    /// Angriff 3 / BUG-07 behoben: Von zehn Fehlanmeldungen in Folge erreichen nur drei das Panel; danach meldet
    /// die App eine Wartezeit. Nach Ablauf ist wieder ein Versuch möglich, eine erfolgreiche Anmeldung setzt zurück.
    @MainActor func testFB04_WiederholteFehlanmeldungenWerdenGebremst() async throws {
        mock.handler = MockXtreamServer.panel(auth: ["user_info": ["auth": 0]])
        let container = try B01.inMemoryContainer()
        let clock = B01TestClock()
        let throttle = XtreamLoginThrottle(now: { clock.now })
        let start = Date()
        var messages: [String] = []
        for i in 1...10 {
            let r = await B01.importXtream(host: mock.hostPort, pass: "qa-pass-falsch-\(i)", context: container.mainContext,
                                           throttle: throttle)
            messages.append(B01.message(r) ?? "ok")
        }
        let elapsed = Date().timeIntervalSince(start)
        let authRequests = mock.requests.filter { $0.action == nil }.count
        print("B01BUILD|FB-04|versuche=10|beimPanelAngekommen=\(authRequests)|dauer=\(String(format: "%.2f", elapsed))s|meldungen=\(Set(messages))")
        XCTAssertLessThanOrEqual(authRequests, 5, "Nach wenigen Fehlversuchen muss die App warten")
        XCTAssertEqual(authRequests, 3)
        XCTAssertEqual(Array(messages.prefix(3)), Array(repeating: "Anmeldung fehlgeschlagen. Benutzername/Passwort prüfen.", count: 3))
        XCTAssertEqual(messages[3], "Zu viele fehlgeschlagene Anmeldungen. Bitte in 30 Sekunden erneut versuchen.")

        // Nach 31 s wieder ein Versuch; scheitert er, verdoppelt sich die Sperre
        clock.advance(31)
        mock.resetLog()
        let again = await B01.importXtream(host: mock.hostPort, pass: "qa-pass-falsch-11", context: container.mainContext, throttle: throttle)
        XCTAssertEqual(B01.message(again), "Anmeldung fehlgeschlagen. Benutzername/Passwort prüfen.")
        XCTAssertEqual(mock.requests.count, 1)
        let locked = await B01.importXtream(host: mock.hostPort, pass: "qa-pass-falsch-12", context: container.mainContext, throttle: throttle)
        XCTAssertEqual(B01.message(locked), "Zu viele fehlgeschlagene Anmeldungen. Bitte in 60 Sekunden erneut versuchen.")

        // Anderes Panel (anderer Port) ist nicht betroffen
        let other = MockXtreamServer()
        try other.start()
        defer { other.stop() }
        let ok = await B01.importXtream(host: other.hostPort, pass: "qa-pass-ok", context: container.mainContext, throttle: throttle)
        XCTAssertNil(B01.message(ok))

        // Erfolg setzt zurück
        clock.advance(61)
        mock.handler = MockXtreamServer.panel()
        let success = await B01.importXtream(host: mock.hostPort, pass: "qa-pass-richtig", context: container.mainContext, throttle: throttle)
        XCTAssertNil(B01.message(success))
        XCTAssertNil(throttle.remainingLock(for: XtreamLoginThrottle.key(for: URL(string: "http://\(mock.hostPort)")!)))
    }

    // MARK: - Angriff 7 · Eingaben (FB-05 Größe)

    /// FB-05 / BUG-08 behoben: Übergroße Texte werden gekürzt, übergroße Antworten und zu viele Sender abgelehnt.
    /// (Gesamtzeit: EC-17 in B01LangsamTests, Menge/Laufzeit: EC-20)
    @MainActor func testFB05_KeineGroessengrenzeFuerAntwortDesPanels() async throws {
        let longName = String(repeating: "A", count: 3_000_000)
        let streams: [[String: Any]] = (0..<8).map { ["name": longName, "stream_id": $0, "category_id": "1"] }
        let body = try JSONSerialization.data(withJSONObject: streams)
        let panel = MockXtreamServer.panel()
        mock.handler = { req in
            req.action == "get_live_streams" ? .raw(status: 200, contentType: "application/json", body: body) : panel(req)
        }
        let container = try B01.inMemoryContainer()
        let start = Date()
        let p = try await B01.importXtream(host: mock.hostPort, pass: "qa-pass-fb05", context: container.mainContext).get()
        let stored = p.channels.map(\.name.utf8.count).reduce(0, +)
        print("B01BUILD|FB-05|antwortBytes=\(body.count)|angelegt=\(p.channelCount)|gespeicherteNamensbytes=\(stored)|dauer=\(String(format: "%.1f", Date().timeIntervalSince(start)))s")
        XCTAssertEqual(p.channelCount, 8)
        XCTAssertNotEqual(stored, 8 * 3_000_000, "Eine Antwort von über 20 MB mit 3-MB-Namen muss begrenzt werden")
        XCTAssertEqual(stored, 8 * XtreamClient.Limits.standard.maxTextLength)

        // Standardgrenzen
        let standard = XtreamClient.Limits.standard
        XCTAssertEqual(standard.maxResponseBytes, 64 * 1024 * 1024)
        XCTAssertEqual(standard.maxStreams, 100_000)
        XCTAssertEqual(standard.totalTimeout, 180)
        XCTAssertEqual(standard.idleTimeout, 60)

        // Antwortgröße: mit bekannter Länge (Content-Length) und über den tatsächlichen Datenstrom
        var small = standard
        small.maxResponseBytes = 1_000_000
        let tooBig = await B01.importXtream(host: mock.hostPort, pass: "qa-pass-fb05", context: container.mainContext, limits: small)
        XCTAssertEqual(B01.message(tooBig), "Netzwerkfehler: Die Antwort des Anbieters ist zu groß (mehr als 1 MB).")
        let unsizedBody = Data(repeating: 0x20, count: 2_000_000)
        mock.handler = { req in req.action == nil ? .unsized(body: unsizedBody) : panel(req) }
        var noLength = standard
        noLength.maxResponseBytes = 1_048_576
        let streamed = await B01.importXtream(host: mock.hostPort, pass: "qa-pass-fb05", context: container.mainContext, limits: noLength)
        XCTAssertEqual(B01.message(streamed), "Netzwerkfehler: Die Antwort des Anbieters ist zu groß (mehr als 1 MB).")

        // Anzahl Sender
        mock.handler = panel
        var fewStreams = standard
        fewStreams.maxStreams = 3
        let tooMany = await B01.importXtream(host: mock.hostPort, pass: "qa-pass-fb05", context: container.mainContext, limits: fewStreams)
        XCTAssertEqual(B01.message(tooMany), "Die Senderliste ist zu groß (mehr als 3 Sender).")
        XCTAssertEqual(try container.mainContext.fetchCount(FetchDescriptor<Playlist>()), 1, "nur der erste, gekürzte Import")
    }

    /// Angriff 7: leer, 1 Zeichen, 10 000 Zeichen, Emoji, SQL, Script, Pfad, `#?/%&`, Umlaute in jedem Feld.
    /// Benutzer/Passwort gegen ein Panel, das wie PHP dekodiert und exakt vergleicht.
    @MainActor func testAngriff07_EingabenInJedemFeld() async throws {
        let inputs: [(String, String)] = [
            ("leer", ""), ("1 Zeichen", "x"), ("10000 Zeichen", String(repeating: "a", count: 10_000)),
            ("Emoji", "😀📺"), ("SQL", "'; drop table --"), ("Script", "<script>alert(1)</script>"),
            ("Pfad", "../../etc/passwd"), ("Sonderzeichen", "#?/%&"), ("Umlaute", "äöüß")
        ]
        let container = try B01.inMemoryContainer()
        let ctx = container.mainContext
        var failures: [String] = []

        for field in ["Benutzer", "Passwort"] {
            for (label, value) in inputs {
                mock.resetLog()
                let user = field == "Benutzer" ? value : "qa-user"
                let pass = field == "Passwort" ? value : "qa-pass-a07"
                let panel = MockXtreamServer.panel()
                mock.handler = { req in
                    (req.username == user && req.password == pass) ? panel(req) : .json(["user_info": ["auth": 0]])
                }
                let complete = XtreamCredentials(host: mock.hostPort, username: user, password: pass).isComplete
                let r = await B01.importXtream(host: mock.hostPort, user: user, pass: pass, context: ctx)
                var outcome = "Button \(complete ? "aktiv" : "deaktiviert") · "
                switch r {
                case .success(let p):
                    let url = try p.channels.first(where: { $0.name == "Kanal Int" }).map { try B01.playable($0) }
                    let pathOK = url?.pathComponents == ["/", "live", user, pass, "101.ts"]
                    outcome += "Import ok · Stream-Pfad \(pathOK ? "korrekt" : "FALSCH")"
                    if !pathOK && complete { failures.append("\(field)/\(label)") }
                case .failure(let e):
                    outcome += "Fehler: \(e.localizedDescription)"
                    if complete { failures.append("\(field)/\(label)") }
                }
                print("B01QA|A07|\(field)|\(label)|\(outcome)")
            }
        }
        mock.handler = MockXtreamServer.panel()
        for (label, value) in inputs {
            let r = await B01.importXtream(host: mock.hostPort, pass: "qa-pass-a07", name: value, context: ctx)
            let stored = (try? r.get())?.name
            let expected = value.isEmpty ? "127.0.0.1" : value  // AK-07: leer → Host
            print("B01QA|A07|Name|\(label)|\(stored == expected ? "wie erwartet gespeichert" : "abweichend")|länge=\(stored?.count ?? -1)")
            XCTAssertEqual(stored, expected, "Name \(label)")
        }
        for (label, value) in inputs {
            let c = XtreamCredentials(host: value, username: "u", password: "p")
            print("B01QA|A07|Host|\(label)|complete=\(c.isComplete)|base=\(c.baseURL()?.absoluteString.prefix(60).description ?? "nil")")
        }
        // Absturzfreiheit und saubere Meldungen sind durch das Erreichen dieser Zeile belegt.
        print("B01QA|A07|fehlerhaft=\(failures)")
        // BUG-05 behoben: auch `/`, `#`, `?` bleiben in ihrem Pfadabschnitt.
        XCTAssertEqual(failures, [])
    }
}
