import XCTest
import SwiftData
import AppKit
import CryptoKit
import OSLog
@testable import MikaPlusPlayer

/// B03 · Playlist-Verwaltung — Löschen, was danach wo bleibt, und die Angriffsprüfungen (QA Durchlauf 1, 2026-09-16).
/// Nur Test-Datenbanken im Temp-Verzeichnis, Schlüsselbund nur im Test-Dienst dieses Laufs, Mock auf 127.0.0.1.
final class B03LoeschenTests: B03QATestCase {

    // MARK: - AK-23 / AK-24 / Angriff 8

    /// AK-23: Playlist und alle Sender entfernt, keine verwaisten Zeilen, Favoriten weg; andere Playlists samt Favoriten
    /// unverändert. AK-24: Schlüsselbund-Eintrag der gelöschten Xtream-Playlist entfernt, der andere bleibt.
    /// Angriff 8: jede Tabelle der Datenbank nachgezählt, keine Netzanfrage beim Löschen.
    @MainActor func testAK23_AK24_Angriff8_LoeschenEntferntAllesDerPlaylist() async throws {
        let (container, url) = try fileContainer("ak23")
        let ctx = container.mainContext
        let m = try await importM3U(ctx, entries: (0..<20).map { ("QA-M-\($0)", nil, "G", "\(B03QA.dead)/m\($0).m3u8") }, name: "QA M")
        let x = try await importXtream(ctx, streams: B03QA.streams((0..<20).map { ("QA-X-\($0)", 500 + $0, "x\($0)", "1") }), pass: "qa-pass-b03-x", name: "QA X")
        let y = try await importXtream(ctx, streams: B03QA.streams((0..<20).map { ("QA-Y-\($0)", 900 + $0, "y\($0)", "1") }), pass: "qa-pass-b03-y", name: "QA Y")
        for ch in m.channels.prefix(3) { ch.isFavorite = true }
        for ch in x.channels.prefix(3) { ch.isFavorite = true }
        for ch in y.channels.prefix(2) { ch.isFavorite = true }
        try ctx.save()
        let yFavorites = favorites(y)
        let yIDs = Set(y.channels.map(\.id))
        let xid = x.id, yid = y.id
        let tables = B03QA.rows(url.path, "select name from sqlite_master where type = 'table' order by name").map { $0[0] }
        func perTable() -> String {
            tables.map { "\($0)=\(B03QA.int(url.path, "select count(*) from \"\($0)\""))" }.joined(separator: ",")
        }
        let before = perTable()
        XCTAssertNotNil(try XtreamCredentialStore.standard.load(for: xid))
        mock.resetLog()

        try PlaylistImporter(modelContext: ctx).delete(m)
        try PlaylistImporter(modelContext: ctx).delete(x)

