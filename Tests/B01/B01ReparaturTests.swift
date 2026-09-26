import XCTest
import SwiftData
import CoreData
@testable import MikaPlusPlayer

/// Fremde Entität, um eine `default.store` einer anderen App bzw. mit fremdem Schema nachzustellen (BUG-04).
@Model
final class B01QAFremdeEntitaet {
    var titel: String
    init(titel: String) { self.titel = titel }
}

/// B01 · Reparatur (sdd-build 2026-09-16): Schlüsselbund, Migration vorhandener Datenbanken, Speicherort,
/// HTTP-Cache, Aktualisieren (B03) nach der Umstellung, Abbrechen.
///
/// Schlüsselbund nur unter dem Test-Dienst dieses Laufs (`XtreamCredentialStore.standard` im Test-Host) oder einem
/// eigenen Dienst je Test; alle Einträge werden am Ende gelöscht. Datenbanken nur im Temp-Verzeichnis.
final class B01ReparaturTests: B01MockTestCase {

    private var tempDirs: [URL] = []
    private var extraStores: [XtreamCredentialStore] = []

    override func tearDown() {
        for store in extraStores { XCTAssertNoThrow(try store.deleteAll()) }
        for dir in tempDirs { try? FileManager.default.removeItem(at: dir) }
        super.tearDown()
    }

