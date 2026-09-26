import XCTest
import Foundation
import Network
import SwiftData
import AppKit
import SQLite3
import Darwin
@testable import MikaPlusPlayer

// B02 · M3U-Import — gemeinsame Hilfen der QA (Durchlauf 1, 2026-09-16).
//
// Regeln für alle B02-Tests:
// - Datenbanken nur in-memory oder als Datei im Temp-Verzeichnis (Produktionsweg `AppPersistence.diskContainer`).
//   Der Test-Host selbst arbeitet im Speicher; die Datenbank des Nutzers wird nie geöffnet.
// - HTTP nur gegen `B02Server` auf 127.0.0.1. Erfundene Zugangsdaten (`qa-user` / `qa-pass-b02…`).
// - Der HTTP-Plattencache des Test-Hosts wäre der Cache der echten App (`~/Library/Caches/<Bundle-ID>`). Jeder Test
//   ersetzt deshalb `URLCache.shared` durch einen Cache im Temp-Ordner (vorab geprüft: `URLSession.shared` schreibt
//   danach dorthin, auch nach früherer Nutzung) und entfernt zur Sicherheit die eigenen Schlüssel im Original-Cache.
// - Cookies der Tests heißen `b02qa…`, sind Sitzungs-Cookies (landen nicht auf der Platte) und werden am Ende gelöscht.
// - Tonlos: Stream-Adressen zeigen auf den geschlossenen Port 9, es wird nichts abgespielt, keine Tastaturereignisse.

enum B02 {
    static let dead = "http://127.0.0.1:9"

    static func log(_ s: String) { print("B02QA|\(s)") }
    static func f2(_ t: TimeInterval) -> String { String(format: "%.2f", t) }

    #if DEBUG
    static let buildConfiguration = "Debug"
    #else
    static let buildConfiguration = "Release"
    #endif

    // MARK: Listen

    /// Zwei gültige Sender („Kanal A" mit tvg-id/Gruppe, „Kanal B" ohne).
    static let zweiSender = """
    #EXTM3U
    #EXTINF:-1 tvg-id="a" group-title="News",Kanal A
    \(dead)/live/a.m3u8
    #EXTINF:-1,Kanal B
    \(dead)/live/b.ts

    """
    static var zweiSenderData: Data { Data(zweiSender.utf8) }

    /// `n` Sender im üblichen Anbieterformat (≈ 150 Byte je Eintrag).
    static func grosseListe(_ n: Int, tag: String = "") -> Data {
        var s = "#EXTM3U\n"
        s.reserveCapacity(n * 160)
        for i in 0..<n {
            s += "#EXTINF:-1 tvg-id=\"sender.\(i)\" tvg-logo=\"\(dead)/logos/\(i).png\" group-title=\"Gruppe \(i % 40)\",Sender \(tag)\(i)\n"
            s += "\(dead)/live/\(i).ts\n"
        }
        return Data(s.utf8)
    }

    // MARK: Datenbank