        let after = perTable()
        let favTab = try ctx.fetch(FetchDescriptor<Channel>(predicate: #Predicate { $0.isFavorite == true })).map(\.name).sorted()
        B03QA.log("AK-23|tabellen vorher=\(before)|nachher=\(after)|\(B03QA.dbSummary(url))|favoritenTab=\(favTab)|anfragenBeimLoeschen=\(mock.requests.count)")
        // Persistente Historie (SwiftData): was steht nach dem Löschen über gelöschte Objekte darin?
        let changeCols = B03QA.rows(url.path, "PRAGMA table_info(ACHANGE)").map { $0.count > 1 ? $0[1] : "?" }
        let changeSample = B03QA.rows(url.path, "select * from ACHANGE order by Z_PK desc limit 3").map { $0.joined(separator: ",") }
        let txStrings = B03QA.rows(url.path, "select * from ATRANSACTIONSTRING").map { $0.joined(separator: ",") }
        let historyNames = B03QA.int(url.path, "select count(*) from ACHANGE where " + changeCols.map { "instr(cast(\"\($0)\" as text), 'QA-M-') > 0" }.joined(separator: " or "))
        B03QA.log("AK-23|historie|spalten=\(changeCols)|letzte=\(changeSample)|transaktionsTexte=\(txStrings)|zeilenMitSendernamen=\(historyNames)")
        XCTAssertEqual(historyNames, 0, "Historie enthält keine Namen gelöschter Sender")
        XCTAssertEqual(B03QA.int(url.path, "select count(*) from ZPLAYLIST"), 1)
        XCTAssertEqual(B03QA.int(url.path, "select count(*) from ZCHANNEL"), 20)
        XCTAssertEqual(B03QA.int(url.path, "select count(*) from ZCHANNEL where ZPLAYLIST is null"), 0)
        XCTAssertEqual(B03QA.int(url.path, "select count(*) from ZCHANNEL where ZNAME like 'QA-M-%' or ZNAME like 'QA-X-%'"), 0)
        XCTAssertEqual(favTab, yFavorites, "nur die Favoriten der verbliebenen Playlist")
        XCTAssertEqual(favorites(y), yFavorites)
        XCTAssertEqual(Set(y.channels.map(\.id)), yIDs)
        XCTAssertEqual(y.channelCount, 20)
        XCTAssertFalse(ctx.hasChanges)
        XCTAssertEqual(mock.requests.count, 0, "Löschen spricht keinen Dienst an")
        let xSecret = try XtreamCredentialStore.standard.load(for: xid)
        let ySecret = try XtreamCredentialStore.standard.load(for: yid)
        B03QA.log("AK-24|schluesselbund X=\(xSecret != nil)|Y=\(ySecret != nil)")
        XCTAssertNil(xSecret, "AK-24: Eintrag der gelöschten Playlist entfernt")
        XCTAssertEqual(ySecret?.password, "qa-pass-b03-y", "AK-24: Eintrag der anderen bleibt")
    }

    /// AK-25 / EC-12: Die Datei einer lokalen Playlist bleibt beim Löschen unberührt.
    @MainActor func testAK25_LokaleDateiBleibtUnberuehrt() async throws {
        let (container, url) = try fileContainer("ak25")
        let ctx = container.mainContext
        let file = url.deletingLastPathComponent().appendingPathComponent("qa-b03-ak25.m3u")
        try B03QA.m3u(B03QA.v1).write(to: file)
        let hash0 = SHA256.hash(data: try Data(contentsOf: file))
        let attrs0 = try FileManager.default.attributesOfItem(atPath: file.path)
        let p = try await PlaylistImporter(modelContext: ctx).importFromFile(file)
        try PlaylistImporter(modelContext: ctx).delete(p)
        let attrs1 = try FileManager.default.attributesOfItem(atPath: file.path)
        let hash1 = SHA256.hash(data: try Data(contentsOf: file))
        B03QA.log("AK-25|dateiDa=\(FileManager.default.fileExists(atPath: file.path))|hashGleich=\(hash0 == hash1)|mtimeGleich=\((attrs0[.modificationDate] as? Date) == (attrs1[.modificationDate] as? Date))|\(B03QA.dbSummary(url))")
        XCTAssertTrue(FileManager.default.fileExists(atPath: file.path))
        XCTAssertEqual(hash0, hash1)
        XCTAssertEqual(attrs0[.modificationDate] as? Date, attrs1[.modificationDate] as? Date)
        XCTAssertEqual(B03QA.int(url.path, "select count(*) from ZPLAYLIST"), 0)
    }

    // MARK: - AK-22 ⚠ · kein Rückgängig

    /// AK-22 (Datenschicht): Der Container, den die App baut, hat keinen `UndoManager`; nach dem Löschen gibt es
    /// keinen Weg zurück. Die Oberfläche (keine Rückfrage, ⌘Z) prüft `B03OberflaecheTests.testAK22_AK24_…`.
    @MainActor func testAK22_ContainerDerAppOhneUndoManager() async throws {
        let launch = AppPersistence.openAppStore()   // Test-Host: im Speicher
        let (container, url) = try fileContainer("ak22")
        let ctx = container.mainContext
        let p = try await importM3U(ctx)
        try PlaylistImporter(modelContext: ctx).delete(p)
        ctx.rollback()
        B03QA.log("AK-22|openAppStore=\(launch.outcome)|undoManager(openAppStore)=\(String(describing: launch.container.mainContext.undoManager))|undoManager(diskContainer)=\(String(describing: ctx.undoManager))|nachRollback=\(B03QA.dbSummary(url))")
        XCTAssertEqual(launch.outcome, .inMemoryForTests)
        XCTAssertNil(launch.container.mainContext.undoManager)
        XCTAssertNil(ctx.undoManager)
        XCTAssertEqual(B03QA.int(url.path, "select count(*) from ZPLAYLIST"), 0, "rollback bringt nichts zurück")
    }

    // MARK: - AK-33 ⚠ · Plattencache (BUG-06)

    @MainActor func testAK33_M3UAdresseUndAntwortBleibenNachLoeschenImPlattencache() async throws {
        let (container, _) = try fileContainer("ak33")
        let ctx = container.mainContext
        let tag = String(UInt32.random(in: 100_000...999_999))
        let token = "qa-b03-tok-\(tag)"
        let channelMarker = "qa-b03-ak33-sender-\(tag)"
        let address = "http://\(mock.hostPort)/list-\(tag).m3u?token=\(token)"
        let entries: [B03QA.M3UEntry] = (0..<5).map { ("\(channelMarker)-\($0)", nil, "G", "\(B03QA.dead)/\(channelMarker)-\($0).m3u8") }
        let p = try await importM3U(ctx, entries: entries, name: "QA Cache", address: address)
        try await refresh(p, ctx)
        let db = B01.hostCacheDB.path
        let keySQL = "select count(*) from cfurl_cache_response where instr(request_key, '\(token)') > 0"
        let bodySQL = "select count(*) from cfurl_cache_receiver_data where instr(cast(receiver_data as text), '\(channelMarker)') > 0"
        var keys = 0, bodies = 0
        for _ in 0..<50 {
            keys = B01.sqliteCount(db, keySQL) ?? 0
            bodies = B01.sqliteCount(db, bodySQL) ?? 0
            if keys > 0 && bodies > 0 { break }
            try await Task.sleep(nanoseconds: 100_000_000)
        }
        let fsBodies = fsCachedDataHits(channelMarker)
        B03QA.log("AK-33|vorLoeschen|cacheSchluesselMitToken=\(keys)|koerperMitSendernamen=\(bodies)|fsCachedData=\(fsBodies)|URLCache.shared=\(URLCache.shared.cachedResponse(for: URLRequest(url: URL(string: address)!)) != nil)")

        try PlaylistImporter(modelContext: ctx).delete(p)
        try await Task.sleep(nanoseconds: 2_000_000_000)
        let keysAfter = B01.sqliteCount(db, keySQL) ?? 0
        let bodiesAfter = (B01.sqliteCount(db, bodySQL) ?? 0) + fsCachedDataHits(channelMarker)
        let api = URLCache.shared.cachedResponse(for: URLRequest(url: URL(string: address)!)) != nil
        B03QA.log("AK-33|nachLoeschen|cacheSchluesselMitToken=\(keysAfter)|koerperMitSendernamen=\(bodiesAfter)|URLCache.shared=\(api)")
        XCTAssertGreaterThan(keys, 0, "Ausgangslage: Adresse samt Token im Plattencache")
        XCTAssertGreaterThan(bodies + fsBodies, 0, "Ausgangslage: Antwort mit Sendernamen im Plattencache")
        XCTExpectFailure("BUG-06 · M3U-Adresse samt Token und Senderliste überstehen das Löschen im HTTP-Plattencache (FB-06)") {
            XCTAssertEqual(keysAfter, 0)
            XCTAssertEqual(bodiesAfter, 0)
            XCTAssertFalse(api)
        }
        // Aufräumen der eigenen Testeinträge, Gegenprobe
        URLCache.shared.removeCachedResponse(for: URLRequest(url: URL(string: address)!))
        try await Task.sleep(nanoseconds: 1_500_000_000)
        XCTAssertEqual(B01.sqliteCount(db, keySQL) ?? 0, 0, "eigene Testeinträge entfernt")
    }

    private func fsCachedDataHits(_ marker: String) -> Int {
        let dir = B01.hostCacheDB.deletingLastPathComponent().appendingPathComponent("fsCachedData")
        let files = (try? FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil)) ?? []
        let needle = Data(marker.utf8)
        return files.filter { (try? Data(contentsOf: $0))?.range(of: needle) != nil }.count
    }

