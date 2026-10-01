import XCTest
import SwiftData
import OSLog
@testable import MikaPlusPlayer

/// B02 · M3U-Import — Datenschutz, Missbrauchsschutz und Angriffe (AK-34, AK-35, AK-37, AK-39, AK-41, AK-42;
/// Angriffsdurchlauf 1, 3, 5, 7, 8). Nur Temp-Datenbanken, umgelenkter Plattencache, Loopback-Server, erfundene Daten.
final class B02SicherheitTests: B02TestCase {

    /// Liste, wie `get.php` sie ausgibt: Zugangsdaten in drei üblichen Formen der Stream-Adresse.
    static func getPhpListe(user: String, pass: String) -> Data {
        Data("""
        #EXTM3U
        #EXTINF:-1 tvg-id="eins" group-title="QA",Eins
        \(B02.dead)/live/\(user)/\(pass)/101.ts
        #EXTINF:-1,Zwei
        \(B02.dead)/\(user)/\(pass)/102
        #EXTINF:-1,Drei
        \(B02.dead)/live/103.m3u8?token=\(pass)

        """.utf8)
    }

    // MARK: AK-34 · BUG-01

    /// AK-34 ⚠ / BUG-01: `get.php?username=…&password=…` → Passwort im Klartext in `sourceURL` und jeder Stream-Adresse;
    /// kein Schlüsselbund-Eintrag; Umstellung beim Start lässt alles stehen; Resolver reicht Adressen mit Passwort durch;
    /// Datenbank nicht vom Backup ausgeschlossen.
    @MainActor func testAK34_ZugangsdatenAusM3ULinkImSchluesselbund() async throws {
        let pass = "qa-pass-b02ak34-\(UInt32.random(in: 1000...9999))"
        server.handler = { _ in B02Server.ok(B02SicherheitTests.getPhpListe(user: "qa-user", pass: pass), type: "application/octet-stream") }
        let dir = try tempDir("ak34")
        let (container, storeURL) = try B02.fileContainer(in: dir)
        let ctx = container.mainContext
        let input = server.url("/get.php?username=qa-user&password=\(pass)&type=m3u_plus&output=ts")
        let p = try await B02.importURL(input, ctx).get()
        try await Task.sleep(nanoseconds: 500_000_000)

        let path = storeURL.path
        let sourceRows = B02.int(path, "select count(*) from ZPLAYLIST where instr(ZSOURCEURL, '\(pass)') > 0")
        let streamRows = B02.int(path, "select count(*) from ZCHANNEL where instr(ZSTREAMURL, '\(pass)') > 0")
        let allStreams = B02.int(path, "select count(*) from ZCHANNEL")
        let raw = B02.bytes(pass, storeURL)
        let keychain = B01QA2.keychainCount(service: XtreamCredentialStore.standard.service)
        let migration = AppPersistence.migrateCredentials(container: container, storeURL: storeURL, store: .standard)
        let sourceAfter = B02.int(path, "select count(*) from ZPLAYLIST where instr(ZSOURCEURL, '\(pass)') > 0")
        let playable = try p.channels.map { try StreamURLResolver.playableURL(for: $0) }
        let playableWithPass = playable.filter { $0.absoluteString.contains(pass) }.count
        let excluded = try storeURL.resourceValues(forKeys: [.isExcludedFromBackupKey]).isExcludedFromBackup
        B02.evidence("AK-34-35-42-sqlite.txt", "AK-34|sqlite|ZPLAYLIST.ZSOURCEURL mit Passwort=\(sourceRows)|ZCHANNEL.ZSTREAMURL mit Passwort=\(streamRows)/\(allStreams)|rohBytes=\(raw)|schluesselbund(Testdienst)=\(keychain)|umstellung=\(migration)|sourceURLDanach=\(sourceAfter)|abspielbarMitPasswort=\(playableWithPass)/\(playable.count)|isExcludedFromBackup=\(excluded.map(String.init) ?? "nil")")

        // BUG-01 behoben: kein Passwort in Datenbank und Dateien, Zugangsdaten im Schlüsselbund, abspielbar über den
        // Resolver; die Umstellung beim Start hat nichts mehr zu tun. Die Datenbank bleibt bewusst im Backup
        // (Begründung in `AppPersistence` trifft jetzt auch für M3U zu).
        XCTAssertEqual(sourceRows, 0)
        XCTAssertEqual(streamRows, 0)
        XCTAssertEqual(allStreams, 3)
        XCTAssertEqual(raw.values.reduce(0, +), 0, "\(raw)")
        XCTAssertEqual(keychain, 1)
        XCTAssertEqual(try XtreamCredentialStore.standard.loadM3U(for: p.id)?.password, pass)
        XCTAssertEqual(migration, AppPersistence.CredentialMigrationResult())
        XCTAssertEqual(sourceAfter, 0)
        XCTAssertEqual(playableWithPass, 3)
        XCTAssertEqual(Set(playable.map(\.absoluteString)), [
            "\(B02.dead)/live/qa-user/\(pass)/101.ts", "\(B02.dead)/qa-user/\(pass)/102", "\(B02.dead)/live/103.m3u8?token=\(pass)"
        ], "abspielbare Adressen unverändert wie in der Liste")
        XCTAssertEqual(excluded, false)
        XCTAssertFalse(p.sourceURL?.absoluteString.contains("qa-user") ?? true, "auch der Benutzername nicht in der Adresse")
    }

