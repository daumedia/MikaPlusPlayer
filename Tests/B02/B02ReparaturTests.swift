import XCTest
import SwiftData
@testable import MikaPlusPlayer

/// B02 · Reparatur (Fehlerauftrag QA 1, gemeinsam mit B03): Tests für Fälle, die der QA-Bericht nicht als eigenen Test
/// hatte – Zerlegen und Wiederherstellen der Zugangsdaten, Umstellung vorhandener Datenbanken (auch der v1.1-Vorlage),
/// fehlender Schlüsselbund-Eintrag, Grenzen je Art, Datei-Import abseits des Main-Threads.
/// Nur Temp-Datenbanken, Test-Schlüsselbunddienst dieses Laufs, Loopback-Server, erfundene Zugangsdaten.
final class B02ReparaturTests: B02TestCase {

    private typealias Marker = M3UCredentials.Marker

    // MARK: BUG-01 · Zerlegen und Wiederherstellen

    func testBUG01_ZerlegenUndWiederherstellen() throws {
        let pass = "qa-pass-b02rep"
        // get.php-Link: Zugangsdaten als Query
        let getPhp = URL(string: "http://h.example:8080/get.php?username=qa-user&password=\(pass)&type=m3u_plus&output=ts")!
        let split = try XCTUnwrap(M3UCredentials.split(getPhp))
        XCTAssertEqual(split.secret, M3USecret(sourceURL: getPhp.absoluteString, username: "qa-user", password: pass))
        XCTAssertEqual(split.stored.absoluteString,
                       "http://h.example:8080/get.php?username=\(Marker.queryUser)&password=\(Marker.queryPassword)&type=m3u_plus&output=ts")
        XCTAssertTrue(M3UCredentials.needsSecret(split.stored))
        XCTAssertNil(M3UCredentials.split(split.stored), "Platzhalter gelten nicht als Zugangsdaten")

        // Stream-Adressen in den üblichen Formen; die Wiederherstellung ergibt exakt die Liste
        let streams = [
            "http://h.example:8080/live/qa-user/\(pass)/101.ts",
            "http://h.example:8080/qa-user/\(pass)/102",
            "http://h.example:8080/live/103.m3u8?token=\(pass)",
            "http://qa-user:\(pass)@cdn.example/hls/104.m3u8",
            "http://h.example:8080/movie/qa-user-archiv/105.ts",          // Benutzername nur als Teil → bleibt
            "https://anderer.example/live/stream.m3u8"                      // ohne Zugangsdaten → unverändert
        ].map { URL(string: $0)! }
        for original in streams {
            let redacted = M3UCredentials.redact(original, secret: split.secret)
            XCTAssertFalse(redacted.absoluteString.contains(pass), original.absoluteString)
            XCTAssertEqual(M3UCredentials.restore(redacted, secret: split.secret), original, original.absoluteString)
        }
        XCTAssertEqual(M3UCredentials.redact(streams[5], secret: split.secret), streams[5])
        XCTAssertEqual(M3UCredentials.redact(streams[0], secret: split.secret).absoluteString,
                       "http://h.example:8080/live/\(Marker.pathUser)/\(Marker.pathPassword)/101.ts")

        // Benutzerinfo, Sonderzeichen
        let special = "p@ss w/rd+1"
        let info = URL(string: "http://qa-user:\(special.addingPercentEncoding(withAllowedCharacters: .urlPasswordAllowed.subtracting(CharacterSet(charactersIn: "@/:")))!)@h.example/liste.m3u")!
        let infoSplit = try XCTUnwrap(M3UCredentials.split(info))
        XCTAssertEqual(infoSplit.secret.password, special)
        XCTAssertEqual(infoSplit.secret.username, "qa-user")
        XCTAssertEqual(infoSplit.stored.absoluteString, "http://\(Marker.infoUser):\(Marker.infoPassword)@h.example/liste.m3u")
        XCTAssertEqual(M3UCredentials.restore(infoSplit.stored, secret: infoSplit.secret), info)

        // Ohne Passwort: nichts zu tun
        XCTAssertNil(M3UCredentials.split(URL(string: "http://h.example/liste.m3u?token=abc&username=nur-name")!))
        XCTAssertNil(M3UCredentials.split(URL(string: "http://nur-name@h.example/liste.m3u")!))
    }