    // MARK: - AK-34 ⚠ · Bytes gelöschter Sender (BUG-07)

    @MainActor func testAK34_NamenUndAdressenGeloeschterSenderBleibenAlsBytes() async throws {
        let tag = String(UInt32.random(in: 100_000...999_999))
        let nameMarker = "qa-b03-ak34-name-\(tag)"
        let streamMarker = "qa-b03-ak34-stream-\(tag)"
        let xMarker = "qa-b03-ak34-xname-\(tag)"
        let token = "qa-b03-ak34-tok-\(tag)"
        var storeURL: URL!
        do {
            let (container, url) = try fileContainer("ak34")
            storeURL = url
            let ctx = container.mainContext
            let m = try await importM3U(ctx, entries: (0..<20).map { ("\(nameMarker)-\($0)", nil, "G", "\(B03QA.dead)/\(streamMarker)-\($0).m3u8") },
                                        name: "QA-B03-AK34-\(tag)", address: "http://\(mock.hostPort)/l.m3u?token=\(token)")
            let x = try await importXtream(ctx, streams: B03QA.streams((0..<20).map { ("\(xMarker)-\($0)", 700 + $0, nil, "1") }), name: "QA-X-\(tag)")
            try await Task.sleep(nanoseconds: 1_000_000_000)
            try PlaylistImporter(modelContext: ctx).delete(m)
            try PlaylistImporter(modelContext: ctx).delete(x)
            B03QA.log("AK-34|offen|name=\(B03QA.bytes(nameMarker, url))|stream=\(B03QA.bytes(streamMarker, url))|xname=\(B03QA.bytes(xMarker, url))|\(B03QA.dbSummary(url))")
            _ = container
        }
        try await Task.sleep(nanoseconds: 2_000_000_000)
        do {   // „Neustart“: neu öffnen und schließen
            let c2 = try AppPersistence.diskContainer(at: storeURL, schema: AppSchema.schema)
            XCTAssertEqual(try c2.mainContext.fetchCount(FetchDescriptor<Playlist>()), 0)
            XCTAssertEqual(try c2.mainContext.fetchCount(FetchDescriptor<Channel>()), 0)
        }
        try await Task.sleep(nanoseconds: 2_000_000_000)
        let names = B03QA.bytes(nameMarker, storeURL)
        let streams = B03QA.bytes(streamMarker, storeURL)
        let xnames = B03QA.bytes(xMarker, storeURL)
        let playlistName = B03QA.bytes("QA-B03-AK34-\(tag)", storeURL)
        let tokens = B03QA.bytes(token, storeURL)
        let freelist = B03QA.int(storeURL.path, "PRAGMA freelist_count")
        let secureDelete = B03QA.int(storeURL.path, "PRAGMA secure_delete")
        let files = (try? FileManager.default.contentsOfDirectory(atPath: storeURL.deletingLastPathComponent().path))?.sorted() ?? []
        B03QA.log("AK-34|nachNeustart|m3uSendernamen=\(names)|streamAdressen=\(streams)|xtreamSendernamen=\(xnames)|playlistName=\(playlistName)|token=\(tokens)|freieSeiten=\(freelist)|secure_delete(neue Verbindung)=\(secureDelete)|dateien=\(files)")
        let remaining = names + streams + xnames
        if remaining > 0 {
            XCTExpectFailure("BUG-07 · Namen und Stream-Adressen gelöschter Sender stehen noch als Bytes in der Datenbankdatei (FB-07)") {
                XCTAssertEqual(remaining, 0)
            }
        } else {
            B03QA.log("AK-34|in diesem Lauf keine Reste gefunden")
        }
    }

