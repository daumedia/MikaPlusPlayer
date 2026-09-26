import XCTest
import SwiftData
@testable import MikaPlusPlayer

/// B03 · Reparatur (Fehlerauftrag QA 1, gemeinsam mit B02): Tests für Fälle ohne eigenen QA-Test – Regeln der
/// Favoriten-Übernahme, „Alle Daten entfernen", Verhalten gehaltener Sender und Multiview nach dem Löschen.
/// Temp-Datenbanken, Test-Schlüsselbunddienst dieses Laufs, Mock auf 127.0.0.1, erfundene Daten, tonlos.
final class B03ReparaturTests: B03QATestCase {

    // MARK: BUG-02 · Favoriten-Übernahme (reine Regel)

    func testBUG02_FavoritenUebernahmeRegeln() {
        func p(_ name: String, _ tvg: String?, _ url: String) -> ParsedChannel {
            ParsedChannel(name: name, streamURL: URL(string: "http://h/\(url)")!, logoURL: nil, group: nil, tvgID: tvg)
        }
        func prev(_ name: String, _ tvg: String?, _ url: String) -> FavoriteCarryOver.Previous {
            FavoriteCarryOver.Previous(key: Channel.favoriteKey(name: name, tvgID: tvg), streamURL: URL(string: "http://h/\(url)")!, name: name)
        }
        let list = [p("Film HD", "film", "f1"), p("Film SD", "film", "f2"), p("Film 4K", "film", "f3"),
                    p("Sport", nil, "s1"), p("sport", nil, "s2"), p("Neu", nil, "n")]
        // gleiche Adresse gewinnt
        XCTAssertEqual(FavoriteCarryOver.flags(previous: [prev("Film SD", "film", "f2")], new: list),
                       [false, true, false, false, false, false])
        // Adresse neu → gleicher Name
        XCTAssertEqual(FavoriteCarryOver.flags(previous: [prev("Film 4K", "film", "alt")], new: list),
                       [false, false, true, false, false, false])
        // weder Adresse noch Name → erster Kandidat mit dem Schlüssel (umbenannt, gleiche tvg-ID)
        XCTAssertEqual(FavoriteCarryOver.flags(previous: [prev("Film", "film", "alt")], new: list),
                       [true, false, false, false, false, false])
        // zwei Favoriten mit einem Schlüssel → höchstens zwei
        XCTAssertEqual(FavoriteCarryOver.flags(previous: [prev("Sport", nil, "s1"), prev("sport", nil, "s2")], new: list),
                       [false, false, false, true, true, false])
        // Schlüssel fehlt → kein Favorit
        XCTAssertEqual(FavoriteCarryOver.flags(previous: [prev("Weg", nil, "w")], new: list), Array(repeating: false, count: 6))
        XCTAssertEqual(FavoriteCarryOver.flags(previous: [], new: list), Array(repeating: false, count: 6))
    }

    // MARK: BUG-05 · Gehaltene Sender und Multiview nach dem Löschen

    @MainActor func testBUG05_ResolverUndMultiviewNachDemLoeschen() async throws {
        let (container, _) = try fileContainer("bug05")
        let ctx = container.mainContext
        mock.handler = B03QAPanel().handler()   // /live/ antwortet nie → stumm
        let x = try await importXtream(ctx, pass: "qa-pass-b03-bug05", output: .hls, name: "QA Weg")
        let m = try await importM3U(ctx, name: "QA Bleibt")
        let held = try XCTUnwrap(x.channels.first { $0.name == "Kanal Int" })
        let other = try XCTUnwrap(m.channels.first)
        XCTAssertTrue(try StreamURLResolver.playableURL(for: held).absoluteString.contains("qa-pass-b03-bug05"))

        let session = MultiviewSession()
        session.add(held)
        session.add(other)
        let doomed = try XCTUnwrap(session.slots.first?.engine)
        doomed.setMuted(true)
        session.slots.forEach { $0.engine.setMuted(true) }
        var announced: Set<UUID> = []
        let obs = NotificationCenter.default.addObserver(forName: PlaylistEvents.willDelete, object: nil, queue: nil) {
            announced.formUnion(PlaylistEvents.ids(in: $0))
        }
        defer { NotificationCenter.default.removeObserver(obs) }

        try await PlaylistImporter(modelContext: ctx).delete(x)
        B03QA.log("BUG-05|angekuendigt=\(announced == [x.id])|slots=\(session.slots.map(\.channel.name))|beendet=\(doomed.isPaused)")
        XCTAssertEqual(announced, [x.id])
        XCTAssertEqual(session.slots.count, 1, "nur der Stream der gelöschten Playlist endet")
        XCTAssertEqual(session.slots.first?.playlistID, m.id)
        XCTAssertTrue(doomed.isPaused)
        XCTAssertEqual(doomed.state, .idle)
        XCTAssertThrowsError(try StreamURLResolver.playableURL(for: held)) { error in
            XCTAssertEqual(error as? StreamURLResolver.ResolveError, .playlistDeleted)
        }
        XCTAssertNoThrow(try StreamURLResolver.playableURL(for: other), "andere Playlist unberührt")
        session.clear()
    }

