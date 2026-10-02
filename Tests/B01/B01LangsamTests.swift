import XCTest
import SwiftData
@testable import MikaPlusPlayer

/// B01 · Xtream-Codes-Login — langsame Fälle mit echten Wartezeiten (Timeout, Tröpfeln, große Liste). QA 2026-09-15.
/// Laufzeit zusammen rund drei Minuten.
final class B01LangsamTests: B01MockTestCase {

    /// AK-20 (c) + AK-23: Verbindung steht, 60 s keine Daten → „Netzwerkfehler: The request timed out.", ohne Zugangsdaten.
    @MainActor func testAK20_AK23_TimeoutNach60Sekunden() async throws {
        mock.handler = { _ in .hang }
        let container = try B01.inMemoryContainer()
        let start = Date()
        let r = await B01.importXtream(host: mock.hostPort, user: "qa-user-ak20", pass: "qa-pass-ak20",
                                       context: container.mainContext)
        let elapsed = Date().timeIntervalSince(start)
        let msg = B01.message(r) ?? "ok"
        print("B01QA|AK-20|timeout|\(String(format: "%.1f", elapsed))s|\(msg)")
        XCTAssertEqual(SystemSprache.englisch(msg), "Netzwerkfehler: The request timed out.")  // B09 · OF-01: Systemtext englisch oder deutsch
        XCTAssertGreaterThanOrEqual(elapsed, 59.5)
        XCTAssertLessThan(elapsed, 75)
        XCTAssertFalse(msg.contains("qa-pass-ak20") || msg.contains("qa-user-ak20") || msg.contains("player_api"))
        XCTAssertEqual(try container.mainContext.fetchCount(FetchDescriptor<Playlist>()), 0)
    }

    /// EC-17 / BUG-08 behoben: Ein Panel, das die Anmeldeantwort in Stücken alle 10 s tröpfelt, wird von der
    /// Gesamtfrist des Imports gestoppt, obwohl die 60-s-Leerlaufgrenze nie greift. Standardfrist 180 s; im Test
    /// auf 25 s verkürzt, damit das Tröpfeln (7 × 10 s = 70 s) sicher darüber liegt.
    @MainActor func testEC17_TroepfelndesPanelWirdVonGesamtfristGestoppt() async throws {
        XCTAssertEqual(XtreamClient.Limits.standard.totalTimeout, 180)
        let authBody = try JSONSerialization.data(withJSONObject: ["user_info": ["auth": 1, "status": "Active"]])
        let panel = MockXtreamServer.panel()
        mock.handler = { req in
            req.action == nil ? .trickle(body: authBody, chunks: 7, interval: 10) : panel(req)
        }
        var limits = XtreamClient.Limits.standard
        limits.totalTimeout = 25
        let container = try B01.inMemoryContainer()
        let start = Date()
        let r = await B01.importXtream(host: mock.hostPort, pass: "qa-pass-ec17", context: container.mainContext, limits: limits)
        let elapsed = Date().timeIntervalSince(start)
        print("B01BUILD|EC-17|trickle|bytes=\(authBody.count)|\(String(format: "%.1f", elapsed))s|\(B01.message(r) ?? "Import ok")|anfragen=\(mock.requests.map { $0.action ?? "(ohne)" })")
        XCTAssertEqual(B01.message(r), "Netzwerkfehler: Der Anbieter hat nicht innerhalb von 25 Sekunden vollständig geantwortet.")
        XCTAssertGreaterThanOrEqual(elapsed, 24.5)
        XCTAssertLessThan(elapsed, 35, "Gesamtfrist muss greifen")
        XCTAssertEqual(try container.mainContext.fetchCount(FetchDescriptor<Playlist>()), 0)
    }