    // MARK: - AK-31 · Systemprotokoll

    /// AK-31 / Angriff 4: Aktualisieren (Erfolg und Fehler) und Löschen schreiben keine Nutzdaten ins Unified Log
    /// des App-Prozesses. Geprüft über `OSLogStore` auf Marken für Benutzer, Passwort, Token, Sender- und Playlistnamen.
    @MainActor func testAK31_Angriff4_KeineNutzdatenImSystemprotokoll() async throws {
        let start = Date().addingTimeInterval(-1)
        let tag = String(UInt32.random(in: 100_000...999_999))
        let user = "qa-user-ak31-\(tag)", pass = "qa-pass-ak31-\(tag)", token = "qa-tok-ak31-\(tag)"
        let chName = "QA-AK31-Sender-\(tag)", plName = "QA-AK31-Playlist-\(tag)"
        let (container, _) = try fileContainer("ak31")
        let ctx = container.mainContext
        let m = try await importM3U(ctx, entries: [(chName, nil, nil, "\(B03QA.dead)/\(chName).m3u8")], name: plName,
                                    address: "http://\(mock.hostPort)/list.m3u?token=\(token)")
        mock.handler = B03QAPanel().handler()
        let x = try await PlaylistImporter(modelContext: ctx, loginThrottle: XtreamLoginThrottle()).importFromXtream(
            XtreamCredentials(host: mock.hostPort, username: user, password: pass), output: .hls, name: plName + "-X")
        var cfg = B03QAPanel(); cfg.m3u = B03QA.m3u([(chName, nil, nil, "\(B03QA.dead)/\(chName).m3u8")])
        mock.handler = cfg.handler()
        try await refresh(m, ctx)
        try await refresh(x, ctx)
        var bad = B03QAPanel(); bad.m3uStatus = 500; bad.m3u = Data("x".utf8); bad.streamsStatus = 500
        mock.handler = bad.handler()
        _ = try? await refresh(m, ctx)
        _ = try? await refresh(x, ctx)
        // gleichzeitiges Aktualisieren und Löschen (SwiftData-Protokollzeilen)
        var slow = B03QAPanel(); slow.m3u = B03QA.m3u([(chName, nil, nil, "\(B03QA.dead)/\(chName).m3u8")]); slow.m3uDelay = 1
        mock.handler = slow.handler()
        let t = Task { @MainActor in try await PlaylistImporter(modelContext: ctx).refresh(m) }
        try await Task.sleep(nanoseconds: 300_000_000)
        try PlaylistImporter(modelContext: ctx).delete(m)
        _ = await t.result
        try PlaylistImporter(modelContext: ctx).delete(x)
        let privMarker = "b03qa-private-probe-\(tag)"
        Logger(subsystem: "lu.daumedia.MikaPlusPlayerTests", category: "B03QA").log("Sonde \(privMarker, privacy: .private)")
        try await Task.sleep(nanoseconds: 1_000_000_000)

        let store = try OSLogStore(scope: .currentProcessIdentifier)
        let entries = try store.getEntries(at: store.position(date: start))
        var total = 0, privateVisible = false, swiftDataLines = 0
        var hits: [String: Int] = [:]
        let markers = ["user": user, "pass": pass, "token": token, "sender": chName, "playlist": plName]
        for case let e as OSLogEntryLog in entries {
            total += 1
            let msg = e.composedMessage
            if msg.contains(privMarker) { privateVisible = true }
            if msg.contains("remapped to a temporary identifier") { swiftDataLines += 1 }
            for (k, v) in markers where msg.contains(v) {
                hits["\(k)@\(e.subsystem.isEmpty ? "-" : e.subsystem)", default: 0] += 1
            }
        }
        B03QA.log("AK-31|eintraege=\(total)|privateDatenSichtbar=\(privateVisible)|swiftDataRemapZeilen=\(swiftDataLines)|treffer=\(hits.sorted { $0.key < $1.key })")
        XCTAssertGreaterThan(total, 0, "OSLogStore liefert Einträge")
        let appHits = hits.filter { $0.key.hasSuffix("@lu.daumedia.MikaPlusPlayer") || $0.key.hasSuffix("@-") }.values.reduce(0, +)
        XCTAssertEqual(appHits, 0, "keine Nutzdaten aus der App selbst")
    }

