import XCTest
import SwiftUI
import SwiftData
import SQLite3
@testable import MikaPlusPlayer

/// B02+B03 · Nacharbeit nach dem Review vom 2026-09-27 (Funde R-01 bis R-11), Teil Import/Zugangsdaten/Start.
/// Temp-Datenbanken, Test-Schlüsselbunddienst dieses Laufs, Loopback-Server, erfundene Zugangsdaten, tonlos.
///
/// Umgebungsvariablen (bei `xcodebuild` mit Präfix `TEST_RUNNER_`):
/// - `B02_NB_VOLUME=<Mountpoint>` – kleines Datenträgerabbild (6 MB) für R-02; ohne wird der Test übersprungen.
final class B02NacharbeitTests: B02TestCase {

    private var env: [String: String] { ProcessInfo.processInfo.environment }

    // MARK: R-02 · Import auf vollem Datenträger

    /// R-02: 40.000 Sender per URL (mit Zugangsdaten) in eine Datenbank auf einem 6-MB-Abbild, davon 3 MB belegt. Der
    /// Import scheitert nach dem ersten Block, und auch das sofortige Aufräumen scheitert am vollen Datenträger. Soll:
    /// deutsche Meldung, keine halbe Playlist in der Übersicht (auch nicht nach dem Neuöffnen), kein Schlüsselbund-Eintrag;
    /// sobald wieder Platz ist, entfernt der nächste Start den Rest aus der Datei.
    @MainActor func testR02_ImportAufVollemDatentraegerHinterlaesstKeineHalbePlaylist() async throws {
        guard let volume = env["B02_NB_VOLUME"], FileManager.default.fileExists(atPath: volume) else {
            throw XCTSkip("kein Datenträgerabbild (TEST_RUNNER_B02_NB_VOLUME)")
        }
        let root = URL(fileURLWithPath: volume)
        let dir = root.appendingPathComponent("r02-\(UUID().uuidString.prefix(8))", isDirectory: true)
        let filler = root.appendingPathComponent("r02-belegt")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        try Data(count: 3 * 1024 * 1024).write(to: filler)
        defer { try? FileManager.default.removeItem(at: filler); try? FileManager.default.removeItem(at: dir) }
        let storeURL = dir.appendingPathComponent("MikaPlusPlayer.store")
        var message = "kein Fehler"
        var inContext: [String] = []
        var shown: [String] = []
        do {
            let container = try AppPersistence.diskContainer(at: storeURL, schema: AppSchema.schema)
            let ctx = container.mainContext
            server.handler = { _ in B02Server.ok(B02.grosseListe(40_000)) }
            let r = await B02.importURL(server.url("/get.php?username=qa-user&password=qa-pass-nb-r02&type=m3u"), name: "Voll", ctx)
            message = B02.message(r) ?? "kein Fehler"
            let all = (try? ctx.fetch(FetchDescriptor<Playlist>())) ?? []
            inContext = all.map { "\($0.name)=\($0.channelCount)" }
            shown = all.filter { !$0.isUnfinished }.map(\.name)   // wie `PlaylistsView.visiblePlaylists`
            _ = container
        }
        try await Task.sleep(nanoseconds: 300_000_000)
        var reopenedShown: [String] = []
        var inFileBefore: [String] = []
        do {
            let reopened = try AppPersistence.diskContainer(at: storeURL, schema: AppSchema.schema)
            let all = try reopened.mainContext.fetch(FetchDescriptor<Playlist>())
            inFileBefore = all.map { "\($0.name)=\($0.channelCount)" }
            reopenedShown = all.filter { !$0.isUnfinished }.map(\.name)
        }
        let keychain = B01QA2.keychainCount(service: XtreamCredentialStore.standard.service)
        // Platz frei, nächster Start
        try FileManager.default.removeItem(at: filler)
        try await Task.sleep(nanoseconds: 300_000_000)
        do {
            let (container, _) = AppPersistence.openStore(at: storeURL, schema: AppSchema.schema)
            _ = await AppPersistence.finishLaunch(container: container, storeURL: storeURL, store: PlaylistStore(),
                                                  credentials: .standard, defaults: nil)
        }
        try await Task.sleep(nanoseconds: 300_000_000)
        let afterStart = B02.rows(storeURL.path, "select (select count(*) from ZPLAYLIST), (select count(*) from ZCHANNEL)").first ?? []
        B02.log("NB|R-02|meldung=\(message)|kontext=\(inContext)|uebersicht=\(shown)|dateiNachNeuoeffnen=\(inFileBefore)|uebersichtNachNeuoeffnen=\(reopenedShown)|schluesselbund=\(keychain)|nachPlatzUndStart(playlists,sender)=\(afterStart)")
        XCTAssertEqual(message, PlaylistStoreError.createFailed.errorDescription, "deutsche Meldung statt SQLite-Fehler")
        XCTAssertEqual(shown, [], "keine halbe Playlist in der Übersicht")
        XCTAssertEqual(reopenedShown, [], "keine halbe Playlist in der Übersicht nach dem Neuöffnen")
        XCTAssertTrue(inFileBefore.allSatisfy { $0.hasSuffix("=\(PlaylistStore.unfinishedChannelCount)") }, "höchstens ein unfertiger Rest: \(inFileBefore)")
        XCTAssertEqual(keychain, 0)
        XCTAssertEqual(afterStart, ["0", "0"], "Rest nach dem nächsten Start entfernt")
    }