    // MARK: BUG-09 · Alle Daten entfernen

    @MainActor func testBUG09_AlleDatenEntfernen() async throws {
        let (container, storeURL) = try fileContainer("bug09")
        let ctx = container.mainContext
        let tag = String(UInt32.random(in: 100_000...999_999))
        let marker = "qa-b03-bug09-\(tag)"
        let m = try await importM3U(ctx, entries: (0..<20).map { ("\(marker)-m\($0)", nil, "G", "\(B03QA.dead)/m\($0).m3u8") },
                                    name: "QA M", address: "http://qa-user:qa-pass-b03-bug09@\(mock.hostPort)/list.m3u")
        let x = try await importXtream(ctx, streams: B03QA.streams((0..<20).map { ("\(marker)-x\($0)", 300 + $0, nil, "1") }),
                                       pass: "qa-pass-b03-bug09x", name: "QA X")
        for ch in m.channels.prefix(2) { ch.isFavorite = true }
        try ctx.save()
        let ids: Set<UUID> = [m.id, x.id]
        XCTAssertEqual(B01QA2.keychainCount(service: XtreamCredentialStore.standard.service), 2)

        // Beiseitegelegte Datenbank (B09), Cache, Einstellungen – alles in Temp-Orten
        let setAside = storeURL.deletingLastPathComponent().appendingPathComponent(AppPersistence.setAsideFolderName, isDirectory: true)
        try FileManager.default.createDirectory(at: setAside.appendingPathComponent("2026-01-01_00-00-00"), withIntermediateDirectories: true)
        try Data("alt".utf8).write(to: setAside.appendingPathComponent("2026-01-01_00-00-00/MikaPlusPlayer.store"))
        let cacheDir = try tempDir("bug09-cache")
        let cache = URLCache(memoryCapacity: 100_000, diskCapacity: 5_000_000, directory: cacheDir)
        let cachedURL = URL(string: "http://127.0.0.1:9/logo-\(tag).png")!
        cache.storeCachedResponse(CachedURLResponse(response: HTTPURLResponse(url: cachedURL, statusCode: 200, httpVersion: "HTTP/1.1",
                                                                              headerFields: ["Cache-Control": "max-age=3600"])!,
                                                   data: Data(marker.utf8)), for: URLRequest(url: cachedURL))
        let suite = "lu.daumedia.MikaPlusPlayerTests.b03.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defaults.set(true, forKey: "B03.qa")
        defer {
            defaults.removePersistentDomain(forName: suite)
            try? FileManager.default.removeItem(at: FileManager.default.urls(for: .libraryDirectory, in: .userDomainMask)[0]
                .appendingPathComponent("Preferences/\(suite).plist"))
        }
        var announced: Set<UUID> = []
        let obs = NotificationCenter.default.addObserver(forName: PlaylistEvents.willDelete, object: nil, queue: nil) {
            announced.formUnion(PlaylistEvents.ids(in: $0))
        }
        defer { NotificationCenter.default.removeObserver(obs) }

        var targets = AppDataReset.Targets()
        targets.httpCache = cache
        targets.setAsideFolder = setAside
        targets.defaults = (defaults, suite)
        let watchdog = B03QAWatchdog(); watchdog.start()
        try await AppDataReset.eraseAll(context: ctx, targets: targets)
        try await Task.sleep(nanoseconds: 300_000_000)
        let gap = watchdog.stop()

        let keychain = B01QA2.keychainCount(service: XtreamCredentialStore.standard.service)
        let names = B03QA.bytes(marker, storeURL)
        B03QA.log("BUG-09|\(B03QA.dbSummary(storeURL))|angekuendigt=\(announced == ids)|schluesselbund=\(keychain)|beiseitegelegt=\(FileManager.default.fileExists(atPath: setAside.path))|cache=\(cache.cachedResponse(for: URLRequest(url: cachedURL)) != nil)|einstellung=\(defaults.bool(forKey: "B03.qa"))|namenBytes=\(names)|blockade=\(B03QA.f2(gap))s")
        XCTAssertEqual(announced, ids, "Wiedergaben aller Playlists enden vorher")
        XCTAssertEqual(B03QA.dbSummary(storeURL), "ZPLAYLIST=0|ZCHANNEL=0|ohnePlaylist=0|favoriten=0")
        XCTAssertEqual(try ctx.fetchCount(FetchDescriptor<Playlist>()), 0)
        XCTAssertFalse(ctx.hasChanges)
        XCTAssertEqual(keychain, 0, "alle Schlüsselbund-Einträge des Dienstes")
        XCTAssertFalse(FileManager.default.fileExists(atPath: setAside.path), "beiseitegelegte Datenbanken")
        XCTAssertNil(cache.cachedResponse(for: URLRequest(url: cachedURL)), "HTTP-Cache")
        XCTAssertFalse(defaults.bool(forKey: "B03.qa"), "Einstellungen")
        XCTAssertTrue(PlaylistHTTPLoader.shared.cookies.isEmpty, "Cookies des Loaders")
        XCTAssertEqual(names, 0, "keine Bytes der Sendernamen in der Datei (verdichtet)")
        XCTAssertLessThan(gap, 0.5)
    }
}