    @MainActor static func memory() throws -> ModelContainer {
        let schema = AppSchema.schema
        return try ModelContainer(for: schema, configurations: [ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)])
    }

    static func tempDir(_ label: String) throws -> URL {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("b02-qa-\(label)-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    /// Store-Datei im Temp-Ordner über den Produktionsweg (`AppPersistence.diskContainer`, versioniertes Schema).
    @MainActor static func fileContainer(in dir: URL) throws -> (ModelContainer, URL) {
        let url = dir.appendingPathComponent("b02-qa.store")
        return (try AppPersistence.diskContainer(at: url, schema: AppSchema.schema), url)
    }

    // MARK: Importe über den echten Pfad

    @MainActor static func importURL(_ input: String, name: String = "", _ ctx: ModelContext) async -> Result<Playlist, Error> {
        do { return .success(try await PlaylistImporter(modelContext: ctx).importFromURL(input, name: name)) } catch { return .failure(error) }
    }

    @MainActor static func importFile(_ url: URL, name: String? = nil, _ ctx: ModelContext) async -> Result<Playlist, Error> {
        do { return .success(try await PlaylistImporter(modelContext: ctx).importFromFile(url, name: name)) } catch { return .failure(error) }
    }

    /// Meldung wie im Alert des Sheets (`error.localizedDescription`); `nil` bei Erfolg.
    static func message(_ r: Result<Playlist, Error>) -> String? {
        if case .failure(let e) = r { return e.localizedDescription }
        return nil
    }

    @MainActor static func count<T: PersistentModel>(_ type: T.Type, _ ctx: ModelContext) -> Int {
        (try? ctx.fetchCount(FetchDescriptor<T>())) ?? -1
    }

    /// Kurzbeschreibung eines Senders für das Protokoll.
    @MainActor static func describe(_ p: Playlist) -> String {
        let sender = p.channels.sorted { $0.name < $1.name }.prefix(5).map {
            "{\($0.name.debugDescription) gruppe=\($0.group?.debugDescription ?? "nil") tvg=\($0.tvgID?.debugDescription ?? "nil") url=\($0.streamURL.absoluteString.prefix(120)) logo=\($0.logoURL?.absoluteString.prefix(80) ?? "nil")}"
        }.joined(separator: " ")
        return "name=\(p.name.debugDescription)|sourceURL=\(p.sourceURL?.absoluteString.prefix(160) ?? "nil")|isRemote=\(p.isRemote)|isXtream=\(p.isXtream)|channelCount=\(p.channelCount)|lastRefreshed=\(p.lastRefreshed == nil ? "nil" : "gesetzt")|\(sender)"
    }

    // MARK: SQLite und Bytes (nur Test-Dateien)

    static func rows(_ path: String, _ sql: String) -> [[String]] {
        var db: OpaquePointer?
        guard sqlite3_open_v2(path, &db, SQLITE_OPEN_READONLY, nil) == SQLITE_OK else { sqlite3_close(db); return [] }
        defer { sqlite3_close(db) }
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return [["SQL-FEHLER"]] }
        defer { sqlite3_finalize(stmt) }
        var out: [[String]] = []
        while sqlite3_step(stmt) == SQLITE_ROW {
            out.append((0..<sqlite3_column_count(stmt)).map { i in
                sqlite3_column_text(stmt, i).map { String(cString: $0) } ?? "NULL"
            })
        }
        return out
    }

    static func int(_ path: String, _ sql: String) -> Int { Int(rows(path, sql).first?.first ?? "") ?? -1 }

    /// Vorkommen einer Bytefolge in Store, -wal, -shm.
    static func bytes(_ marker: String, _ storeURL: URL) -> [String: Int] {
        B01.rawOccurrences(of: marker, inFilesWithPrefix: storeURL)
    }

    static func footprintMB() -> Double {
        var info = task_vm_info_data_t()
        var count = mach_msg_type_number_t(MemoryLayout<task_vm_info_data_t>.size / MemoryLayout<integer_t>.size)
        let kr = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                task_info(mach_task_self_, task_flavor_t(TASK_VM_INFO), $0, &count)
            }
        }
        return kr == KERN_SUCCESS ? Double(info.phys_footprint) / 1_048_576 : -1
    }

    // MARK: Belege

    /// `features/B02-m3u-import/qa/` im Repository.
    static var qaFolder: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("features/B02-m3u-import/qa", isDirectory: true)
    }

    static func evidence(_ file: String, _ line: String) {
        log(line)
        let url = qaFolder.appendingPathComponent(file)
        try? FileManager.default.createDirectory(at: qaFolder, withIntermediateDirectories: true)
        let data = Data((line + "\n").utf8)
        if let h = try? FileHandle(forWritingTo: url) {
            h.seekToEndOfFile(); h.write(data); try? h.close()
        } else {
            try? data.write(to: url)
        }
    }
}

// MARK: - Loopback-HTTP-Server

/// HTTP-Server auf 127.0.0.1 mit frei gebauten Antworten. Schreibt jede Anfrage **roh** mit (Request-Zeile, alle
/// Kopfzeilen in Originalreihenfolge und -schreibweise) und zählt auch Verbindungen, die nie eine HTTP-Anfrage senden.
final class B02Server: @unchecked Sendable {
    struct Request: Sendable {
        let requestLine: String
        let method: String
        let target: String
        let path: String
        let query: String?
        let headers: [(name: String, value: String)]
        let port: UInt16
        let received: Date

        func header(_ name: String) -> String? {
            headers.first { $0.name.lowercased() == name.lowercased() }?.value
        }
        var headerNames: [String] { headers.map { $0.name.lowercased() }.sorted() }
    }

    indirect enum Reply: Sendable {
        /// vollständige Antwort (Bytes), danach Verbindung schließen
        case bytes(Data)
        /// Verbindung offen lassen, nie antworten
        case hang
        /// Kopf sofort, Körper in `chunks` Stücken im Abstand `interval`
        case trickle(head: Data, body: Data, chunks: Int, interval: TimeInterval)
        case delayed(TimeInterval, Reply)
    }

    static func http(_ status: Int, reason: String = "QA", headers: [(String, String)] = [], body: Data = Data()) -> Data {
        var head = "HTTP/1.1 \(status) \(reason)\r\n"
        for (k, v) in headers { head += "\(k): \(v)\r\n" }
        head += "Content-Length: \(body.count)\r\nConnection: close\r\n\r\n"
        var d = Data(head.utf8)
        d.append(body)
        return d
    }

