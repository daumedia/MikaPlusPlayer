import XCTest
import SwiftData
@testable import MikaPlusPlayer

/// B01 · QA-Durchlauf 2: Grenzwerte aus BUG-08 genau (64 MB, 100.000 Sender, 180 s) und Leistung mit 17.000 Sendern
/// (BUG-12). Nur Loopback-Mocks, erfundene Zugangsdaten, Temp-Dateien.
///
/// Die 180-s-Messung dauert gut drei Minuten und läuft nur mit `TEST_RUNNER_B01_QA2_FRIST=1`.
final class B01QA2GrenzenTests: B01MockTestCase {

    private static let mib = 1024 * 1024

    /// Gültige Anmeldeantwort, mit Leerzeichen (JSON-Whitespace) auf genau `size` Byte aufgefüllt.
    private func paddedAuth(size: Int) -> Data {
        var body = Data(#"{"user_info":{"auth":1,"status":"Active"}}"#.utf8)
        body.append(Data(repeating: 0x20, count: size - body.count))
        return body
    }

    // MARK: 64 MB

    /// BUG-08: Antwort mit genau 64 MiB (67.108.864 Byte) wird angenommen, ein Byte mehr abgelehnt – mit und ohne
    /// `Content-Length`. Abgelehnt: eigene Meldung, keine Playlist, kein Schlüsselbund-Eintrag.
    @MainActor func testQA2_BUG08_Antwortgroesse64MBGenau() async throws {
        let limit = XtreamClient.Limits.standard.maxResponseBytes
        XCTAssertEqual(limit, 64 * Self.mib)
        let container = try B01.inMemoryContainer()
        let panel = MockXtreamServer.panel()
        var results: [String] = []
        for (label, size, sized) in [("genau, mit Länge", limit, true), ("+1, mit Länge", limit + 1, true),
                                     ("genau, ohne Länge", limit, false), ("+1, ohne Länge", limit + 1, false)] {
            let body = paddedAuth(size: size)
            mock.handler = { req in
                req.action == nil ? (sized ? .raw(status: 200, contentType: "application/json", body: body) : .unsized(body: body)) : panel(req)
            }
            let start = Date()
            let r = await B01.importXtream(host: mock.hostPort, pass: "qa-pass-qa2-64mb", context: container.mainContext)
            let line = "\(label)|bytes=\(size)|\(B01.message(r) ?? "Import ok")|\(String(format: "%.1f", Date().timeIntervalSince(start)))s"
            results.append(line)
            print("B01QA2|64MB|\(line)")
            if size == limit {
                XCTAssertNil(B01.message(r), label)
            } else {
                XCTAssertEqual(B01.message(r), "Netzwerkfehler: Die Antwort des Anbieters ist zu groß (mehr als 64 MB).", label)
            }
        }
        XCTAssertEqual(try container.mainContext.fetchCount(FetchDescriptor<Playlist>()), 2)
        XCTAssertEqual(B01QA2.keychainCount(service: XtreamCredentialStore.standard.service), 2)
    }

    /// BUG-08, Angriff: gzip-Bombe. Das Panel schickt ~70 KB mit `Content-Encoding: gzip`, entpackt über 64 MB.
    /// `Content-Length` ist klein – greift die Grenze am entpackten Datenstrom?
    @MainActor func testQA2_BUG08_GzipBombe() async throws {
        let work = try B01QA2.tempDir("gzip")
        defer { try? FileManager.default.removeItem(at: work) }
        let plain = work.appendingPathComponent("auth.json")
        try paddedAuth(size: 70 * Self.mib).write(to: plain)
        let gz = B01QA2.run("/usr/bin/gzip", ["-k", "-9", plain.path], timeout: 120)
        XCTAssertEqual(gz.status, 0, gz.output)
        let compressed = try Data(contentsOf: URL(fileURLWithPath: plain.path + ".gz"))
        let raw = B01QA2RawServer { line in
            if line.contains("action=") { return B01QA2RawServer.http(body: B01QA2RawServer.panelBody(line)) }
            return B01QA2RawServer.http(headers: ["Content-Type": "application/json", "Content-Encoding": "gzip"], body: compressed)
        }
        try raw.start()
        defer { raw.stop() }
        let container = try B01.inMemoryContainer()
        let start = Date()
        let r = await B01.importXtream(host: raw.hostPort, pass: "qa-pass-qa2-gzip", context: container.mainContext)
        print("B01QA2|GZIP|komprimiert=\(compressed.count)|entpackt=\(70 * Self.mib)|\(B01.message(r) ?? "Import ok")|\(String(format: "%.1f", Date().timeIntervalSince(start)))s")
        XCTAssertEqual(B01.message(r), "Netzwerkfehler: Die Antwort des Anbieters ist zu groß (mehr als 64 MB).")
        XCTAssertEqual(try container.mainContext.fetchCount(FetchDescriptor<Playlist>()), 0)
    }

    // MARK: 100.000 Sender

    /// BUG-08: genau 100.000 Streams werden importiert (alle Sender gespeichert, Main-Thread-Blockade gemessen);
    /// 100.001 werden abgelehnt, ohne Playlist und ohne Schlüsselbund-Eintrag.
    @MainActor func testQA2_BUG08_Hunderttausend() async throws {
        XCTAssertEqual(XtreamClient.Limits.standard.maxStreams, 100_000)
        let container = try B01.inMemoryContainer()
        let panel = MockXtreamServer.panel()
        for n in [100_001, 100_000] {
            var streams: [[String: Any]] = []
            streams.reserveCapacity(n)
            for i in 0..<n { streams.append(["name": "S\(i)", "stream_id": i, "category_id": "\(i % 30)"]) }
            let body = try JSONSerialization.data(withJSONObject: streams)
            mock.handler = { req in req.action == "get_live_streams" ? .raw(status: 200, contentType: "application/json", body: body) : panel(req) }
            let watchdog = MainThreadWatchdog()
            watchdog.start()
            let start = Date()
            let r = await B01.importXtream(host: mock.hostPort, pass: "qa-pass-qa2-100k", context: container.mainContext)
            let elapsed = Date().timeIntervalSince(start)
            let gap = watchdog.stop()
            let channels = try container.mainContext.fetchCount(FetchDescriptor<Channel>())
            print("B01QA2|100K|streams=\(n)|bytes=\(body.count)|\(B01.message(r) ?? "Import ok")|gespeichert=\(channels)|gesamt=\(String(format: "%.2f", elapsed))s|maxMainThreadBlockade=\(String(format: "%.2f", gap))s")
            if n == 100_000 {
                XCTAssertNil(B01.message(r))
                XCTAssertEqual(try r.get().channelCount, 100_000)
                XCTAssertEqual(channels, 100_000)
                XCTAssertLessThan(gap, 0.5)
            } else {
                XCTAssertEqual(B01.message(r), "Die Senderliste ist zu groß (mehr als 100.000 Sender).")
                XCTAssertEqual(channels, 0)
                XCTAssertEqual(try container.mainContext.fetchCount(FetchDescriptor<Playlist>()), 0)
                XCTAssertEqual(B01QA2.keychainCount(service: XtreamCredentialStore.standard.service), 0)
            }
        }
    }

    // MARK: 180 s

    /// BUG-08 / EC-17: gemeinsame Frist von **180 s** mit dem Standardwert, drei Importe gleichzeitig:
    /// A tröpfelt die Anmeldung 9 × 19,5 s = 175,5 s → gelingt; B 9 × 20,56 s = 185 s → Abbruch bei 180 s;
    /// C Anmeldung 5 × 19 s = 95 s, danach Kategorien 5 × 19 s → Abbruch bei 180 s in der zweiten Anfrage.
    @MainActor func testQA2_BUG08_Frist180SekundenGenau() async throws {
        guard ProcessInfo.processInfo.environment["B01_QA2_FRIST"] == "1" else {
            throw XCTSkip("Laufzeit > 3 min: mit TEST_RUNNER_B01_QA2_FRIST=1 ausführen")
        }
        XCTAssertEqual(XtreamClient.Limits.standard.totalTimeout, 180)
        // Körperlängen genau durch die Stückzahl teilbar, damit die Mock-Stücke exakt `chunks` × `interval` dauern
        let auth = paddedAuth(size: 90)
        var cats = try JSONSerialization.data(withJSONObject: MockXtreamServer.categories)
        cats.append(Data(repeating: 0x20, count: (5 - cats.count % 5) % 5))
        let panel = MockXtreamServer.panel()
        let a = MockXtreamServer { req in req.action == nil ? .trickle(body: auth, chunks: 9, interval: 19.5) : panel(req) }
        let b = MockXtreamServer { req in req.action == nil ? .trickle(body: auth, chunks: 9, interval: 185.0 / 9) : panel(req) }
        let c = MockXtreamServer { req in
            switch req.action {
            case nil: return .trickle(body: auth, chunks: 5, interval: 19)
            case "get_live_categories": return .trickle(body: cats, chunks: 5, interval: 19)
            default: return panel(req)
            }
        }
        for s in [a, b, c] { try s.start() }
        defer { for s in [a, b, c] { s.stop() } }
        let container = try B01.inMemoryContainer()
        func run(_ server: MockXtreamServer, _ label: String) -> Task<String, Never> {
            let host = server.hostPort
            return Task { @MainActor in
                let start = Date()
                let r = await B01.importXtream(host: host, pass: "qa-pass-qa2-frist", context: container.mainContext)
                return "\(label)|\(String(format: "%.1f", Date().timeIntervalSince(start)))s|\(B01.message(r) ?? "Import ok")"
            }
        }
        let ta = run(a, "A 175,5 s"), tb = run(b, "B 185 s"), tc = run(c, "C 95+95 s")
        let ra = await ta.value, rb = await tb.value, rc = await tc.value
        for line in [ra, rb, rc] { print("B01QA2|FRIST|\(line)") }
        print("B01QA2|FRIST|C-anfragen=\(c.requests.map { $0.action ?? "(ohne)" })")
        XCTAssertTrue(ra.hasSuffix("Import ok"), ra)
        let deadlineMessage = "Netzwerkfehler: Der Anbieter hat nicht innerhalb von 180 Sekunden vollständig geantwortet."
        XCTAssertTrue(rb.hasSuffix(deadlineMessage), rb)
        XCTAssertTrue(rc.hasSuffix(deadlineMessage), rc)
        for line in [rb, rc] {
            let seconds = Double(line.split(separator: "|")[1].dropLast().replacingOccurrences(of: ",", with: ".")) ?? 0
            XCTAssertGreaterThanOrEqual(seconds, 179.5, line)
            XCTAssertLessThan(seconds, 182, line)
        }
        XCTAssertEqual(c.requests.map { $0.action ?? "(ohne)" }, ["(ohne)", "get_live_categories"])
        XCTAssertEqual(try container.mainContext.fetchCount(FetchDescriptor<Playlist>()), 1)
    }

    // MARK: 17.000 Sender

    /// BUG-12 / EC-20, erneut gemessen: 17.000 Sender über den echten Pfad – einmal mit In-Memory-Store (wie Durchlauf 1),
    /// einmal mit Store-Datei (wie die App). Gesamtzeit und längste Blockade des Main-Threads.
    @MainActor func testQA2_BUG12_SiebzehntausendSender() async throws {
        let n = 17_000
        var streams: [[String: Any]] = []
        for i in 0..<n {
            streams.append(["name": "Sender \(i)", "stream_id": i, "category_id": "\(i % 40)",
                            "stream_icon": "http://logos.example/\(i).png", "epg_channel_id": "sender.\(i)"])
        }
        let body = try JSONSerialization.data(withJSONObject: streams)
        let panel = MockXtreamServer.panel()
        mock.handler = { req in req.action == "get_live_streams" ? .raw(status: 200, contentType: "application/json", body: body) : panel(req) }
        for variant in ["inMemory", "storeDatei"] {
            let container: ModelContainer
            var folder: URL?
            if variant == "inMemory" {
                container = try B01.inMemoryContainer()
            } else {
                let (c, _, d) = try B01.tempFileContainer("qa2-17k")
                container = c
                folder = d
            }
            let watchdog = MainThreadWatchdog()
            watchdog.start()
            let start = Date()
            let p = try await B01.importXtream(host: mock.hostPort, pass: "qa-pass-qa2-17k", context: container.mainContext).get()
            let elapsed = Date().timeIntervalSince(start)
            try await Task.sleep(nanoseconds: 300_000_000)
            let gap = watchdog.stop()
            print("B01QA2|17K|\(variant)|sender=\(p.channelCount)|gesamt=\(String(format: "%.2f", elapsed))s|maxMainThreadBlockade=\(String(format: "%.2f", gap))s")
            XCTAssertEqual(p.channelCount, n)
            XCTAssertLessThan(gap, 0.5)
            XCTAssertLessThan(elapsed, 30)
            if let folder { try? FileManager.default.removeItem(at: folder) }
        }
    }

    /// Hinweis für B03 (nicht Teil von B01): Aktualisieren derselben Xtream-Playlist läuft weiter auf dem Main-Actor
    /// (`attach`). Gemessen mit 3.000 Sendern.
    @MainActor func testQA2_HinweisB03_AktualisierenBlockiertMainThread() async throws {
        let n = 3_000
        let streams: [[String: Any]] = (0..<n).map { ["name": "Sender \($0)", "stream_id": $0] }
        let body = try JSONSerialization.data(withJSONObject: streams)
        let panel = MockXtreamServer.panel()
        mock.handler = { req in req.action == "get_live_streams" ? .raw(status: 200, contentType: "application/json", body: body) : panel(req) }
        let container = try B01.inMemoryContainer()
        let p = try await B01.importXtream(host: mock.hostPort, pass: "qa-pass-qa2-ref", context: container.mainContext).get()
        let watchdog = MainThreadWatchdog()
        watchdog.start()
        let start = Date()
        try await PlaylistImporter(modelContext: container.mainContext, loginThrottle: XtreamLoginThrottle()).refresh(p)
        let elapsed = Date().timeIntervalSince(start)
        try await Task.sleep(nanoseconds: 300_000_000)
        let gap = watchdog.stop()
        print("B01QA2|B03-HINWEIS|aktualisieren|sender=\(n)|gesamt=\(String(format: "%.2f", elapsed))s|maxMainThreadBlockade=\(String(format: "%.2f", gap))s")
        XCTAssertEqual(p.channelCount, n)
    }
}