    /// EC-20 / BUG-12 behoben: Sender werden abseits des Main-Actors in Blöcken angelegt. Gemessen wird die längste
    /// Blockade des Main-Threads und die Gesamtdauer für 1 500, 3 000 und 6 000 Sender (Wachstum).
    /// Vorher (qa-report.md): 17 000 Sender → 285 s Blockade. Einzelmessung: TEST_RUNNER_B01_QA_EC20_SIZES=17000
    @MainActor func testEC20_GrosseSenderlisteBlockiertMainThreadNicht() async throws {
        var gaps: [Int: TimeInterval] = [:]
        var totals: [Int: TimeInterval] = [:]
        // Standardgrößen; für die Einzelmessung im Bericht: TEST_RUNNER_B01_QA_EC20_SIZES=17000
        let sizes = (ProcessInfo.processInfo.environment["B01_QA_EC20_SIZES"] ?? "")
            .split(separator: ",").compactMap { Int($0) }
        for n in (sizes.isEmpty ? [1_500, 3_000, 6_000] : sizes) {
            var streams: [[String: Any]] = []
            for i in 0..<n {
                streams.append(["name": "Sender \(i)", "stream_id": i, "category_id": "\(i % 40)",
                                "stream_icon": "http://logos.example/\(i).png", "epg_channel_id": "sender.\(i)"])
            }
            let body = try JSONSerialization.data(withJSONObject: streams)
            let panel = MockXtreamServer.panel()
            mock.handler = { req in
                req.action == "get_live_streams" ? .raw(status: 200, contentType: "application/json", body: body) : panel(req)
            }
            let container = try B01.inMemoryContainer()
            let watchdog = MainThreadWatchdog()
            watchdog.start()
            let start = Date()
            let p = try await B01.importXtream(host: mock.hostPort, pass: "qa-pass-ec20", context: container.mainContext).get()
            let elapsed = Date().timeIntervalSince(start)
            try await Task.sleep(nanoseconds: 300_000_000)
            let maxGap = watchdog.stop()
            gaps[n] = maxGap
            totals[n] = elapsed
            let pid = p.id
            let stored = try container.mainContext.fetchCount(FetchDescriptor<Channel>(predicate: #Predicate { $0.playlistID == pid }))
            print("B01BUILD|EC-20|sender=\(p.channelCount)|bytes=\(body.count)|gesamt=\(String(format: "%.2f", elapsed))s|maxMainThreadBlockade=\(String(format: "%.2f", maxGap))s|playlistID=\(stored)|beziehung=\(p.channels.count)")
            XCTAssertEqual(p.channelCount, n)
            XCTAssertEqual(stored, n, "Channel.playlistID muss stimmen")
            XCTAssertEqual(p.channels.count, n, "Beziehung Playlist.channels muss stimmen")
        }
        for (n, gap) in gaps {
            XCTAssertLessThan(gap, 0.5, "Die Oberfläche darf beim Import nicht einfrieren (\(n) Sender)")
        }
        if let t3 = totals[3_000], let t6 = totals[6_000] {
            // linear statt quadratisch: doppelte Menge ≈ doppelte Zeit (großzügig, mit Grundlast)
            XCTAssertLessThan(t6, 3 * t3 + 1.0, "Aufwand wächst überproportional")
        }
    }
}

extension B01LangsamTests {
    /// BUG-01: Umstellung einer vorhandenen Datenbank mit 17 000 Xtream-Sendern beim ersten Start (läuft synchron vor der
    /// Oberfläche). Misst die Dauer und prüft, dass danach kein Klartext mehr in Store/-wal/-shm steht.
    @MainActor func testBUG01_MigrationMit17000Sendern() async throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("b01-build-mig17k-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let url = dir.appendingPathComponent("legacy.store")
        let store = XtreamCredentialStore(service: "lu.daumedia.MikaPlusPlayer.b01-build-tests.\(UUID().uuidString)")
        defer { try? store.deleteAll() }
        let marker = "qa-pass-mig17k-\(UInt32.random(in: 1000...9999))"
        let count = 17_000
        do {
            let container = try ModelContainer(for: B01.schema, configurations: [ModelConfiguration(schema: B01.schema, url: url)])
            let ctx = ModelContext(container)
            let playlist = Playlist(name: "Alt", sourceURL: URL(string: "http://127.0.0.1:18765/player_api.php?username=qa-user&password=\(marker)"),
                                    isXtream: true, xtreamOutput: "mpegts", channelCount: count)
            ctx.insert(playlist)
            var channels: [Channel] = []
            for i in 0..<count {
                let c = Channel(name: "Sender \(i)", streamURL: URL(string: "http://127.0.0.1:18765/live/qa-user/\(marker)/\(i).ts")!,
                                tvgID: "s.\(i)", isFavorite: i % 1000 == 0, playlistID: playlist.id)
                ctx.insert(c)
                channels.append(c)
            }
            playlist.channels = channels
            try ctx.save()
        }
        try await Task.sleep(nanoseconds: 1_500_000_000)
        let container = try ModelContainer(for: B01.schema, configurations: [ModelConfiguration(schema: B01.schema, url: url)])
        let start = Date()
        let result = AppPersistence.migrateCredentials(container: container, storeURL: url, store: store)
        let elapsed = Date().timeIntervalSince(start)
        let raw = B01.rawOccurrences(of: marker, inFilesWithPrefix: url)
        let favorites = try container.mainContext.fetchCount(FetchDescriptor<Channel>(predicate: #Predicate { $0.isFavorite == true }))
        print("B01BUILD|MIGRATION-17000|\(result)|dauer=\(String(format: "%.2f", elapsed))s|rawBytes=\(raw)|favoriten=\(favorites)")
        XCTAssertEqual(result.migratedPlaylists, 1)
        XCTAssertEqual(result.rewrittenChannels, count)
        XCTAssertEqual(raw.values.reduce(0, +), 0)
        XCTAssertEqual(favorites, 17)
        XCTAssertLessThan(elapsed, 30)
        // Die Daten sind nach dem Verdichten weiter über den offenen Container lesbar
        let channels = try container.mainContext.fetchCount(FetchDescriptor<Channel>())
        let playlist = try XCTUnwrap(try container.mainContext.fetch(FetchDescriptor<Playlist>()).first)
        XCTAssertEqual(channels, count)
        XCTAssertEqual(playlist.channels.count, count)
        XCTAssertEqual(playlist.channels.first?.streamURL.absoluteString.contains(marker), false)
    }
}

/// Misst, wie lange der Main-Thread höchstens nicht auf `DispatchQueue.main.async` reagiert.
final class MainThreadWatchdog: @unchecked Sendable {
    private let lock = NSLock()
    private var running = true
    private var maxGap: TimeInterval = 0

    func start() {
        Thread.detachNewThread { [self] in
            while lock.withLock({ running }) {
                let sent = Date()
                let done = DispatchSemaphore(value: 0)
                DispatchQueue.main.async {
                    let gap = Date().timeIntervalSince(sent)
                    self.lock.withLock { self.maxGap = max(self.maxGap, gap) }
                    done.signal()
                }
                _ = done.wait(timeout: .now() + 120)
                Thread.sleep(forTimeInterval: 0.02)
            }
        }
    }

    func stop() -> TimeInterval {
        lock.withLock { running = false; return maxGap }
    }
}