    static func ok(_ body: Data, type: String = "audio/x-mpegurl", headers: [(String, String)] = []) -> Reply {
        .bytes(http(200, reason: "OK", headers: [("Content-Type", type)] + headers, body: body))
    }

    static func status(_ code: Int, headers: [(String, String)] = [], body: Data = Data()) -> Reply {
        .bytes(http(code, headers: headers, body: body))
    }

    static func redirect(_ code: Int, to location: String) -> Reply {
        .bytes(http(code, reason: "Redirect", headers: [("Location", location)]))
    }

    private let queue = DispatchQueue(label: "b02qa.server")
    private let lock = NSLock()
    private var listener: NWListener?
    private var open: [ObjectIdentifier: NWConnection] = [:]
    private var _requests: [Request] = []
    private var _connections = 0
    private var _handler: @Sendable (Request) -> Reply
    private(set) var port: UInt16 = 0

    init(handler: @escaping @Sendable (Request) -> Reply = { _ in B02Server.ok(B02.zweiSenderData) }) {
        _handler = handler
    }

    var handler: @Sendable (Request) -> Reply {
        get { lock.withLock { _handler } }
        set { lock.withLock { _handler = newValue } }
    }
    var requests: [Request] { lock.withLock { _requests } }
    var connectionCount: Int { lock.withLock { _connections } }
    var hostPort: String { "127.0.0.1:\(port)" }
    func url(_ path: String) -> String { "http://\(hostPort)\(path)" }
    func resetLog() { lock.withLock { _requests.removeAll(); _connections = 0 } }

    func start() throws {
        let params = NWParameters.tcp
        params.requiredLocalEndpoint = .hostPort(host: "127.0.0.1", port: .any)
        params.allowLocalEndpointReuse = true
        let listener = try NWListener(using: params)
        let ready = DispatchSemaphore(value: 0)
        listener.stateUpdateHandler = { state in
            switch state {
            case .ready, .failed: ready.signal()
            default: break
            }
        }
        listener.newConnectionHandler = { [weak self] c in self?.accept(c) }
        listener.start(queue: queue)
        _ = ready.wait(timeout: .now() + 5)
        self.listener = listener
        port = listener.port?.rawValue ?? 0
        if port == 0 { throw NSError(domain: "B02Server", code: 1, userInfo: [NSLocalizedDescriptionKey: "Listener nicht bereit"]) }
    }

    func stop() {
        listener?.cancel()
        listener = nil
        let conns = lock.withLock { () -> [NWConnection] in let c = Array(open.values); open.removeAll(); return c }
        conns.forEach { $0.cancel() }
    }

    private func accept(_ c: NWConnection) {
        lock.withLock { open[ObjectIdentifier(c)] = c; _connections += 1 }
        c.start(queue: queue)
        receive(c, buffer: Data())
    }

    private func receive(_ c: NWConnection, buffer: Data) {
        c.receive(minimumIncompleteLength: 1, maximumLength: 65_536) { [weak self] data, _, complete, error in
            guard let self else { return }
            var buf = buffer
            if let data { buf.append(data) }
            if let end = buf.range(of: Data("\r\n\r\n".utf8)) {
                self.handle(c, head: buf.subdata(in: buf.startIndex..<end.lowerBound))
            } else if complete || error != nil {
                self.close(c)
            } else {
                self.receive(c, buffer: buf)
            }
        }
    }

    private func handle(_ c: NWConnection, head: Data) {
        let text = String(decoding: head, as: UTF8.self)
        var lines = text.components(separatedBy: "\r\n")
        let line = lines.isEmpty ? "" : lines.removeFirst()
        let parts = line.split(separator: " ", omittingEmptySubsequences: false).map(String.init)
        let target = parts.count > 1 ? parts[1] : ""
        var headers: [(String, String)] = []
        for l in lines {
            guard let i = l.firstIndex(of: ":") else { continue }
            headers.append((String(l[..<i]), l[l.index(after: i)...].trimmingCharacters(in: .whitespaces)))
        }
        let path: String
        let query: String?
        if let q = target.firstIndex(of: "?") {
            path = String(target[..<q]); query = String(target[target.index(after: q)...])
        } else {
            path = target; query = nil
        }
        let req = Request(requestLine: line, method: parts.first ?? "", target: target, path: path, query: query,
                          headers: headers.map { (name: $0.0, value: $0.1) }, port: port, received: Date())
        lock.withLock { _requests.append(req) }
        respond(c, handler(req))
    }