    // MARK: - AK-36 ⚠ · Alles entfernen (BUG-09)

    /// AK-36: In der App gibt es keinen Weg, alle Daten zu entfernen; die Speicherorte liegen außerhalb des App-Bundles,
    /// das Löschen der App (Bundle entfernen) erreicht sie nicht. Das Löschen der App selbst wird nicht ausgeführt.
    @MainActor func testAK36_KeinWegAlleDatenZuEntfernen() throws {
        func titles(_ menu: NSMenu?, _ prefix: String = "") -> [String] {
            guard let menu else { return [] }
            return menu.items.flatMap { item -> [String] in
                let t = prefix + item.title
                return [t] + titles(item.submenu, t + " › ")
            }
        }
        let menu = titles(NSApp.mainMenu)
        let suspicious = menu.filter {
            let l = $0.lowercased()
            return l.contains("alle") || l.contains("zurücksetzen") || l.contains("daten") || l.contains("reset") || l.contains("aktualisieren")
                || (l.contains("löschen") && !l.hasSuffix("bearbeiten › löschen"))
        }
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        let bundleID = Bundle.main.bundleIdentifier ?? "-"
        let locations: [String: URL] = [
            "datenbank": AppPersistence.storeURL(applicationSupport: support, bundleID: bundleID),
            "beiseitegelegt(B09)": AppPersistence.storeURL(applicationSupport: support, bundleID: bundleID)
                .deletingLastPathComponent().appendingPathComponent(AppPersistence.setAsideFolderName),
            "httpCache": B01.hostCacheDB,
            "einstellungen": FileManager.default.urls(for: .libraryDirectory, in: .userDomainMask)[0]
                .appendingPathComponent("Preferences/\(bundleID).plist")
        ]
        let bundlePath = Bundle.main.bundleURL.standardizedFileURL.path
        let inside = locations.filter { $0.value.standardizedFileURL.path.hasPrefix(bundlePath) }
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        B03QA.log("AK-36|hauptmenue=\(menu.count) Einträge|verdächtig=\(suspicious)|bundle=\(bundlePath.replacingOccurrences(of: home, with: "~"))|orte=\(locations.mapValues { $0.path.replacingOccurrences(of: home, with: "~") }.sorted { $0.key < $1.key })|schluesselbundDienst=lu.daumedia.MikaPlusPlayer.xtream (Anmelde-Schlüsselbund)|imBundle=\(inside.keys.sorted())")
        XCTAssertGreaterThan(menu.count, 10, "Hauptmenü gelesen")
        XCTAssertEqual(inside.count, 0, "Ist: kein Speicherort liegt im App-Bundle")
        XCTAssertTrue(suspicious.filter { !$0.hasPrefix("MikaPlusPlayer › Nach Updates") }.isEmpty, "Ist: kein Menüeintrag zum Entfernen aller Daten: \(suspicious)")
        XCTExpectFailure("BUG-09 · Kein Weg, alle Daten zu entfernen; App löschen entfernt Datenbank, Cache, Einstellungen und Schlüsselbund nicht (FB-09)") {
            XCTAssertFalse(suspicious.isEmpty, "Menüeintrag „Alle Daten löschen“ fehlt")
        }
    }