    /// R-02 ohne Abbild: Eine unfertige Playlist (Rest eines gescheiterten oder abgebrochenen Anlegens) ist unsichtbar
    /// und verschwindet beim nächsten Anlegen bzw. bei der Wartung beim Start; fertige Playlists bleiben.
    @MainActor func testR02_UnfertigePlaylistWirdEntfernt() async throws {
        let dir = try tempDir("r02b")
        let (container, storeURL) = try B02.fileContainer(in: dir)
        let ctx = container.mainContext
        func leftover(_ name: String) throws -> UUID {
            let c = ModelContext(container)
            let p = Playlist(name: name, sourceURL: URL(string: "http://h.example/\(name).m3u"), channelCount: PlaylistStore.unfinishedChannelCount)
            c.insert(p)
            var channels: [Channel] = []
            for i in 0..<300 {
                let ch = Channel(name: "\(name) \(i)", streamURL: URL(string: "\(B02.dead)/\(name)/\(i).ts")!, playlistID: p.id)
                c.insert(ch)
                channels.append(ch)
            }
            p.channels.append(contentsOf: channels)
            try c.save()
            return p.id
        }
        _ = try leftover("RestA")
        server.handler = { _ in B02Server.ok(B02.zweiSenderData) }
        let kept = try await PlaylistImporter(modelContext: ctx).importFromURL(server.url("/liste.m3u"), name: "Fertig")
        let afterImport = B02.rows(storeURL.path, "select ZNAME, ZCHANNELCOUNT from ZPLAYLIST order by ZNAME").map { $0.joined(separator: "=") }
        let channelsAfterImport = B02.int(storeURL.path, "select count(*) from ZCHANNEL")
        _ = try leftover("RestB")
        let result = await AppPersistence.finishLaunch(container: container, storeURL: storeURL, store: PlaylistStore(),
                                                       credentials: .standard, defaults: nil)
        let afterStart = B02.rows(storeURL.path, "select ZNAME, ZCHANNELCOUNT from ZPLAYLIST order by ZNAME").map { $0.joined(separator: "=") }
        let channelsAfterStart = B02.int(storeURL.path, "select count(*) from ZCHANNEL")
        B02.log("NB|R-02b|nachImport=\(afterImport)|sender=\(channelsAfterImport)|nachStart=\(afterStart)|sender=\(channelsAfterStart)|umstellung=\(result)")
        XCTAssertEqual(afterImport, ["Fertig=2"], "Rest des früheren Anlegens entfernt, neue Playlist fertig")
        XCTAssertEqual(channelsAfterImport, 2)
        XCTAssertEqual(afterStart, ["Fertig=2"], "Wartung beim Start entfernt Reste")
        XCTAssertEqual(channelsAfterStart, 2)
        XCTAssertEqual(kept.channelCount, 2)
    }