    private func tempDir(_ label: String) throws -> URL {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("b01-build-\(label)-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        tempDirs.append(dir)
        return dir
    }

    private func testStore() -> XtreamCredentialStore {
        let store = XtreamCredentialStore(service: "lu.daumedia.MikaPlusPlayer.b01-build-tests.\(UUID().uuidString)")
        extraStores.append(store)
        return store
    }

    // MARK: - Schlüsselbund

    func testBUG01_SchluesselbundSpeichernLesenErsetzenLoeschen() throws {
        XCTAssertTrue(XtreamCredentialStore.standard.service.contains(".tests."), "Test-Host nutzt eigenen Dienst")
        let store = testStore()
        let id = UUID()
        XCTAssertNil(try store.load(for: id))
        let first = XtreamSecret(host: "http://127.0.0.1:1", username: "qa-user", password: "qa-pass-kc1")
        try store.save(first, for: id)
        XCTAssertEqual(try store.load(for: id), first)
        let second = XtreamSecret(host: "https://127.0.0.1:2", username: "qa-user", password: "qa-pass-kc2")
        try store.save(second, for: id)
        XCTAssertEqual(try store.load(for: id), second, "Speichern ersetzt den Eintrag")
        let other = UUID()
        try store.save(first, for: other)
        try store.delete(for: id)
        XCTAssertNil(try store.load(for: id))
        XCTAssertEqual(try store.load(for: other), first, "Löschen trifft nur die eine Playlist")
        XCTAssertNoThrow(try store.delete(for: id), "Löschen eines fehlenden Eintrags ist kein Fehler")
        try store.deleteAll()
        XCTAssertNil(try store.load(for: other))
    }

    // MARK: - Zentrale Adressbildung

    @MainActor func testBUG01_ResolverM3UUnveraendertXtreamMitSchluesselbund() async throws {
        let container = try B01.inMemoryContainer()
        let ctx = container.mainContext
        // M3U-Sender: unverändert
        let m3u = Playlist(name: "M3U", sourceURL: URL(string: "http://example.com/list.m3u"))
        ctx.insert(m3u)
        let m3uChannel = Channel(name: "M", streamURL: URL(string: "http://example.com/stream.m3u8?token=t")!, playlistID: m3u.id)
        ctx.insert(m3uChannel)
        m3u.channels.append(m3uChannel)
        XCTAssertEqual(try StreamURLResolver.playableURL(for: m3uChannel).absoluteString, "http://example.com/stream.m3u8?token=t")

        // Xtream über den echten Import
        let p = try await B01.importXtream(host: mock.hostPort, user: "qa user", pass: "qa#pass/1?", context: ctx).get()
        let channel = try XCTUnwrap(p.channels.first(where: { $0.name == "Kanal Int" }))
        XCTAssertEqual(channel.streamURL.absoluteString, "http://\(mock.hostPort)/live/101.ts")
        XCTAssertEqual(try B01.playable(channel).absoluteString,
                       "http://\(mock.hostPort)/live/qa%20user/qa%23pass%2F1%3F/101.ts")

        // Fehlt der Eintrag (z. B. nach Wiederherstellung auf einem neuen Gerät): verständlicher Fehler
        try XtreamCredentialStore.standard.delete(for: p.id)
        XCTAssertThrowsError(try B01.playable(channel)) { error in
            XCTAssertEqual(error as? StreamURLResolver.ResolveError, .missingCredentials)
        }
        await XCTAssertThrowsErrorAsync(try await PlaylistImporter(modelContext: ctx).refresh(p)) { error in
            XCTAssertEqual(error as? StreamURLResolver.ResolveError, .missingCredentials)
        }
    }

    // MARK: - B03 Aktualisieren nach der Umstellung

    @MainActor func testBUG01_AktualisierenLiestSchluesselbundUndBehaeltFavoriten() async throws {
        let container = try B01.inMemoryContainer()
        let ctx = container.mainContext
        let p = try await B01.importXtream(host: "http://qa-u:qa-pw@\(mock.hostPort)", pass: "qa-pass-refresh", context: ctx).get()
        let fav = try XCTUnwrap(p.channels.first(where: { $0.name == "Kanal Int" }))
        fav.isFavorite = true
        try ctx.save()
        mock.resetLog()

        try await PlaylistImporter(modelContext: ctx, loginThrottle: XtreamLoginThrottle()).refresh(p)

        XCTAssertEqual(mock.requests.count, 3)
        XCTAssertTrue(mock.requests.allSatisfy { $0.username == "qa-user" && $0.password == "qa-pass-refresh" })
        XCTAssertEqual(p.channelCount, MockXtreamServer.streams.count)
        XCTAssertEqual(try ctx.fetchCount(FetchDescriptor<Channel>()), MockXtreamServer.streams.count)
        XCTAssertEqual(p.channels.filter(\.isFavorite).map(\.name), ["Kanal Int"], "Favorit bleibt")
        XCTAssertTrue(p.channels.allSatisfy { !$0.streamURL.absoluteString.contains("qa-pass-refresh") })
        let url = try B01.playable(try XCTUnwrap(p.channels.first(where: { $0.name == "Kanal Int" })))
        XCTAssertEqual(url.absoluteString, "http://qa-u:qa-pw@\(mock.hostPort)/live/qa-user/qa-pass-refresh/101.ts",
                       "H-1 entfällt: Benutzerinfo bleibt beim Aktualisieren erhalten")
        XCTAssertNil(p.sourceURL?.query)
    }

    // MARK: - Migration vorhandener Datenbanken

    /// Legt Daten so an, wie `PlaylistImporter.importFromXtream` bis Version 1.1 sie gespeichert hat
    /// (Code-Pfad nachgebildet: `playerAPIURL()` mit Zugangsdaten, Stream-Adressen per Interpolation).
    private func insertLegacyXtream(into ctx: ModelContext, host: String, user: String, pass: String,
                                    streams: [(id: String, name: String, favorite: Bool)], output: String = "mpegts") throws -> Playlist {
        var h = host
        if !h.lowercased().hasPrefix("http://") { h = "http://" + h }
        var comps = try XCTUnwrap(URLComponents(string: h))
        comps.path = ""
        comps.query = nil
        let base = try XCTUnwrap(comps.url)
        var api = comps
        api.path = "/player_api.php"
        api.queryItems = [URLQueryItem(name: "username", value: user), URLQueryItem(name: "password", value: pass)]
        let playlist = Playlist(name: "Alt \(user)", sourceURL: api.url, lastRefreshed: Date(), isXtream: true, xtreamOutput: output)
        ctx.insert(playlist)
        let ext = output == "hls" ? "m3u8" : "ts"
        for s in streams {
            let url = try XCTUnwrap(URL(string: "\(base.absoluteString)/live/\(user)/\(pass)/\(s.id).\(ext)"))
            let channel = Channel(name: s.name, streamURL: url, playlist: playlist, playlistID: playlist.id)
            channel.isFavorite = s.favorite
            ctx.insert(channel)
        }
        playlist.channelCount = streams.count
        return playlist
    }

    @MainActor func testBUG01_MigrationVorhandenerDatenbankOhneDatenverlust() async throws {
        let dir = try tempDir("migration")
        let url = dir.appendingPathComponent("legacy.store")
        let store = testStore()
        let schema = B01.schema
        let marker = "qa-pass-mig-\(UInt32.random(in: 1000...9999))"
        let streams: [(id: String, name: String, favorite: Bool)] = [("101", "Eins", true), ("102", "Zwei", false), ("abc/def", "Pfad", true)]

        var legacyURLs: [String: String] = [:]
        var ids: [String: UUID] = [:]
        var channelIDs: Set<UUID> = []
        do {
            let container = try ModelContainer(for: schema, configurations: [ModelConfiguration(schema: schema, url: url)])
            let ctx = ModelContext(container)
            let a = try insertLegacyXtream(into: ctx, host: "127.0.0.1:18765", user: "qa-user", pass: marker, streams: streams)
            let b = try insertLegacyXtream(into: ctx, host: "http://qa-host.invalid:8080/", user: "qa user ä", pass: "\(marker)+&=x",
                                           streams: [("7", "Sieben", true)], output: "hls")
            let c = try insertLegacyXtream(into: ctx, host: "http://qa-u:qa-pw@127.0.0.1:18766", user: "qa-user", pass: "\(marker)/slash",
                                           streams: [("8", "Acht", false)])
            let m3u = Playlist(name: "M3U", sourceURL: URL(string: "http://example.com/list.m3u?token=qa-token"), lastRefreshed: Date())
            ctx.insert(m3u)
            let m3uChannel = Channel(name: "M", streamURL: URL(string: "http://example.com/s.m3u8?token=qa-token")!, playlist: m3u, playlistID: m3u.id)
            m3uChannel.isFavorite = true
            ctx.insert(m3uChannel)
            m3u.channelCount = 1
            try ctx.save()
            ids = ["a": a.id, "b": b.id, "c": c.id, "m3u": m3u.id]
            for p in [a, b, c, m3u] {
                for ch in p.channels {
                    legacyURLs["\(p.name)|\(ch.name)"] = ch.streamURL.absoluteString
                    channelIDs.insert(ch.id)
                }
            }
            XCTAssertGreaterThan(B01.rawOccurrences(of: marker, inFilesWithPrefix: url).values.reduce(0, +), 0, "Ausgangslage: Klartext")
        }
        try await Task.sleep(nanoseconds: 1_000_000_000)

        // Start der neuen Version: Container öffnen, Umstellung laufen lassen
        let container = try ModelContainer(for: schema, configurations: [ModelConfiguration(schema: schema, url: url)])
        let start = Date()
        let result = AppPersistence.migrateCredentials(container: container, storeURL: url, store: store)
        print("B01BUILD|MIGRATION|\(result)|dauer=\(String(format: "%.2f", Date().timeIntervalSince(start)))s")
        XCTAssertEqual(result, AppPersistence.CredentialMigrationResult(migratedPlaylists: 3, rewrittenChannels: 5, failedPlaylists: 0))

        let ctx = container.mainContext
        let all = try ctx.fetch(FetchDescriptor<Playlist>())
        XCTAssertEqual(all.count, 4)
        let allChannels = try ctx.fetch(FetchDescriptor<Channel>())
        XCTAssertEqual(Set(allChannels.map(\.id)), channelIDs, "dieselben Sender-Objekte")
        XCTAssertEqual(Set(allChannels.filter(\.isFavorite).map(\.name)), ["Eins", "Pfad", "Sieben", "M"], "Favoriten bleiben")

        for p in all where p.isXtream {
            XCTAssertNil(p.sourceURL?.query, p.name)
            XCTAssertNil(p.sourceURL?.user, p.name)
            XCTAssertEqual(p.sourceURL?.path, "/player_api.php")
            XCTAssertEqual(p.channelCount, p.channels.count)
            let secret = try XCTUnwrap(try store.load(for: p.id))
            XCTAssertTrue(secret.password.hasPrefix(marker))
            for ch in p.channels {
                XCTAssertFalse(ch.streamURL.absoluteString.contains(marker), ch.streamURL.absoluteString)
                XCTAssertNil(ch.streamURL.user)
                XCTAssertEqual(ch.playlistID, p.id)
                let playable = try StreamURLResolver.playableURL(for: ch, store: store)
                let legacy = try XCTUnwrap(legacyURLs["\(p.name)|\(ch.name)"])
                if p.id == ids["c"] {
                    // Passwort mit `/` war vorher zerlegt (BUG-05); jetzt ein kodierter Abschnitt
                    XCTAssertEqual(playable.absoluteString, "http://qa-u:qa-pw@127.0.0.1:18766/live/qa-user/\(marker)%2Fslash/8.ts")
                } else {
                    XCTAssertEqual(playable.absoluteString, legacy, "abspielbare Adresse wie vorher")
                }
            }
        }
        let m3u = try XCTUnwrap(all.first { $0.id == ids["m3u"] })
        XCTAssertEqual(m3u.sourceURL?.absoluteString, "http://example.com/list.m3u?token=qa-token", "M3U unangetastet")
        XCTAssertEqual(m3u.channels.first?.streamURL.absoluteString, legacyURLs["M3U|M"])

        // Kein Klartext mehr in Store, -wal, -shm – schon bei offenem Container
        let rawOpen = B01.rawOccurrences(of: marker, inFilesWithPrefix: url)
        print("B01BUILD|MIGRATION|rawBytesOffen=\(rawOpen)")
        XCTAssertEqual(rawOpen.values.reduce(0, +), 0)

        // Zweiter Start: nichts mehr zu tun
        XCTAssertEqual(AppPersistence.migrateCredentials(container: container, storeURL: url, store: store),
                       AppPersistence.CredentialMigrationResult())
    }

    @MainActor func testBUG01_AltbestandBleibtSpielbarUndWirdBeimAktualisierenUmgestellt() async throws {
        let container = try B01.inMemoryContainer()
        let ctx = container.mainContext
        let p = try insertLegacyXtream(into: ctx, host: mock.hostPort, user: "qa-user", pass: "qa-pass-alt",
                                       streams: [("101", "Kanal Int", true)])
        p.channels.first?.tvgID = "kanal.int"  // wie beim alten Import aus epg_channel_id; Favoriten-Schlüssel (B05)
        try ctx.save()
        let channel = try XCTUnwrap(p.channels.first)
        XCTAssertEqual(try B01.playable(channel).absoluteString, "http://\(mock.hostPort)/live/qa-user/qa-pass-alt/101.ts",
                       "nicht umgestellter Altbestand spielt weiter")

        try await PlaylistImporter(modelContext: ctx, loginThrottle: XtreamLoginThrottle()).refresh(p)
        XCTAssertNil(p.sourceURL?.query)
        XCTAssertEqual(try XtreamCredentialStore.standard.load(for: p.id)?.password, "qa-pass-alt")
        XCTAssertTrue(p.channels.allSatisfy { !$0.streamURL.absoluteString.contains("qa-pass-alt") })
        XCTAssertEqual(p.channels.filter(\.isFavorite).count, 1)
        XCTAssertEqual(try B01.playable(try XCTUnwrap(p.channels.first(where: { $0.name == "Kanal Int" }))).absoluteString,
                       "http://\(mock.hostPort)/live/qa-user/qa-pass-alt/101.ts")
    }

    // MARK: - BUG-04 Speicherort und Übernahme der alten Datei

    private func makeStore(at url: URL, schema: Schema, fill: (ModelContext) throws -> Void) throws {
        let container = try ModelContainer(for: schema, configurations: [ModelConfiguration(schema: schema, url: url)])
        let ctx = ModelContext(container)
        try fill(ctx)
        try ctx.save()
    }

    @MainActor func testBUG04_UebernahmeNurBeiEigenemSchemaKopierenDannLoeschen() async throws {
        let bundleID = "lu.daumedia.MikaPlusPlayer"

        // 1) default.store dieser App → kopiert, geprüft, alte Datei entfernt, Daten vollständig
        let support = try tempDir("adopt")
        let legacy = support.appendingPathComponent("default.store")
        try makeStore(at: legacy, schema: B01.schema) { ctx in
            let p = try self.insertLegacyXtream(into: ctx, host: "127.0.0.1:18765", user: "qa-user", pass: "qa-pass-adopt",
                                                streams: [("1", "A", true), ("2", "B", false)])
            p.name = "Übernommen"
        }
        try await Task.sleep(nanoseconds: 800_000_000)
        let (storeURL, outcome) = AppPersistence.prepareStore(applicationSupport: support, bundleID: bundleID)
        print("B01BUILD|BUG-04|eigenesSchema|\(outcome)")
        XCTAssertEqual(outcome, .adopted)
        XCTAssertEqual(storeURL, support.appendingPathComponent(bundleID).appendingPathComponent("MikaPlusPlayer.store"))
        XCTAssertFalse(FileManager.default.fileExists(atPath: legacy.path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: legacy.path + "-wal"))
        do {
            let container = try ModelContainer(for: B01.schema, configurations: [ModelConfiguration(schema: B01.schema, url: storeURL)])
            let playlists = try container.mainContext.fetch(FetchDescriptor<Playlist>())
            XCTAssertEqual(playlists.map(\.name), ["Übernommen"])
            XCTAssertEqual(try container.mainContext.fetchCount(FetchDescriptor<Channel>()), 2)
            XCTAssertEqual(try container.mainContext.fetch(FetchDescriptor<Channel>()).filter(\.isFavorite).map(\.name), ["A"])
        }
        // zweiter Start: nichts mehr zu tun
        XCTAssertEqual(AppPersistence.prepareStore(applicationSupport: support, bundleID: bundleID).1, .noLegacyStore)

        // 2) default.store mit zusätzlicher fremder Entität → unangetastet
        for (label, schema) in [("zusaetzlich", Schema([Playlist.self, Channel.self, B01QAFremdeEntitaet.self])),
                                ("fremd", Schema([B01QAFremdeEntitaet.self]))] {
            let other = try tempDir("foreign-\(label)")
            let otherLegacy = other.appendingPathComponent("default.store")
            try makeStore(at: otherLegacy, schema: schema) { ctx in ctx.insert(B01QAFremdeEntitaet(titel: "fremd")) }
            try await Task.sleep(nanoseconds: 800_000_000)
            let before = try Data(contentsOf: otherLegacy)
            let (otherStore, otherOutcome) = AppPersistence.prepareStore(applicationSupport: other, bundleID: bundleID)
            print("B01BUILD|BUG-04|\(label)|\(otherOutcome)")
            XCTAssertEqual(otherOutcome, .notOurs, label)
            XCTAssertEqual(try Data(contentsOf: otherLegacy), before, "\(label): alte Datei unverändert")
            XCTAssertFalse(FileManager.default.fileExists(atPath: otherStore.path), "\(label): keine Kopie")
        }

        // 3) keine SQLite-Datei → unangetastet
        let junk = try tempDir("junk")
        let junkFile = junk.appendingPathComponent("default.store")
        try Data("kein sqlite".utf8).write(to: junkFile)
        XCTAssertEqual(AppPersistence.prepareStore(applicationSupport: junk, bundleID: bundleID).1, .notOurs)
        XCTAssertEqual(try Data(contentsOf: junkFile), Data("kein sqlite".utf8))

        // 4) neue Datenbank existiert schon → alte bleibt, wird nicht übernommen
        let both = try tempDir("both")
        let bothLegacy = both.appendingPathComponent("default.store")
        try makeStore(at: bothLegacy, schema: B01.schema) { ctx in ctx.insert(Playlist(name: "alt")) }
        let newURL = AppPersistence.storeURL(applicationSupport: both, bundleID: bundleID)
        try FileManager.default.createDirectory(at: newURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try makeStore(at: newURL, schema: B01.schema) { ctx in ctx.insert(Playlist(name: "neu")) }
        XCTAssertEqual(AppPersistence.prepareStore(applicationSupport: both, bundleID: bundleID).1, .newStoreExists)
        XCTAssertTrue(FileManager.default.fileExists(atPath: bothLegacy.path))
    }

    // MARK: - BUG-03 alter HTTP-Cache

    func testBUG03_AlterHTTPCacheWirdEinmaligGeleert() async throws {
        // Eigener Cache im Temp-Ordner, ohne Speicheranteil: jede Abfrage liest die Platte. Der Ordner bleibt bis zum
        // Aufräumen des Systems liegen, weil URLCache seine SQLite-Datei nicht schließen lässt.
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("b01-build-cache-\(UUID().uuidString)", isDirectory: true)
        let cache = URLCache(memoryCapacity: 0, diskCapacity: 10_000_000, directory: dir)
        let suite = "lu.daumedia.MikaPlusPlayerTests.b01.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }

        func store(_ pass: String) async throws -> URLRequest {
            let url = URL(string: "http://127.0.0.1:1/player_api.php?username=qa-user&password=\(pass)")!
            let request = URLRequest(url: url)
            let response = HTTPURLResponse(url: url, statusCode: 200, httpVersion: "HTTP/1.1", headerFields: ["Cache-Control": "max-age=3600"])!
            cache.storeCachedResponse(CachedURLResponse(response: response, data: Data("{\"user_info\":{\"password\":\"\(pass)\"}}".utf8)), for: request)
            // Schreiben ist asynchron: warten, bis der Eintrag auf der Platte steht (wie bei einem Altbestand)
            try await waitUntil { cache.cachedResponse(for: request) != nil }
            return request
        }
        func waitUntil(_ condition: () -> Bool) async throws {
            for _ in 0..<50 where !condition() { try await Task.sleep(nanoseconds: 100_000_000) }
        }

        let old = try await store("qa-pass-cache-alt")
        XCTAssertNotNil(cache.cachedResponse(for: old), "Ausgangslage: Eintrag auf der Platte")
        XCTAssertTrue(AppPersistence.purgeLegacyHTTPCacheOnce(defaults: defaults, cache: cache))
        try await waitUntil { cache.cachedResponse(for: old) == nil }
        XCTAssertNil(cache.cachedResponse(for: old), "alter Eintrag entfernt")
        XCTAssertTrue(defaults.bool(forKey: AppPersistence.cachePurgeDefaultsKey))

        let later = try await store("qa-pass-cache-neu")
        XCTAssertFalse(AppPersistence.purgeLegacyHTTPCacheOnce(defaults: defaults, cache: cache), "nur einmal")
        try await Task.sleep(nanoseconds: 300_000_000)
        XCTAssertNotNil(cache.cachedResponse(for: later))
        cache.removeAllCachedResponses()
    }

    // MARK: - BUG-11 Abbrechen im Dienst

    @MainActor func testBUG11_AbgebrochenerImportLegtNichtsAn() async throws {
        let container = try B01.inMemoryContainer()
        let ctx = container.mainContext
        let panel = MockXtreamServer.panel()
        mock.handler = { req in req.action == nil ? .delayed(2, panel(req)) : panel(req) }
        let host = mock.hostPort
        let task = Task { @MainActor () -> String in
            let result = await B01.importXtream(host: host, pass: "qa-pass-cancel", context: container.mainContext)
            switch result {
            case .success: return "Import gelungen"
            case .failure(let error): return error is CancellationError ? "CancellationError" : error.localizedDescription
            }
        }
        try await Task.sleep(nanoseconds: 400_000_000)
        task.cancel()
        let outcome = await task.value
        try await Task.sleep(nanoseconds: 2_500_000_000)
        print("B01BUILD|BUG-11|dienst|\(outcome)|anfragen=\(mock.requests.count)")
        XCTAssertEqual(outcome, "CancellationError")
        XCTAssertEqual(try ctx.fetchCount(FetchDescriptor<Playlist>()), 0)
        XCTAssertEqual(try ctx.fetchCount(FetchDescriptor<Channel>()), 0)
        XCTAssertEqual(mock.requests.count, 1)
    }

    /// Abbruch während des blockweisen Speicherns (Review-Fund): Die Hintergrund-Aufgabe hört auf, die bereits
    /// gespeicherten Blöcke und der Schlüsselbund-Eintrag werden wieder entfernt.
    @MainActor func testBUG11_AbbruchWaehrendDesSpeicherns() async throws {
        let n = 40_000
        let streams: [[String: Any]] = (0..<n).map { ["name": "Sender \($0)", "stream_id": $0, "category_id": "1"] }
        let body = try JSONSerialization.data(withJSONObject: streams)
        let panel = MockXtreamServer.panel()
        mock.handler = { req in
            req.action == "get_live_streams" ? .raw(status: 200, contentType: "application/json", body: body) : panel(req)
        }
        let container = try B01.inMemoryContainer()
        let host = mock.hostPort
        let task = Task { @MainActor () -> String in
            let result = await B01.importXtream(host: host, pass: "qa-pass-cancel-save", context: container.mainContext)
            switch result {
            case .success: return "Import gelungen"
            case .failure(let error): return error is CancellationError ? "CancellationError" : error.localizedDescription
            }
        }
        // warten, bis der erste Block gespeichert ist
        var partialID: UUID?
        for _ in 0..<600 {
            if let first = try container.mainContext.fetch(FetchDescriptor<Playlist>()).first {
                partialID = first.id
                break
            }
            try await Task.sleep(nanoseconds: 20_000_000)
        }
        let id = try XCTUnwrap(partialID, "erster Block wurde nicht gespeichert")
        let savedBeforeCancel = try container.mainContext.fetchCount(FetchDescriptor<Channel>())
        task.cancel()
        let outcome = await task.value
        try await Task.sleep(nanoseconds: 300_000_000)
        let playlists = try container.mainContext.fetchCount(FetchDescriptor<Playlist>())
        let channels = try container.mainContext.fetchCount(FetchDescriptor<Channel>())
        print("B01BUILD|BUG-11|speichern|\(outcome)|senderVorAbbruch=\(savedBeforeCancel)|playlists=\(playlists)|sender=\(channels)")
        XCTAssertEqual(outcome, "CancellationError")
        XCTAssertEqual(playlists, 0)
        XCTAssertEqual(channels, 0)
        XCTAssertNil(try XtreamCredentialStore.standard.load(for: id))
    }

    /// Abbruch zu beliebigen Zeitpunkten (Review-Fund Start/Abbruch-Rennen): Jede Anfrage endet, keine hängt.
    func testBUG11_LoaderEndetBeiAbbruchImmer() async throws {
        mock.handler = { _ in .hang }
        let url = try XCTUnwrap(URL(string: "http://\(mock.hostPort)/player_api.php?username=qa-user&password=qa-pass-race"))
        let finished = B01Counter()
        let rounds = 200
        for i in 0..<rounds {
            let task = Task {
                defer { finished.increment() }
                _ = try? await XtreamHTTPLoader.shared.data(for: URLRequest(url: url), maxBytes: 1_000, deadline: Date().addingTimeInterval(60))
            }
            if i % 4 != 0 { await Task.yield() }
            if i % 3 == 0 { try await Task.sleep(nanoseconds: UInt64(i % 5) * 1_000_000) }
            task.cancel()
        }
        for _ in 0..<200 where finished.value < rounds {
            try await Task.sleep(nanoseconds: 50_000_000)
        }
        print("B01BUILD|BUG-11|loaderAbbruch|beendet=\(finished.value)/\(rounds)")
        XCTAssertEqual(finished.value, rounds, "hängende Anfrage nach Abbruch")
    }

    // MARK: - BUG-07 Bremse ohne Netz

    func testBUG07_BremseZaehltJePanel() {
        let clock = B01TestClock()
        let throttle = XtreamLoginThrottle(now: { clock.now })
        let key = XtreamLoginThrottle.key(for: URL(string: "http://Panel.example:8080")!)
        XCTAssertEqual(key, "http://panel.example:8080")
        XCTAssertEqual(XtreamLoginThrottle.key(for: URL(string: "https://panel.example")!), "https://panel.example:443")
        throttle.recordFailure(for: key)
        throttle.recordFailure(for: key)
        XCTAssertNil(throttle.remainingLock(for: key), "zwei Fehlschläge: noch frei")
        throttle.recordFailure(for: key)
        XCTAssertEqual(throttle.remainingLock(for: key), 30)
        clock.advance(30)
        XCTAssertNil(throttle.remainingLock(for: key))
        for _ in 0..<10 { throttle.recordFailure(for: key) }
        XCTAssertEqual(throttle.remainingLock(for: key), 300, "höchstens fünf Minuten")
        throttle.recordSuccess(for: key)
        XCTAssertNil(throttle.remainingLock(for: key))
    }
}

/// `XCTAssertThrowsError` für `async`-Ausdrücke.
func XCTAssertThrowsErrorAsync<T>(_ expression: @autoclosure () async throws -> T,
                                  file: StaticString = #filePath, line: UInt = #line,
                                  _ handler: (Error) -> Void = { _ in }) async {
    do {
        _ = try await expression()
        XCTFail("Fehler erwartet", file: file, line: line)
    } catch {
        handler(error)
    }
}

final class B01Counter: @unchecked Sendable {
    private let lock = NSLock()
    private var count = 0
    var value: Int { lock.withLock { count } }
    func increment() { lock.withLock { count += 1 } }
}