    // MARK: - Angriff 1 · fremde/manipulierte IDs

    /// Angriff 1 (übertragen): Datenbank manipuliert. (a) Host in `sourceURL` einer Xtream-Playlist auf einen fremden
    /// Server umgeschrieben → Aktualisieren schickt die Zugangsdaten trotzdem nur an den Host aus dem Schlüsselbund.
    /// (b) Zweite Playlist mit derselben `id` → Löschen der einen entfernt den Schlüsselbund-Eintrag der anderen.
    @MainActor func testAngriff1_ManipulierteHostsUndDoppelteIDs() async throws {
        let (container, _) = try fileContainer("angriff1")
        let ctx = container.mainContext
        let pass = "qa-pass-b03-idor"
        let x = try await importXtream(ctx, pass: pass, name: "QA Echt")
        let attacker = MockXtreamServer(handler: B03QAPanel().handler())
        try attacker.start()
        defer { attacker.stop() }
        x.sourceURL = URL(string: "http://\(attacker.hostPort)/player_api.php")
        try ctx.save()
        mock.handler = B03QAPanel().handler()
        mock.resetLog()
        try await refresh(x, ctx)
        B03QA.log("Angriff1|a|anfragenFremderHost=\(attacker.requests.count)|anfragenEchterHost=\(mock.requests.count)|mitPasswortFremd=\(attacker.requests.filter { $0.password == pass }.count)")
        XCTAssertEqual(attacker.requests.count, 0, "Zugangsdaten gehen nicht an den umgeschriebenen Host")
        XCTAssertEqual(mock.requests.filter { $0.password == pass }.count, 3)

        let twin = Playlist(id: x.id, name: "QA Zwilling", sourceURL: URL(string: "http://\(attacker.hostPort)/player_api.php"),
                            isXtream: true, xtreamOutput: "hls")
        ctx.insert(twin)
        try ctx.save()
        try PlaylistImporter(modelContext: ctx).delete(twin)
        let left = try XtreamCredentialStore.standard.load(for: x.id)
        var msg = "ok"
        do { try await refresh(x, ctx) } catch { msg = error.localizedDescription }
        B03QA.log("Angriff1|b|schluesselbundDerEchtenNachLoeschenDesZwillings=\(left != nil)|aktualisierenDanach=\(msg)")
        XCTAssertNil(left, "Ist: Doppelte id (nur per Datenbank-Manipulation) – Löschen des Zwillings nimmt der echten Playlist die Zugangsdaten")
    }

    // MARK: - Angriff 5 · tatsächlicher Payload