    // MARK: R-03 · Benutzerinfo und Query mit verschiedenen Passwörtern

    func testR03_BenutzerinfoUndQueryMitVerschiedenenPasswoertern() throws {
        typealias Marker = M3UCredentials.Marker
        let source = URL(string: "http://qa-info:qa-pass-info@h.example/get.php?username=qa-user&password=qa-pass-query&type=m3u")!
        let split = try XCTUnwrap(M3UCredentials.split(source))
        XCTAssertEqual(split.secret.password, "qa-pass-query")
        XCTAssertEqual(split.secret.username, "qa-user")
        XCTAssertEqual(split.secret.infoPassword, "qa-pass-info")
        XCTAssertEqual(split.secret.infoUsername, "qa-info")
        let stored = split.stored.absoluteString
        B02.log("NB|R-03|gespeichert=\(stored)")
        for secret in ["qa-pass-info", "qa-pass-query", "qa-info", "qa-user"] {
            XCTAssertFalse(stored.contains(secret), "\(secret) im Klartext: \(stored)")
        }
        XCTAssertEqual(stored, "http://\(Marker.secondInfoUser):\(Marker.secondInfoPassword)@h.example/get.php?username=\(Marker.queryUser)&password=\(Marker.queryPassword)&type=m3u")
        XCTAssertEqual(M3UCredentials.restore(split.stored, secret: split.secret), source, "Abruf wie eingegeben")
        XCTAssertNil(M3UCredentials.split(split.stored), "Platzhalter gelten nicht als Zugangsdaten")

        // Stream-Adressen: Benutzerinfo mit dem einen oder dem anderen Passwort, Pfad, Query
        let streams = ["http://qa-info:qa-pass-info@cdn.example/1.ts", "http://qa-user:qa-pass-query@cdn.example/2.ts",
                       "http://h.example/live/qa-user/qa-pass-query/3.ts", "http://h.example/4.m3u8?token=qa-pass-query",
                       "http://h.example/5.m3u8"].map { URL(string: $0)! }
        for original in streams {
            let redacted = M3UCredentials.redact(original, secret: split.secret)
            for secret in ["qa-pass-info", "qa-pass-query"] {
                XCTAssertFalse(redacted.absoluteString.contains(secret), "\(original) → \(redacted)")
            }
            XCTAssertEqual(M3UCredentials.restore(redacted, secret: split.secret), original, original.absoluteString)
        }

        // Gespeicherte Einträge älterer Stände (ohne die neuen Felder) lesen sich unverändert
        let old = Data(#"{"sourceURL":"http://qa-user:p@h.example/l.m3u","username":"qa-user","password":"p"}"#.utf8)
        let decoded = try JSONDecoder().decode(M3USecret.self, from: old)
        XCTAssertEqual(decoded, M3USecret(sourceURL: "http://qa-user:p@h.example/l.m3u", username: "qa-user", password: "p"))
        XCTAssertNil(decoded.infoPassword)
        let same = try XCTUnwrap(M3UCredentials.split(URL(string: "http://qa-user:gleich@h.example/get.php?username=qa-user&password=gleich")!))
        XCTAssertNil(same.secret.infoPassword, "gleiches Passwort: wie bisher ein Eintrag")
    }

    /// R-03 über den echten Import: nichts von beiden Passwörtern in der Datei, Abruf beim Aktualisieren wie eingegeben.
    @MainActor func testR03_ImportUndAktualisierenMitZweiPasswoertern() async throws {
        let dir = try tempDir("r03")
        let (container, storeURL) = try B02.fileContainer(in: dir)
        let ctx = container.mainContext
        server.handler = { _ in B02Server.ok(B02.zweiSenderData) }
        let url = "http://qa-info:qa-pass-nb-info@\(server.hostPort)/get.php?username=qa-user&password=qa-pass-nb-query"
        let p = try await PlaylistImporter(modelContext: ctx).importFromURL(url, name: "Zwei")
        server.resetLog()
        try await PlaylistImporter(modelContext: ctx).refresh(p)
        let request = server.requests.first
        try await Task.sleep(nanoseconds: 300_000_000)
        let bytes = ["qa-pass-nb-info", "qa-pass-nb-query"].map { B02.bytes($0, storeURL).values.reduce(0, +) }
        B02.log("NB|R-03|import|sourceURL=\(p.sourceURL?.absoluteString ?? "nil")|klartextBytes=\(bytes)|aktualisieren=\(request?.requestLine ?? "-")")
        XCTAssertEqual(bytes, [0, 0])
        XCTAssertEqual(request?.requestLine, "GET /get.php?username=qa-user&password=qa-pass-nb-query HTTP/1.1")
        XCTAssertEqual(try XtreamCredentialStore.standard.loadM3U(for: p.id)?.sourceURL, url, "Abruf beim Aktualisieren wie eingegeben")
    }

    // MARK: R-08 · Abbruch vor dem Verdichten

    @MainActor func testR08_AbbruchVorDemVerdichtenWirdBeimNaechstenStartNachgeholt() async throws {
        let pass = "qa-pass-nb-r08-\(UInt32.random(in: 1000...9999))"
        let dir = try tempDir("r08")
        let storeURL = dir.appendingPathComponent(AppPersistence.storeFileName)
        // Einstellungen nur im Arbeitsspeicher (eine eigene Suite hinterließe eine Datei unter ~/Library/Preferences)
        let defaults = try XCTUnwrap(NBMemoryDefaults(suiteName: nil))
        do {
            let container = try AppPersistence.diskContainer(at: storeURL, schema: AppSchema.schema)
            let ctx = ModelContext(container)
            for n in 0..<3 {
                let p = Playlist(name: "Alt \(n)", sourceURL: URL(string: "http://h.example/get.php?username=qa-user&password=\(pass)&n=\(n)")!)
                ctx.insert(p)
                var channels: [Channel] = []
                for i in 0..<200 {
                    let ch = Channel(name: "S\(n)-\(i)", streamURL: URL(string: "http://h.example/live/qa-user/\(pass)/\(n)\(i).ts")!, playlistID: p.id)
                    ctx.insert(ch)
                    channels.append(ch)
                }
                p.channels.append(contentsOf: channels)
                p.channelCount = channels.count
            }
            try ctx.save()
        }
        try await Task.sleep(nanoseconds: 300_000_000)
        // Erster Start: umgestellt und gespeichert, aber vor dem Verdichten beendet (= ohne Speicherort zum Verdichten)
        var first = AppPersistence.CredentialMigrationResult()
        do {
            let (container, _) = AppPersistence.openStore(at: storeURL, schema: AppSchema.schema)
            first = AppPersistence.migrateCredentials(container: container, storeURL: nil, store: .standard, defaults: defaults)
        }
        try await Task.sleep(nanoseconds: 300_000_000)
        let pending = defaults.bool(forKey: AppPersistence.compactionPendingDefaultsKey)
        let bytesAfterMigration = B02.bytes(pass, storeURL).values.reduce(0, +)
        // Was ein abgebrochener Lauf hinterlassen kann (Review: 0 bzw. 1 Vorkommen je Lauf, nicht vorhersagbar), hier
        // deterministisch: Klartext in freien Seiten der Datei (eigene Verbindung ohne secure_delete, Tabelle danach weg).
        B02NacharbeitTests.leaveFreePages(containing: pass, in: storeURL)
        let bytesAfterAbort = B02.bytes(pass, storeURL).values.reduce(0, +)
        let freePages = B02.int(storeURL.path, "PRAGMA freelist_count")
        // Nächster Start: nichts mehr umzustellen, aber das Verdichten steht aus
        var second = AppPersistence.CredentialMigrationResult()
        do {
            let (container, _) = AppPersistence.openStore(at: storeURL, schema: AppSchema.schema)
            second = await AppPersistence.finishLaunch(container: container, storeURL: storeURL, store: PlaylistStore(),
                                                       credentials: .standard, defaults: defaults)
        }
        try await Task.sleep(nanoseconds: 300_000_000)
        let bytesAfterStart = B02.bytes(pass, storeURL)
        B02.log("NB|R-08|ersterStart=\(first)|merker=\(pending)|klartextNachUmstellung=\(bytesAfterMigration)|klartextInFreienSeiten=\(bytesAfterAbort)|freieSeiten=\(freePages)|naechsterStart=\(second)|klartextDanach=\(bytesAfterStart)|merkerDanach=\(defaults.bool(forKey: AppPersistence.compactionPendingDefaultsKey))")
        XCTAssertEqual(first.migratedPlaylists, 3)
        XCTAssertTrue(pending, "Merker nach Umstellung ohne Verdichten")
        XCTAssertGreaterThan(bytesAfterAbort, 0, "Ausgangslage der Reproduktion: Klartext-Rest in freien Seiten")
        XCTAssertGreaterThan(freePages, 0)
        XCTAssertEqual(second, AppPersistence.CredentialMigrationResult(), "nichts mehr umzustellen")
        XCTAssertEqual(bytesAfterStart.values.reduce(0, +), 0, "Klartext-Rest nach dem nächsten Start: \(bytesAfterStart)")
        XCTAssertFalse(defaults.bool(forKey: AppPersistence.compactionPendingDefaultsKey), "Merker nach dem Verdichten entfernt")
    }

    // MARK: R-09 · „Öffnen mit" nur für M3U

    func testR09_NurM3UDateienWerdenGeoeffnet() {
        for name in ["a.m3u", "a.M3U", "a.m3u8", "Liste.M3U8"] {
            XCTAssertTrue(PlaylistDocumentHandler.isPlaylistFile(URL(fileURLWithPath: "/tmp/\(name)")), name)
        }
        for name in ["a.txt", "a.json", "a.pls", "a.xspf", "a", "a.m3u.txt", "a.m3u8.zip"] {
            XCTAssertFalse(PlaylistDocumentHandler.isPlaylistFile(URL(fileURLWithPath: "/tmp/\(name)")), name)
        }
        XCTAssertEqual(ImportError.unsupportedFile.errorDescription, "Nur M3U-Playlists (.m3u, .m3u8) lassen sich importieren.")
    }

    // MARK: R-10 · Umstellung beim Start blockiert nicht

    /// R-10: Datenbank im Speicherformat vor der Reparatur (Zugangsdaten im Klartext) mit 10 × 3.000 M3U-Sendern und
    /// 1.000 Xtream-Sendern; die Umstellung beim Start läuft über `LaunchMaintenance`. Soll: der Main-Thread reagiert
    /// währenddessen (Wachhund ≤ 0,5 s), die Oberfläche sieht „läuft" und danach „fertig", alles ist umgestellt.
    @MainActor func testR10_UmstellungBeimStartLaeuftImHintergrund() async throws {
        let pass = "qa-pass-nb-r10-\(UInt32.random(in: 1000...9999))"
        let dir = try tempDir("r10")
        let storeURL = dir.appendingPathComponent(AppPersistence.storeFileName)
        let lists = Int(env["B02_NB_R10_LISTEN"] ?? "") ?? 10
        do {
            let container = try AppPersistence.diskContainer(at: storeURL, schema: AppSchema.schema)
            let ctx = ModelContext(container)
            for n in 0..<lists {
                let p = Playlist(name: "Alt \(n)", sourceURL: URL(string: "http://h.example/get.php?username=qa-user&password=\(pass)&n=\(n)")!)
                ctx.insert(p)
                var channels: [Channel] = []
                for i in 0..<3_000 {
                    let ch = Channel(name: "S\(n)-\(i)", streamURL: URL(string: "http://h.example/live/qa-user/\(pass)/\(n)-\(i).ts")!,
                                     tvgID: "s.\(n).\(i)", isFavorite: i == 7, playlistID: p.id)
                    ctx.insert(ch)
                    channels.append(ch)
                }
                p.channels.append(contentsOf: channels)
                p.channelCount = channels.count
                try ctx.save()
            }
            let x = Playlist(name: "Alt Xtream", sourceURL: URL(string: "http://h.example:8080/player_api.php?username=qa-user&password=\(pass)")!,
                             isXtream: true, xtreamOutput: "ts")
            ctx.insert(x)
            var xc: [Channel] = []
            for i in 0..<1_000 {
                let ch = Channel(name: "X\(i)", streamURL: URL(string: "http://h.example:8080/live/qa-user/\(pass)/\(i).ts")!, playlistID: x.id)
                ctx.insert(ch)
                xc.append(ch)
            }
            x.channels.append(contentsOf: xc)
            x.channelCount = xc.count
            try ctx.save()
        }
        try await Task.sleep(nanoseconds: 500_000_000)
        let (container, outcome) = AppPersistence.openStore(at: storeURL, schema: AppSchema.schema)
        XCTAssertEqual(outcome, .opened)

        let maintenance = LaunchMaintenance()
        // Fenster wie die App: Inhalt mit Abdeckung während der Umstellung
        let window = B03UI.window(Text("QA Inhalt R-10").launchMaintenanceCover(maintenance), size: CGSize(width: 520, height: 360))
        defer { window.close() }
        let wd = B03QAWatchdog(); wd.start()
        let t0 = Date()
        maintenance.start(container: container, storeURL: storeURL, store: PlaylistStore(), credentials: .standard, defaults: nil, cache: nil)
        let runningRightAfterStart = maintenance.isRunning
        let startReturned = Date().timeIntervalSince(t0)
        var ticks = 0
        var hintWhileRunning: [String] = []
        while maintenance.isRunning, Date().timeIntervalSince(t0) < 120 {
            try await Task.sleep(nanoseconds: 20_000_000)
            ticks += 1
            if hintWhileRunning.isEmpty, Date().timeIntervalSince(t0) > 1.0, maintenance.isRunning {
                hintWhileRunning = B03UI.labels(window).filter { $0.contains("aktualisiert") || $0.contains("QA Inhalt") }
            }
        }
        let duration = Date().timeIntervalSince(t0)
        try await Task.sleep(nanoseconds: 200_000_000)
        let gap = wd.stop()
        let labelsAfter = B03UI.labels(window).filter { $0.contains("aktualisiert") || $0.contains("QA Inhalt") }
        let result = maintenance.result
        let bytes = B02.bytes(pass, storeURL)
        let keychain = B01QA2.keychainCount(service: XtreamCredentialStore.standard.service)
        let favorites = try container.mainContext.fetchCount(FetchDescriptor<Channel>(predicate: #Predicate { $0.isFavorite == true }))
        B02.log("NB|R-10|sender=\(lists * 3_000 + 1_000)|startKehrtZurueckNach=\(B02.f2(startReturned))s|laeuftDanach=\(runningRightAfterStart)|dauer=\(B02.f2(duration))s|mainThreadBlockade=\(B02.f2(gap))s|mainActorSchritte=\(ticks)|fensterWaehrendDerUmstellung=\(hintWhileRunning)|fensterDanach=\(labelsAfter)|ergebnis=\(result.map { "\($0)" } ?? "nil")|klartext=\(bytes)|schluesselbund=\(keychain)|favoriten=\(favorites)|build=\(B02.buildConfiguration)")
        XCTAssertTrue(hintWhileRunning.contains { $0.contains("Gespeicherte Playlists werden aktualisiert") }, "Hinweis während der Umstellung: \(hintWhileRunning)")
        XCTAssertFalse(hintWhileRunning.contains { $0.contains("QA Inhalt R-10") }, "Inhalt während der Umstellung verdeckt: \(hintWhileRunning)")
        XCTAssertFalse(labelsAfter.contains { $0.contains("aktualisiert") }, "Hinweis danach weg: \(labelsAfter)")
        XCTAssertTrue(labelsAfter.contains { $0.contains("QA Inhalt R-10") }, "Inhalt danach sichtbar: \(labelsAfter)")
        XCTAssertTrue(runningRightAfterStart)
        XCTAssertLessThan(startReturned, 0.1, "Start kehrt sofort zurück")
        XCTAssertFalse(maintenance.isRunning, "Umstellung fertig")
        XCTAssertLessThanOrEqual(gap, 0.5, "Main-Thread blockiert \(B02.f2(gap)) s")
        XCTAssertEqual(result, AppPersistence.CredentialMigrationResult(migratedPlaylists: lists + 1, rewrittenChannels: lists * 3_000 + 1_000, failedPlaylists: 0))
        XCTAssertEqual(bytes.values.reduce(0, +), 0, "\(bytes)")
        XCTAssertEqual(keychain, lists + 1)
        XCTAssertEqual(favorites, lists)
    }

    /// Schreibt `marker` über eine eigene Verbindung (ohne `secure_delete`) in eine Hilfstabelle und löscht sie wieder:
    /// Die Seiten landen mit Inhalt in der Freiliste, wie Reste einer abgebrochenen Umstellung.
    static func leaveFreePages(containing marker: String, in storeURL: URL) {
        var db: OpaquePointer?
        guard sqlite3_open_v2(storeURL.path, &db, SQLITE_OPEN_READWRITE, nil) == SQLITE_OK else { sqlite3_close(db); return }
        defer { sqlite3_close(db) }
        sqlite3_busy_timeout(db, 2_000)
        let payload = String(repeating: "http://h.example/live/qa-user/\(marker)/1.ts ", count: 60).replacingOccurrences(of: "'", with: "")
        sqlite3_exec(db, "PRAGMA secure_delete=OFF;", nil, nil, nil)
        sqlite3_exec(db, "CREATE TABLE nb_rest(x);", nil, nil, nil)
        for _ in 0..<40 { sqlite3_exec(db, "INSERT INTO nb_rest VALUES('\(payload)');", nil, nil, nil) }
        sqlite3_exec(db, "DROP TABLE nb_rest;", nil, nil, nil)
        sqlite3_exec(db, "PRAGMA wal_checkpoint(TRUNCATE);", nil, nil, nil)
    }
}

/// `UserDefaults` nur im Arbeitsspeicher: alle Zugriffe, die die Umstellung benutzt, gehen in ein Wörterbuch.
final class NBMemoryDefaults: UserDefaults {
    private var values: [String: Any] = [:]
    override init?(suiteName suitename: String?) { super.init(suiteName: suitename) }
    override func object(forKey defaultName: String) -> Any? { values[defaultName] }
    override func set(_ value: Any?, forKey defaultName: String) { values[defaultName] = value }
    override func set(_ value: Bool, forKey defaultName: String) { values[defaultName] = value }
    override func bool(forKey defaultName: String) -> Bool { (values[defaultName] as? Bool) ?? false }
    override func removeObject(forKey defaultName: String) { values[defaultName] = nil }
}