    /// AK-34 (b): Benutzerinfo-Variante `http://user:pass@…` → ebenfalls Klartext in `sourceURL`.
    @MainActor func testAK34_BenutzerinfoImSchluesselbund() async throws {
        let pass = "qa-pass-b02ak34u-\(UInt32.random(in: 1000...9999))"
        let dir = try tempDir("ak34u")
        let (container, storeURL) = try B02.fileContainer(in: dir)
        _ = try await B02.importURL("http://qa-user:\(pass)@\(server.hostPort)/liste.m3u", container.mainContext).get()
        let rows = B02.int(storeURL.path, "select count(*) from ZPLAYLIST where instr(ZSOURCEURL, '\(pass)') > 0")
        let raw = B02.bytes(pass, storeURL).values.reduce(0, +)
        B02.evidence("AK-34-35-42-sqlite.txt", "AK-34|benutzerinfo|ZPLAYLIST.ZSOURCEURL mit Passwort=\(rows)|rohBytes=\(raw)")
        XCTAssertEqual(rows, 0)
        XCTAssertEqual(raw, 0)
        let p = try XCTUnwrap(try container.mainContext.fetch(FetchDescriptor<Playlist>()).first)
        let secret = try XCTUnwrap(try XtreamCredentialStore.standard.loadM3U(for: p.id))
        XCTAssertEqual(secret.username, "qa-user")
        XCTAssertEqual(secret.password, pass)
        XCTAssertEqual(secret.sourceURL, "http://qa-user:\(pass)@\(server.hostPort)/liste.m3u", "Abruf beim Aktualisieren wie eingegeben")
    }

    // MARK: AK-35 · BUG-02