    // MARK: BUG-01 · Aktualisieren und Resolver über den Schlüsselbund

    @MainActor func testBUG01_AktualisierenMitZugangsdatenAusDemSchluesselbund() async throws {
        let pass = "qa-pass-b02rep-\(UInt32.random(in: 1000...9999))"
        server.handler = { _ in B02Server.ok(B02SicherheitTests.getPhpListe(user: "qa-user", pass: pass)) }
        let dir = try tempDir("rep-refresh")
        let (container, storeURL) = try B02.fileContainer(in: dir)
        let ctx = container.mainContext
        let input = server.url("/get.php?username=qa-user&password=\(pass)&type=m3u_plus")
        let p = try await B02.importURL(input, ctx).get()
        p.channels.first { $0.name == "Eins" }?.isFavorite = true
        try ctx.save()
        server.resetLog()
        try await PlaylistImporter(modelContext: ctx).refresh(p)
        let target = try XCTUnwrap(server.requests.first?.target)
        let raw = B02.bytes(pass, storeURL).values.reduce(0, +)
        B02.log("BUG-01|aktualisieren|anfrage=\(target.replacingOccurrences(of: pass, with: "<pass>"))|rohBytes=\(raw)|favoriten=\(p.channels.filter(\.isFavorite).map(\.name))")
        XCTAssertEqual(target, "/get.php?username=qa-user&password=\(pass)&type=m3u_plus", "Abruf wie eingegeben")
        XCTAssertEqual(raw, 0)
        XCTAssertEqual(p.channels.filter(\.isFavorite).map(\.name), ["Eins"])
        let playable = try p.channels.map { try StreamURLResolver.playableURL(for: $0).absoluteString }
        XCTAssertEqual(Set(playable), ["\(B02.dead)/live/qa-user/\(pass)/101.ts", "\(B02.dead)/qa-user/\(pass)/102",
                                       "\(B02.dead)/live/103.m3u8?token=\(pass)"])
    }

    @MainActor func testBUG01_FehlenderSchluesselbundEintragMeldetSichOhneAnfrage() async throws {
        let pass = "qa-pass-b02rep-miss"
        server.handler = { _ in B02Server.ok(B02SicherheitTests.getPhpListe(user: "qa-user", pass: pass)) }
        let c = try B02.memory()
        let p = try await B02.importURL(server.url("/get.php?username=qa-user&password=\(pass)"), c.mainContext).get()
        try XtreamCredentialStore.standard.delete(for: p.id)
        server.resetLog()
        var message = "kein Fehler"
        do { try await PlaylistImporter(modelContext: c.mainContext).refresh(p) } catch { message = error.localizedDescription }
        let channel = try XCTUnwrap(p.channels.first { $0.name == "Eins" })
        XCTAssertThrowsError(try StreamURLResolver.playableURL(for: channel)) { error in
            XCTAssertEqual(error as? StreamURLResolver.ResolveError, .missingPlaylistCredentials)
        }
        XCTAssertEqual(message, "Die Zugangsdaten dieser Playlist fehlen auf diesem Gerät. Bitte die Playlist löschen und neu importieren.")
        XCTAssertEqual(server.requests.count, 0, "ohne Zugangsdaten keine Anfrage")
        XCTAssertEqual(p.channelCount, 3, "alte Liste bleibt")
    }

    // MARK: BUG-01 · Umstellung vorhandener Datenbanken