    private func respond(_ c: NWConnection, _ reply: Reply) {
        switch reply {
        case .hang:
            return
        case .delayed(let s, let inner):
            queue.asyncAfter(deadline: .now() + s) { [weak self] in self?.respond(c, inner) }
        case .bytes(let d):
            c.send(content: d, completion: .contentProcessed { [weak self] _ in self?.close(c) })
        case .trickle(let head, let body, let chunks, let interval):
            c.send(content: head, completion: .contentProcessed { _ in })
            let size = max(1, Int((Double(body.count) / Double(max(chunks, 1))).rounded(.up)))
            trickle(c, body: body, offset: 0, size: size, interval: interval)
        }
    }

    private func trickle(_ c: NWConnection, body: Data, offset: Int, size: Int, interval: TimeInterval) {
        guard offset < body.count else {
            queue.asyncAfter(deadline: .now() + 1) { [weak self] in self?.close(c) }
            return
        }
        queue.asyncAfter(deadline: .now() + interval) { [weak self] in
            guard let self, self.lock.withLock({ self.open[ObjectIdentifier(c)] != nil }) else { return }
            let end = min(body.count, offset + size)
            c.send(content: body.subdata(in: (body.startIndex + offset)..<(body.startIndex + end)), completion: .contentProcessed { _ in })
            self.trickle(c, body: body, offset: end, size: size, interval: interval)
        }
    }

    private func close(_ c: NWConnection) {
        lock.withLock { _ = open.removeValue(forKey: ObjectIdentifier(c)) }
        c.cancel()
    }
}

// MARK: - Basisklasse

/// Startet je Test einen frischen Server, lenkt den HTTP-Plattencache in einen Temp-Ordner um und räumt danach auf.
class B02TestCase: XCTestCase {
    var server: B02Server!
    /// Weitere Server eines Tests (z. B. Weiterleitungsziel); werden im `tearDown` gestoppt.
    var extraServers: [B02Server] = []
    var probeCache: URLCache!
    var cacheDir: URL!
    var dirs: [URL] = []
    private var originalCache: URLCache?

    override func setUpWithError() throws {
        try super.setUpWithError()
        server = B02Server()
        try server.start()
        cacheDir = try B02.tempDir("urlcache")
        dirs.append(cacheDir)
        originalCache = URLCache.shared
        probeCache = URLCache(memoryCapacity: 512_000, diskCapacity: 20_000_000, directory: cacheDir)
        URLCache.shared = probeCache
    }

    override func tearDown() {
        let servers = [server].compactMap { $0 } + extraServers
        for s in servers {
            // Sicherheitsnetz: eigene Schlüssel auch im Original-Cache (= Cache der App) entfernen
            for r in s.requests {
                for host in ["127.0.0.1", "localhost"] {
                    if let u = URL(string: "http://\(host):\(s.port)\(r.target)") {
                        originalCache?.removeCachedResponse(for: URLRequest(url: u))
                    }
                }
            }
            s.stop()
        }
        if let originalCache { URLCache.shared = originalCache }
        for cookie in HTTPCookieStorage.shared.cookies ?? [] where cookie.name.hasPrefix("b02qa") {
            HTTPCookieStorage.shared.deleteCookie(cookie)
        }
        // Nur eigene, erfundene Zugangsdaten (Benutzer `qa-…`) entfernen — nie fremde Einträge.
        let storage = URLCredentialStorage.shared
        for (space, creds) in storage.allCredentials where ["127.0.0.1", "localhost"].contains(space.host) {
            for (user, c) in creds where user.hasPrefix("qa-") { storage.remove(c, for: space) }
        }
        for d in dirs { try? FileManager.default.removeItem(at: d) }
        dirs = []
        extraServers = []
        server = nil
        super.tearDown()
    }

    func tempDir(_ label: String) throws -> URL {
        let d = try B02.tempDir(label)
        dirs.append(d)
        return d
    }

    func extraServer(_ handler: @escaping @Sendable (B02Server.Request) -> B02Server.Reply) throws -> B02Server {
        let s = B02Server(handler: handler)
        try s.start()
        extraServers.append(s)
        return s
    }

    /// Wie viele Plattencache-Einträge (API) haben diese Adressen im umgelenkten Cache?
    func cachedCount(_ urls: [String]) -> Int {
        urls.compactMap(URL.init(string:)).filter { probeCache.cachedResponse(for: URLRequest(url: $0)) != nil }.count
    }

    @MainActor func waitFor<T>(_ what: String, timeout: TimeInterval = 5, _ probe: () -> T?) async throws -> T {
        let end = Date().addingTimeInterval(timeout)
        while Date() < end {
            if let v = probe() { return v }
            try await Task.sleep(nanoseconds: 50_000_000)
        }
        throw NSError(domain: "B02QA", code: 1, userInfo: [NSLocalizedDescriptionKey: "Zeitüberschreitung: \(what)"])
    }
}