    /// AK-35 ⚠ / BUG-02: Anfrage-Adresse samt Zugangsdaten und Antwortkörper landen im HTTP-Plattencache (hier: auf einen
    /// Temp-Ordner umgelenkter `URLCache.shared`, dieselbe Instanzart wie in der App) und überstehen das Löschen der
    /// Playlist; `Cache-Control: no-store` verhindert den Eintrag; das einmalige Leeren aus B01 greift nur einmal.
    @MainActor func testAK35_KeinPlattencacheFuerM3UAbrufe() async throws {
        let pass = "qa-pass-b02ak35-\(UInt32.random(in: 1000...9999))"
        let passNoStore = pass + "-nostore"
        server.handler = { req in
            if req.path == "/no-store.php" {
                return B02Server.ok(B02SicherheitTests.getPhpListe(user: "qa-user", pass: passNoStore), headers: [("Cache-Control", "no-store")])
            }
            return B02Server.ok(B02SicherheitTests.getPhpListe(user: "qa-user", pass: pass))
        }
        let c = try B02.memory()
        let url = server.url("/get.php?username=qa-user&password=\(pass)")
        let p = try await B02.importURL(url, c.mainContext).get()
        try await Task.sleep(nanoseconds: 2_000_000_000)
        let apiAfterImport = cachedCount([url])
        let body = probeCache.cachedResponse(for: URLRequest(url: URL(string: url)!)).map { String(decoding: $0.data, as: UTF8.self) } ?? ""
        let diskAfterImport = B01QA2.occurrences(of: [pass], under: cacheDir)
        let files = diskAfterImport.filter { $0.value > 0 }.keys.sorted()

        try await PlaylistImporter(modelContext: c.mainContext).delete(p)
        try await Task.sleep(nanoseconds: 1_000_000_000)
        let apiAfterDelete = cachedCount([url])
        let diskAfterDelete = B01QA2.occurrences(of: [pass], under: cacheDir).values.reduce(0, +)

        let urlNoStore = server.url("/no-store.php?username=qa-user&password=\(passNoStore)")
        _ = try await B02.importURL(urlNoStore, c.mainContext).get()
        try await Task.sleep(nanoseconds: 2_000_000_000)
        let apiNoStore = cachedCount([urlNoStore])
        let diskNoStore = B01QA2.occurrences(of: [passNoStore], under: cacheDir).values.reduce(0, +)

        // Einmaliges Leeren (B01 · BUG-03): erster Aufruf leert, ein späterer Import schreibt wieder, zweiter Aufruf tut nichts.
        let suite = "lu.daumedia.MikaPlusPlayerTests.b02.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer {
            defaults.removePersistentDomain(forName: suite)
            // cfprefsd lässt die leere Datei sonst liegen
            try? FileManager.default.removeItem(at: FileManager.default.urls(for: .libraryDirectory, in: .userDomainMask)[0]
                .appendingPathComponent("Preferences/\(suite).plist"))
        }
        let firstPurge = AppPersistence.purgeLegacyHTTPCacheOnce(defaults: defaults, cache: probeCache)
        try await Task.sleep(nanoseconds: 1_000_000_000)
        let afterFirstPurge = cachedCount([url])
        _ = try await B02.importURL(url, c.mainContext).get()
        try await Task.sleep(nanoseconds: 2_000_000_000)
        let secondPurge = AppPersistence.purgeLegacyHTTPCacheOnce(defaults: defaults, cache: probeCache)
        let afterSecondPurge = cachedCount([url])