    /// Datenbank wie bis heute (Zugangsdaten im Klartext in `sourceURL` und jeder Stream-Adresse) → Umstellung beim Start:
    /// Schlüsselbund, Platzhalter, dieselben Sender-Objekte, Favoriten bleiben, abspielbar wie vorher, keine Bytefolge mehr.
    @MainActor func testBUG01_UmstellungVorhandenerDatenbank() async throws {
        let pass = "qa-pass-b02mig-\(UInt32.random(in: 1000...9999))"
        let dir = try tempDir("rep-mig")
        let storeURL = dir.appendingPathComponent(AppPersistence.storeFileName)
        var ids: [UUID] = []
        var legacy: [UUID: String] = [:]
        let plainID: UUID
        do {
            let container = try AppPersistence.diskContainer(at: storeURL, schema: AppSchema.schema)
            let ctx = ModelContext(container)
            let p = Playlist(name: "Alt M3U", sourceURL: URL(string: "http://h.example/get.php?username=qa-user&password=\(pass)&type=m3u_plus")!,
                             lastRefreshed: Date())
            ctx.insert(p)
            let urls = ["http://h.example/live/qa-user/\(pass)/1.ts", "http://h.example/live/2.m3u8?token=\(pass)", "http://cdn.example/3.m3u8"]
            var channels: [Channel] = []
            for (i, u) in urls.enumerated() {
                let ch = Channel(name: "Alt \(i)", streamURL: URL(string: u)!, tvgID: "alt.\(i)", isFavorite: i == 0, playlistID: p.id)
                ctx.insert(ch)
                channels.append(ch)
                legacy[ch.id] = u
            }
            p.channels.append(contentsOf: channels)
            p.channelCount = channels.count
            let plain = Playlist(name: "Ohne Zugang", sourceURL: URL(string: "http://h.example/liste.m3u?token=bleibt")!)
            ctx.insert(plain)
            plainID = plain.id
            try ctx.save()
            ids = channels.map(\.id)
            XCTAssertGreaterThan(B02.bytes(pass, storeURL).values.reduce(0, +), 0, "Ausgangslage: Klartext")
        }
        try await Task.sleep(nanoseconds: 500_000_000)

        let (container, outcome) = AppPersistence.openStore(at: storeURL, schema: AppSchema.schema)
        XCTAssertEqual(outcome, .opened)
        let result = AppPersistence.migrateCredentials(container: container, storeURL: storeURL, store: .standard)
        B02.log("BUG-01|umstellung|\(result)")
        XCTAssertEqual(result, AppPersistence.CredentialMigrationResult(migratedPlaylists: 1, rewrittenChannels: 2, failedPlaylists: 0))
        let ctx = container.mainContext
        let all = try ctx.fetch(FetchDescriptor<Playlist>())
        let migrated = try XCTUnwrap(all.first { $0.name == "Alt M3U" })
        XCTAssertEqual(Set(migrated.channels.map(\.id)), Set(ids), "dieselben Sender-Objekte")
        XCTAssertEqual(migrated.channels.filter(\.isFavorite).map(\.name), ["Alt 0"])
        XCTAssertFalse(migrated.sourceURL?.absoluteString.contains(pass) ?? true)
        XCTAssertEqual(try XtreamCredentialStore.standard.loadM3U(for: migrated.id)?.password, pass)
        for ch in migrated.channels {
            XCTAssertFalse(ch.streamURL.absoluteString.contains(pass))
            XCTAssertEqual(try StreamURLResolver.playableURL(for: ch).absoluteString, legacy[ch.id], "abspielbar wie vorher")
        }
        XCTAssertEqual(all.first { $0.id == plainID }?.sourceURL?.absoluteString, "http://h.example/liste.m3u?token=bleibt")
        XCTAssertEqual(B02.bytes(pass, storeURL).values.reduce(0, +), 0, "nach dem Verdichten keine Bytefolge")
        XCTAssertEqual(AppPersistence.migrateCredentials(container: container, storeURL: storeURL, store: .standard),
                       AppPersistence.CredentialMigrationResult(), "zweiter Start: nichts mehr zu tun")
    }