    /// Angriff 5: Was geht beim Aktualisieren tatsächlich an den Anbieter (Request-Zeile und Kopfzeilen), und beim Löschen nichts.
    @MainActor func testAngriff5_TatsaechlicherPayloadBeimAktualisieren() async throws {
        let (container, _) = try fileContainer("angriff5")
        let ctx = container.mainContext
        let m = try await importM3U(ctx, address: "http://\(mock.hostPort)/list.m3u?token=qa-b03-tok-payload")
        let x = try await importXtream(ctx, pass: "qa-pass-b03-payload")
        var cfg = B03QAPanel(); cfg.m3u = B03QA.m3u(B03QA.v1)
        mock.handler = cfg.handler()
        mock.resetLog()
        try await refresh(m, ctx)
        try await refresh(x, ctx)
        for r in mock.requests {
            let headers = r.headers.sorted { $0.key < $1.key }.map { "\($0.key): \($0.key == "host" ? "<mock>" : $0.value)" }
            B03QA.log("Angriff5|\(r.requestLine)|\(headers)")
        }
        XCTAssertEqual(mock.requests.count, 4)
        XCTAssertEqual(Set(mock.requests.flatMap { $0.headers.keys }), ["accept", "accept-encoding", "accept-language", "connection", "host", "user-agent"])
        XCTAssertTrue(mock.requests.allSatisfy { $0.headers["authorization"] == nil && $0.headers["cookie"] == nil })
        mock.resetLog()
        try PlaylistImporter(modelContext: ctx).delete(m)
        try PlaylistImporter(modelContext: ctx).delete(x)
        try await Task.sleep(nanoseconds: 500_000_000)
        XCTAssertEqual(mock.requests.count, 0, "Löschen sendet nichts")
    }

    // MARK: - Angriff 7 · Eingaben

    /// Angriff 7: Playlist- und Sendernamen leer, 1 Zeichen, 10.000 Zeichen, Emoji, SQL, Script, Pfad – Import, Aktualisieren
    /// und Löschen verarbeiten sie sicher und unverändert; die Tabellen bleiben intakt.
    @MainActor func testAngriff7_EingabenInNamenUndSenderlisten() async throws {
        let (container, url) = try fileContainer("angriff7")
        let ctx = container.mainContext
        let inputs = ["", "x", String(repeating: "W", count: 10_000), "📺 Sender 🇱🇺 ünd ß", "'; drop table ZPLAYLIST; --",
                      "<script>alert(1)</script>", "../../etc/passwd", "Name,mit \"Quote\""]
        var created: [Playlist] = []
        for (i, input) in inputs.enumerated() {
            let entries: [B03QA.M3UEntry] = [(input.isEmpty ? "leer\(i)" : input, nil, input.isEmpty ? nil : input, "\(B03QA.dead)/\(i).m3u8"),
                                             ("Normal \(i)", nil, nil, "\(B03QA.dead)/n\(i).m3u8")]
            let p = try await importM3U(ctx, entries: entries, name: input)
            created.append(p)
            var cfg = B03QAPanel(); cfg.m3u = B03QA.m3u(entries + [("Neu \(i)", nil, nil, "\(B03QA.dead)/z\(i).m3u8")])
            mock.handler = cfg.handler()
            try await refresh(p, ctx)
        }
        let names = created.map(\.name)
        let tablesOK = B03QA.int(url.path, "select count(*) from sqlite_master where name = 'ZPLAYLIST'")
        let longStored = B03QA.int(url.path, "select max(length(ZNAME)) from ZPLAYLIST")
        B03QA.log("Angriff7|namen=\(names.map { $0.count > 40 ? "<\($0.count) Zeichen>" : $0 })|ZPLAYLIST=\(B03QA.int(url.path, "select count(*) from ZPLAYLIST"))|tabelleDa=\(tablesOK)|laengsterName=\(longStored)|sender=\(created.map(\.channelCount))")
        XCTAssertEqual(names.first, "127.0.0.1", "leerer Name → Host")
        XCTAssertEqual(Array(names.dropFirst()), Array(inputs.dropFirst()))
        XCTAssertEqual(created.map(\.channelCount), Array(repeating: 3, count: inputs.count))
        XCTAssertEqual(tablesOK, 1)
        XCTAssertEqual(longStored, 10_000)
        for p in created { try PlaylistImporter(modelContext: ctx).delete(p) }
        XCTAssertEqual(B03QA.dbSummary(url), "ZPLAYLIST=0|ZCHANNEL=0|ohnePlaylist=0|favoriten=0")
    }
}