        B02.evidence("AK-34-35-42-sqlite.txt", "AK-35|cache|nachImport api=\(apiAfterImport) bytes=\(diskAfterImport.values.reduce(0, +)) dateien=\(files) antwortkoerperMitPasswort=\(body.contains(pass))|nachLoeschen api=\(apiAfterDelete) bytes=\(diskAfterDelete)|no-store api=\(apiNoStore) bytes=\(diskNoStore)|leeren1=\(firstPurge)->api \(afterFirstPurge)|neuerImport+leeren2=\(secondPurge)->api \(afterSecondPurge)")
        // BUG-02 behoben: Der Abruf läuft über den Loader ohne Plattencache – nichts landet dort, auch nicht beim
        // erneuten Import nach dem einmaligen Leeren.
        XCTAssertEqual(apiAfterImport, 0)
        XCTAssertFalse(body.contains(pass), "kein Antwortkörper mit Passwort im Cache")
        XCTAssertEqual(diskAfterImport.values.reduce(0, +), 0)
        XCTAssertEqual(apiAfterDelete + diskAfterDelete, 0)
        XCTAssertEqual(apiNoStore + diskNoStore, 0)
        XCTAssertTrue(firstPurge)
        XCTAssertEqual(afterFirstPurge, 0)
        XCTAssertFalse(secondPurge)
        XCTAssertEqual(afterSecondPurge, 0)
    }

    // MARK: AK-37 · BUG-03

    /// AK-37 ⚠ / BUG-03: 52 MB mit 1.000 Einträgen und 52.000 Zeichen langen Namen — per URL und per Datei vollständig
    /// importiert; Speicherzuwachs; Namen ungekürzt gespeichert.
    @MainActor func testAK37_GrosseAntwortUndDateiMitGrenze() async throws {
        let longName = String(repeating: "N", count: 52_000)
        var s = "#EXTM3U\n"
        for i in 0..<1_000 { s += "#EXTINF:-1 group-title=\"G\",\(i)-\(longName)\n\(B02.dead)/live/\(i).ts\n" }
        let data = Data(s.utf8)
        server.handler = { _ in B02Server.ok(data) }
        let dir = try tempDir("ak37")
        let file = dir.appendingPathComponent("gross.m3u")
        try data.write(to: file)

        for weg in ["URL", "Datei"] {
            let c = try B02.memory()
            let before = B02.footprintMB()
            let watchdog = MainThreadWatchdog(); watchdog.start()
            let t = Date()
            let r = weg == "URL" ? await B02.importURL(server.url("/gross.m3u"), c.mainContext) : await B02.importFile(file, c.mainContext)
            let elapsed = Date().timeIntervalSince(t)
            try await Task.sleep(nanoseconds: 200_000_000)
            let gap = watchdog.stop()
            let after = B02.footprintMB()
            let p = try r.get()
            let maxName = p.channels.map { $0.name.count }.max() ?? 0
            B02.evidence("AK-37-EC-13-grenzen.txt", "AK-37|\(weg)|bytes=\(data.count)|ergebnis=\(B02.message(r) ?? "OK")|sender=\(p.channelCount)|laengsterName=\(maxName)|gesamt=\(B02.f2(elapsed))s|maxMainThreadBlockade=\(B02.f2(gap))s|speicherVorher=\(Int(before))MB|nachher=\(Int(after))MB|build=\(B02.buildConfiguration)")
            XCTAssertEqual(p.channelCount, 1_000)
            // BUG-03 behoben: Namen gekürzt (512 Zeichen); Größen- und Mengengrenze prüft `B02ReparaturTests`.
            XCTAssertLessThan(maxName, 1_000)
            XCTAssertEqual(maxName, 512)
        }
    }

    // MARK: AK-39 · BUG-05

    /// AK-39 ⚠ / BUG-05: beliebige Schemata als Stream- und Logo-Adresse landen ungeprüft in der Datenbank.
    @MainActor func testAK39_NurErlaubteSchemataWerdenGespeichert() async throws {
        let streams = ["file:///etc/hosts", "file:///Users/qa/Movies/privat.mp4", "javascript:alert(1)", "data:video/mp2t;base64,R0lGODlh",
                       "smb://nas.local/share/a.ts", "udp://@239.0.0.1:1234", "rtp://239.0.0.1:5000", "rtsp://127.0.0.1:554/cam",
                       "rtmp://127.0.0.1/live/x", "ftp://127.0.0.1/a.ts", "mailto:qa@example.invalid", "vlc://quit",
                       "x-apple.systempreferences:com.apple.preference.security"]
        let logos = ["file:///etc/hosts", "javascript:alert(1)", "smb://nas.local/logo.png", "logos/relativ.png"]
        var s = "#EXTM3U\n"
        for (i, u) in streams.enumerated() { s += "#EXTINF:-1,S\(i)\n\(u)\n" }
        for (i, l) in logos.enumerated() { s += "#EXTINF:-1 tvg-logo=\"\(l)\",L\(i)\n\(B02.dead)/live/l\(i).ts\n" }
        s += "#EXTINF:-1,OhneSchema\nnas.local/share/a.ts\n"
        let body = Data(s.utf8)
        server.handler = { _ in B02Server.ok(body) }
        let dir = try tempDir("ak39")
        let (container, storeURL) = try B02.fileContainer(in: dir)
        let p = try await B02.importURL(server.url("/schemata.m3u"), container.mainContext).get()
        let storedStreams = Set(p.channels.map(\.streamURL.absoluteString))
        let storedLogos = Set(p.channels.compactMap(\.logoURL?.absoluteString))
        let schemes = B02.rows(storeURL.path, "select distinct substr(ZSTREAMURL, 1, instr(ZSTREAMURL, ':')) from ZCHANNEL order by 1").map { $0[0] }
        B02.evidence("AK-39-schemata.txt", "AK-39|sender=\(p.channelCount)|streamSchemataInDB=\(schemes)|logos=\(storedLogos.sorted())|ohneSchemaGespeichert=\(storedStreams.contains("nas.local/share/a.ts"))")
        // BUG-05 behoben: nur Wiedergabe-Schemata für Streams, nur HTTP(S) für Logos.
        let allowed = ["udp://@239.0.0.1:1234", "rtp://239.0.0.1:5000", "rtsp://127.0.0.1:554/cam", "rtmp://127.0.0.1/live/x"]
        XCTAssertEqual(p.channelCount, allowed.count + logos.count)
        for u in streams { XCTAssertEqual(storedStreams.contains(u), allowed.contains(u), u) }
        XCTAssertEqual(storedLogos, [], "kein Logo mit file:, javascript:, smb: oder ohne Schema")
        XCTAssertEqual(schemes, ["http:", "rtmp:", "rtp:", "rtsp:", "udp:"])
        XCTAssertFalse(storedStreams.contains("nas.local/share/a.ts"))
        XCTAssertFalse(storedStreams.contains("file:///etc/hosts"))
        XCTAssertFalse(storedLogos.contains("file:///etc/hosts"))
    }

    // MARK: AK-41 (Test-Host)

    /// AK-41 (Test-Host-Anteil): Die App protokolliert selbst nichts; CFNetwork schreibt fehlgeschlagene Adressen ins
    /// Protokoll — im Test-Host unter `xcodebuild` im Klartext, wenn Private-Data-Logging aktiv ist. Der regulär gestartete
    /// Vergleich läuft außerhalb des Tests (Sonde `b02logprobe`, siehe qa-report.md).
    @MainActor func testAK41_ProtokollImTestHost() async throws {
        let marker = "qa-pass-b02ak41-\(UInt32.random(in: 1000...9999))"
        let start = Date().addingTimeInterval(-1)
        let c = try B02.memory()
        let closed = B02Server(); try closed.start(); let closedPort = closed.port; closed.stop()
        server.handler = { req in req.path == "/schleife" ? B02Server.redirect(302, to: "/schleife") : B02Server.status(404) }
        _ = await B02.importURL("http://127.0.0.1:\(closedPort)/get.php?username=qa-user&password=\(marker)", c.mainContext)
        _ = await B02.importURL(server.url("/schleife?password=\(marker)"), c.mainContext)
        _ = await B02.importURL(server.url("/404?password=\(marker)"), c.mainContext)
        try await Task.sleep(nanoseconds: 1_000_000_000)
        let privMarker = "b02qa-private-probe-\(UInt32.random(in: 1000...9999))"
        Logger(subsystem: "lu.daumedia.MikaPlusPlayerTests", category: "B02QA").log("Sonde \(privMarker, privacy: .private)")
        try await Task.sleep(nanoseconds: 300_000_000)
        let store = try OSLogStore(scope: .currentProcessIdentifier)
        var total = 0, hits = 0, privateVisible = false, appSubsystem = 0
        var subsystems: [String: Int] = [:]
        var older = 0
        var olderApp: [String] = []
        for case let e in try store.getEntries(at: store.position(date: start)) {
            // `position(date:)` liefert im Gesamtlauf auch ältere Einträge des Prozesses (z. B. Wiederherstellungs-
            // Meldungen aus B09-Tests); gezählt wird nur das Zeitfenster dieses Tests.
            guard let log = e as? OSLogEntryLog else { continue }
            guard log.date >= start else {
                // Review R-07: belegen, was das Zeitfenster ausschließt.
                older += 1
                if log.subsystem.hasPrefix("lu.daumedia.MikaPlusPlayer") && log.subsystem != "lu.daumedia.MikaPlusPlayerTests" {
                    olderApp.append("\(ISO8601DateFormatter().string(from: log.date))|\(log.subsystem)|\(log.category)|\(log.composedMessage.prefix(120))")
                }
                continue
            }
            total += 1
            if log.composedMessage.contains(privMarker) { privateVisible = true }
            if log.subsystem.hasPrefix("lu.daumedia.MikaPlusPlayer") && log.subsystem != "lu.daumedia.MikaPlusPlayerTests" { appSubsystem += 1 }
            if log.composedMessage.contains(marker) {
                hits += 1
                subsystems[log.subsystem, default: 0] += 1
            }
        }
        B02.evidence("AK-41-protokoll.txt", "AK-41|testHost(xcodebuild)|eintraege=\(total)|trefferMitPasswort=\(hits)|subsysteme=\(subsystems)|privateDatenSichtbar=\(privateVisible)|eintraegeDerApp=\(appSubsystem)")
        B02.log("AK-41|R-07|vorStart=\(older)|davonDerApp=\(olderApp.count)|ohneZeitfenster eintraegeDerApp=\(appSubsystem + olderApp.count)")
        for line in olderApp.prefix(12) { B02.log("AK-41|R-07|ausgeschlossen|\(line)") }
        XCTAssertGreaterThan(total, 0)
        XCTAssertEqual(appSubsystem, 0, "die App selbst protokolliert beim M3U-Import nichts")
        XCTAssertTrue(subsystems.keys.allSatisfy { $0 == "com.apple.CFNetwork" }, "\(subsystems)")
    }

    // MARK: AK-42

    /// AK-42 / Angriff 8: Löschen über `PlaylistImporter.delete` (zentraler Weg von B03). Seit B02 · BUG-01/-02 steht das
    /// Passwort nie in der Datenbank; nach dem Löschen bleiben weder Cache-Eintrag noch Cookie noch Schlüsselbund-Eintrag.
    @MainActor func testAK42_LoeschenLaesstKeineZugangsdatenZurueck() async throws {
        let pass = "qa-pass-b02ak42-\(UInt32.random(in: 1000...9999))"
        server.handler = { _ in B02Server.ok(B02SicherheitTests.getPhpListe(user: "qa-user", pass: pass), headers: [("Set-Cookie", "b02qaDel=\(pass); Path=/")]) }
        let dir = try tempDir("ak42")
        let url = server.url("/get.php?username=qa-user&password=\(pass)")
        let storeURL: URL
        var beforeDelete: [String: Int] = [:]
        var openAfterDelete: [String: Int] = [:]
        var rowsAfterDelete = -1
        var cookieBeforeDelete = -1
        var secretAfterDelete: M3USecret?
        do {
            let (container, u) = try B02.fileContainer(in: dir)
            storeURL = u
            let ctx = container.mainContext
            let p = try await B02.importURL(url, ctx).get()
            try await Task.sleep(nanoseconds: 300_000_000)
            beforeDelete = B02.bytes(pass, storeURL)
            cookieBeforeDelete = PlaylistHTTPLoader.shared.cookies.filter { $0.name == "b02qaDel" }.count
            try await PlaylistImporter(modelContext: ctx).delete(p)
            try await Task.sleep(nanoseconds: 500_000_000)
            openAfterDelete = B02.bytes(pass, storeURL)
            rowsAfterDelete = B02.int(storeURL.path, "select (select count(*) from ZPLAYLIST) + (select count(*) from ZCHANNEL)")
            secretAfterDelete = try XtreamCredentialStore.standard.loadM3U(for: p.id)
            B02.evidence("AK-34-35-42-sqlite.txt", "AK-42|vorLoeschen=\(beforeDelete)|cookieImLoader=\(cookieBeforeDelete)|nachLoeschenOffen zeilen=\(rowsAfterDelete) bytes=\(openAfterDelete)|schluesselbund=\(secretAfterDelete != nil)")
        }
        try await Task.sleep(nanoseconds: 1_500_000_000)
        let closed = B02.bytes(pass, storeURL)
        let cacheLeft = cachedCount([url])
        let cookieShared = HTTPCookieStorage.shared.cookies?.filter { $0.name == "b02qaDel" }.count ?? 0
        let cookieLoader = PlaylistHTTPLoader.shared.cookies.filter { $0.name == "b02qaDel" }.count
        B02.evidence("AK-34-35-42-sqlite.txt", "AK-42|nachSchliessen bytes=\(closed)|cacheEintrag=\(cacheLeft)|cookieGemeinsam=\(cookieShared)|cookieLoader=\(cookieLoader)")
        XCTAssertEqual(beforeDelete.values.reduce(0, +), 0, "Passwort nie in der Datenbank (BUG-01)")
        XCTAssertEqual(rowsAfterDelete, 0)
        XCTAssertEqual(openAfterDelete.values.reduce(0, +), 0)
        XCTAssertEqual(closed.values.reduce(0, +), 0, "nach dem Schließen in keiner Datei")
        XCTAssertNil(secretAfterDelete, "Schlüsselbund-Eintrag mit der Playlist gelöscht")
        XCTAssertEqual(cacheLeft, 0, "kein Cache-Eintrag (BUG-02)")
        XCTAssertEqual(cookieBeforeDelete, 1, "AK-36: Cookie für den nächsten Abruf im Arbeitsspeicher")
        XCTAssertEqual(cookieShared, 0, "kein Cookie im gemeinsamen Speicher")
        XCTAssertEqual(cookieLoader, 0, "Cookie des Hosts mit der Playlist entfernt")
    }

    // MARK: Angriff 1 · fremde Playlist beeinflussen (Ersatz für IDOR)

    /// Angriff 1 (Ersatz): Eine zweite, präparierte Liste mit denselben tvg-IDs, Namen und Adressen verändert eine
    /// vorhandene Playlist nicht (Sender, Favoriten, `playlistID`, `channelCount`).
    @MainActor func testAngriff01_FremdeListeVeraendertVorhandenePlaylistNicht() async throws {
        let c = try B02.memory()
        let a = try await B02.importURL(server.url("/a.m3u"), name: "A", c.mainContext).get()
        a.channels.forEach { $0.isFavorite = true }
        try c.mainContext.save()
        let aID = a.id
        let evil = Data("""
        #EXTM3U
        #EXTINF:-1 tvg-id="a" group-title="News",Kanal A
        \(B02.dead)/live/a.m3u8
        #EXTINF:-1 tvg-id="\(aID.uuidString)",\(aID.uuidString)
        http://evil.example/\(aID.uuidString).ts

        """.utf8)
        server.handler = { _ in B02Server.ok(evil) }
        let b = try await B02.importURL(server.url("/b.m3u"), name: "B", c.mainContext).get()
        let aChannels = try c.mainContext.fetch(FetchDescriptor<Channel>(predicate: #Predicate { $0.playlistID == aID }))
        B02.log("Angriff-01|A sender=\(aChannels.count) favoriten=\(aChannels.filter(\.isFavorite).count) channelCount=\(a.channelCount)|B sender=\(b.channelCount) favoriten=\(b.channels.filter(\.isFavorite).count) ids=\(Set(b.channels.compactMap(\.playlistID)) == [b.id])")
        XCTAssertEqual(aChannels.count, 2)
        XCTAssertEqual(aChannels.filter(\.isFavorite).count, 2)
        XCTAssertEqual(a.channelCount, 2)
        XCTAssertEqual(b.channels.filter(\.isFavorite).count, 0)
        XCTAssertEqual(Set(b.channels.compactMap(\.playlistID)), [b.id])
    }

    // MARK: Angriff 3 · Wiederholung ohne Grenze

    /// Angriff 3: Zehn Importe in Folge und ein Basic-Auth-Server, der immer 401 antwortet — keine Bremse, jede Anfrage
    /// erreicht den Server. (Für M3U gibt es keine Anmeldung der App; Katalog 4.1 „trifft nicht zu".)
    @MainActor func testAngriff03_WiederholteAbrufeOhneBremse() async throws {
        let c = try B02.memory()
        server.handler = { req in req.path == "/401" ? B02Server.status(401, headers: [("WWW-Authenticate", "Basic realm=\"qa\"")]) : B02Server.status(404) }
        let t = Date()
        var messages: [String] = []
        for i in 0..<10 {
            let r = await B02.importURL("http://qa-user:qa-pass-b02a3-\(i)@\(server.hostPort)/401", c.mainContext)
            messages.append(B02.message(r) ?? "OK")
        }
        let elapsed = Date().timeIntervalSince(t)
        let withAuth = server.requests.filter { $0.header("Authorization") != nil }.count
        let firstThree = server.requests.prefix(4).map { $0.header("Authorization") == nil ? "ohne" : "mit" }
        B02.log("Angriff-03|versuche=10|anfragen=\(server.requests.count)|davonMitAuthorization=\(withAuth)|folgeErsteAnfragen=\(firstThree)|dauer=\(B02.f2(elapsed))s|meldungen=\(Set(messages))")
        XCTAssertGreaterThanOrEqual(server.requests.count, 20, "jeder Versuch erreicht den Server")
        XCTAssertEqual(Set(messages), ["Netzwerkfehler: HTTP 401"])
    }

    // MARK: Angriff 5 · tatsächlicher Payload

    /// Angriff 5: Was geht beim Import raus? Logo- und Stream-Hosts aus der Liste werden beim Import **nicht** kontaktiert;
    /// der Listen-Server bekommt die vollständige Adresse samt Query (kein Fragment).
    @MainActor func testAngriff05_PayloadUndKeineKontakteZuListenHosts() async throws {
        let c = try B02.memory()
        let other = try extraServer { _ in B02Server.status(404) }
        let liste = Data("""
        #EXTM3U
        #EXTINF:-1 tvg-logo="http://127.0.0.1:\(other.port)/logo.png",Fremd
        http://127.0.0.1:\(other.port)/live/1.ts

        """.utf8)
        server.handler = { _ in B02Server.ok(liste) }
        let input = server.url("/get.php?username=qa-user&password=qa-pass-b02a5&type=m3u_plus#frag")
        _ = try await B02.importURL(input, c.mainContext).get()
        try await Task.sleep(nanoseconds: 1_000_000_000)
        let req = try XCTUnwrap(server.requests.first)
        B02.evidence("Angriff-05-payload.txt", "Angriff-05|anfrage=\(req.requestLine)|kopfzeilen=\(req.headers.map { "\($0.name): \($0.value)" })|verbindungenZuLogoUndStreamHost=\(other.connectionCount)")
        XCTAssertEqual(req.target, "/get.php?username=qa-user&password=qa-pass-b02a5&type=m3u_plus")
        XCTAssertEqual(other.connectionCount, 0)
    }

    // MARK: Angriff 7 · Eingaben

    /// Angriff 7: URL- und Namensfeld mit leer, 1 Zeichen, 10.000 Zeichen, Emoji, SQL, Script, Pfad; dazu dieselben Werte als
    /// Sendername in der Liste. Erwartet: saubere Meldung oder sichere Speicherung, kein Absturz.
    @MainActor func testAngriff07_Eingaben() async throws {
        let c = try B02.memory()
        let values = ["", "x", String(repeating: "a", count: 10_000), "📺😀 Ümläut", "'; drop table ZPLAYLIST; --",
                      "<script>alert(1)</script>", "../../etc/passwd", "%00%0d%0a", "\u{0}"]
        var lines: [String] = []
        for v in values {
            let r = await B02.importURL(v, c.mainContext)
            lines.append("url=\(v.prefix(30).debugDescription)(\(v.count))→\(B02.message(r) ?? "OK")")
        }
        for v in values {
            let r = await B02.importURL(server.url("/liste.m3u"), name: v, c.mainContext)
            let stored = (try? r.get())?.name
            lines.append("name=\(v.prefix(30).debugDescription)(\(v.count))→\(stored == v ? "exakt" : "ABWEICHEND \(stored?.prefix(30) ?? "nil")")")
            // Seit B02 · BUG-04 wird die Playlist im Hintergrund gespeichert und aus der Datenbank gelesen, nicht mehr das
            // ungespeicherte Objekt: Ein NUL-Zeichen schneidet die Datenbank ab (bekannter Befund B05 · BUG-09).
            XCTAssertEqual(stored, v.isEmpty ? "127.0.0.1" : (v == "\u{0}" ? "" : v))
        }
        var liste = "#EXTM3U\n"
        for (i, v) in values.enumerated() { liste += "#EXTINF:-1 group-title=\"\(v.replacingOccurrences(of: "\"", with: ""))\",\(v)\n\(B02.dead)/live/\(i).ts\n" }
        let listData = Data(liste.utf8)
        server.handler = { _ in B02Server.ok(listData) }
        let p = try await B02.importURL(server.url("/angriff.m3u"), c.mainContext).get()
        let names = Set(p.channels.map(\.name))
        lines.append("sendernamen=\(p.channelCount)|sqlUnveraendert=\(names.contains("'; drop table ZPLAYLIST; --"))|script=\(names.contains("<script>alert(1)</script>"))|playlistsGesamt=\(B02.count(Playlist.self, c.mainContext))")
        B02.evidence("Angriff-07-eingaben.txt", "Angriff-07|" + lines.joined(separator: "\nAngriff-07|"))
        XCTAssertTrue(names.contains("'; drop table ZPLAYLIST; --"))
        XCTAssertTrue(names.contains("<script>alert(1)</script>"))
        XCTAssertGreaterThan(B02.count(Playlist.self, c.mainContext), values.count)
    }
}