    /// Dieselbe Umstellung auf der v1.1-Vorlage (B09): Vorlage kopieren, eine M3U-Playlist mit Zugangsdaten so anlegen,
    /// wie v1.1 sie gespeichert hätte, schließen, über den Startpfad öffnen und umstellen. Die Playlist der Vorlage bleibt.
    @MainActor func testBUG01_UmstellungAufDerV11Vorlage() async throws {
        let fixture = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("B09/Fixtures/v1.1-schema.store")
        guard FileManager.default.fileExists(atPath: fixture.path) else { throw XCTSkip("Vorlage fehlt") }
        let dir = try tempDir("rep-v11")
        let storeURL = dir.appendingPathComponent(AppPersistence.storeFileName)
        try FileManager.default.copyItem(at: fixture, to: storeURL)
        let pass = "qa-pass-b02v11-\(UInt32.random(in: 1000...9999))"
        var fixtureNames: [String] = []
        do {
            let (container, outcome) = AppPersistence.openStore(at: storeURL, schema: AppSchema.schema)
            XCTAssertEqual(outcome, .opened)
            let ctx = ModelContext(container)
            fixtureNames = try ctx.fetch(FetchDescriptor<Playlist>()).map(\.name)
            let p = Playlist(name: "v1.1 M3U", sourceURL: URL(string: "http://qa-user:\(pass)@h.example/liste.m3u")!, lastRefreshed: Date())
            ctx.insert(p)
            let ch = Channel(name: "Kanal", streamURL: URL(string: "http://qa-user:\(pass)@h.example/live/1.ts")!, isFavorite: true, playlistID: p.id)
            ctx.insert(ch)
            p.channels.append(ch)
            p.channelCount = 1
            try ctx.save()
        }
        try await Task.sleep(nanoseconds: 500_000_000)
        let (container, outcome) = AppPersistence.openStore(at: storeURL, schema: AppSchema.schema)
        XCTAssertEqual(outcome, .opened)
        let result = AppPersistence.migrateCredentials(container: container, storeURL: storeURL, store: .standard)
        let names = try container.mainContext.fetch(FetchDescriptor<Playlist>()).map(\.name)
        B02.log("BUG-01|v1.1-vorlage|vorlage=\(fixtureNames)|\(result)|nachher=\(names.sorted())")
        XCTAssertEqual(fixtureNames, ["B09 v1.1 Testliste"])
        XCTAssertEqual(Set(names), Set(fixtureNames + ["v1.1 M3U"]), "Vorlage und neue Playlist bleiben")
        XCTAssertEqual(result, AppPersistence.CredentialMigrationResult(migratedPlaylists: 1, rewrittenChannels: 1, failedPlaylists: 0))
        let m = try XCTUnwrap(try container.mainContext.fetch(FetchDescriptor<Playlist>()).first { $0.name == "v1.1 M3U" })
        let ch = try XCTUnwrap(m.channels.first)
        XCTAssertTrue(ch.isFavorite)
        XCTAssertEqual(try StreamURLResolver.playableURL(for: ch).absoluteString, "http://qa-user:\(pass)@h.example/live/1.ts")
        XCTAssertEqual(B02.bytes(pass, storeURL).values.reduce(0, +), 0)
    }

    // MARK: BUG-03 · Grenzen je Art

    @MainActor func testBUG03_GroessenMengenUndZeitgrenzen() async throws {
        let c = try B02.memory()
        var small = PlaylistImporter.M3ULimits()
        small.maxBytes = 2_000
        small.parser.maxChannels = 3
        small.totalTimeout = 4
        small.throughput = PlaylistHTTPLoader.Throughput(bytesPerSecond: 1, grace: 3_600)
        let importer = PlaylistImporter(modelContext: c.mainContext, m3uLimits: small)
        func message(_ op: () async throws -> Playlist) async -> String {
            do { _ = try await op(); return "OK" } catch { return error.localizedDescription }
        }
        // Größe per URL
        server.handler = { _ in B02Server.ok(B02.grosseListe(100)) }
        let tooBigURL = await message { try await importer.importFromURL(server.url("/gross.m3u"), name: "") }
        // Größe per Datei
        let dir = try tempDir("rep-grenzen")
        let file = dir.appendingPathComponent("gross.m3u")
        try B02.grosseListe(100).write(to: file)
        let tooBigFile = await message { try await importer.importFromFile(file) }
        // Menge
        server.handler = { _ in B02Server.ok(B02.grosseListe(5)) }
        let tooMany = await message { try await importer.importFromURL(server.url("/fuenf.m3u"), name: "") }
        // Gesamtfrist
        let head = Data("HTTP/1.1 200 OK\r\nContent-Length: 400\r\nConnection: close\r\n\r\n".utf8)
        server.handler = { _ in .trickle(head: head, body: Data(repeating: 0x41, count: 400), chunks: 20, interval: 1) }
        let t = Date()
        let deadline = await message { try await importer.importFromURL(server.url("/langsam.m3u"), name: "") }
        let elapsed = Date().timeIntervalSince(t)
        B02.log("BUG-03|url=\(tooBigURL)|datei=\(tooBigFile)|menge=\(tooMany)|frist=\(deadline) nach \(B02.f2(elapsed)) s")
        XCTAssertEqual(tooBigURL, "Netzwerkfehler: Die Playlist ist zu groß (mehr als 1 MB).")
        XCTAssertEqual(tooBigFile, "Die Datei ist zu groß (mehr als 1 MB).")
        XCTAssertEqual(tooMany, "Die Senderliste ist zu groß (mehr als 3 Sender).")
        XCTAssertEqual(deadline, "Netzwerkfehler: Der Server hat die Playlist nicht innerhalb von 4 Sekunden vollständig geliefert.")
        XCTAssertLessThan(elapsed, 8)
        XCTAssertEqual(B02.count(Playlist.self, c.mainContext), 0, "nichts angelegt")
        XCTAssertEqual(PlaylistImporter.M3ULimits.standard.maxBytes, 64 * 1024 * 1024)
        XCTAssertEqual(PlaylistImporter.M3ULimits.standard.parser.maxChannels, 100_000)
    }

    // MARK: BUG-04 · Datei-Import abseits des Main-Threads

    /// Datei mit 6.000 Sendern (Messung 17.000 über `TEST_RUNNER_B02_REP_DATEI=17000`): Lesen, Parsen und Speichern
    /// blockieren den Main-Thread nicht.
    @MainActor func testBUG04_DateiImportBlockiertDenMainThreadNicht() async throws {
        let n = Int(ProcessInfo.processInfo.environment["B02_REP_DATEI"] ?? "") ?? 6_000
        let dir = try tempDir("rep-datei")
        let file = dir.appendingPathComponent("gross.m3u")
        try B02.grosseListe(n).write(to: file)
        let (container, _) = try B02.fileContainer(in: try tempDir("rep-datei-db"))
        let watchdog = MainThreadWatchdog(); watchdog.start()
        let t = Date()
        let p = try await B02.importFile(file, container.mainContext).get()
        let elapsed = Date().timeIntervalSince(t)
        try await Task.sleep(nanoseconds: 300_000_000)
        let gap = watchdog.stop()
        B02.evidence("AK-40-messung.txt", "BUG-04|datei|sender=\(n)|gesamt=\(B02.f2(elapsed))s|maxMainThreadBlockade=\(B02.f2(gap))s|build=\(B02.buildConfiguration)")
        XCTAssertEqual(p.channelCount, n)
        XCTAssertLessThan(gap, 0.5)
    }
}
