import Foundation
import Network
import XCTest
import SwiftUI
import SwiftData
import AppKit
import AVFoundation
import ObjectiveC
@testable import MikaPlusPlayer

// B08 · Multiview — gemeinsame Hilfen der QA (Durchlauf 1, 2026-09-26).
//
// Kein Ton, doppelt abgesichert:
// 1. Alle Testmedien entstehen mit `ffmpeg -an` und werden vor der ersten Wiedergabe mit `ffprobe` geprüft
//    (0 Audiospuren, sonst Abbruch). Der Mock liefert ausschließlich diese Dateien.
// 2. Jede Engine, die ein Test (direkt oder über den ⊞-Button) entstehen lässt, bekommt sofort Lautstärke 0
//    (`setVolume(0)` bzw. `AVPlayer.volume = 0`). Das ändert `isMuted` nicht – der Ton-Fokus bleibt prüfbar.
// Tastenereignisse nur mit aktivem Beep-Wächter (ersetzt `noResponderFor:`, den Weg zu `NSBeep`).
// Streams ausschließlich von 127.0.0.1 (`B08StreamServer`), Zugangsdaten erfunden (qa-user / qa-pass-123).

enum B08QA {
    static let user = "qa-user"
    static let pass = "qa-pass-123"

    static func log(_ s: String) {
        print("B08QA|\(stamp())|\(s)")
        fflush(stdout)
        appendEvidence("testlauf.log", "\(stamp())|\(s)")
    }

    static func stamp() -> String {
        let f = DateFormatter()
        f.dateFormat = "HH:mm:ss.SSS"
        return f.string(from: Date())
    }

    static func f1(_ t: TimeInterval) -> String { String(format: "%.1f", t) }
    static func f2(_ t: Double) -> String { String(format: "%.2f", t) }

    /// `features/B08-multiview/qa/` neben den Tests (in der QA-Kopie; wird danach ins Repository übernommen).
    static var qaFolder: URL {
        if let custom = ProcessInfo.processInfo.environment["B08_QA_EVIDENCE"], !custom.isEmpty {
            return URL(fileURLWithPath: custom, isDirectory: true)
        }
        return URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("features/B08-multiview/qa", isDirectory: true)
    }

    static func appendEvidence(_ file: String, _ line: String) {
        let url = qaFolder.appendingPathComponent(file)
        try? FileManager.default.createDirectory(at: qaFolder, withIntermediateDirectories: true)
        let data = Data((line + "\n").utf8)
        if let h = try? FileHandle(forWritingTo: url) {
            h.seekToEndOfFile(); h.write(data); try? h.close()
        } else {
            try? data.write(to: url)
        }
    }

    static func spin(_ seconds: TimeInterval) async {
        try? await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
    }

    @MainActor
    static func inMemoryContainer() throws -> ModelContainer {
        let schema = Schema([Playlist.self, Channel.self])
        return try ModelContainer(for: schema, configurations: [ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)])
    }

    /// Store-Datei im eigenen Temp-Ordner (für SQLite-Nachzählungen).
    @MainActor
    static func fileContainer(_ label: String) throws -> (ModelContainer, URL) {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("b08-qa-\(label)-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let url = dir.appendingPathComponent("b08-qa.store")
        let schema = Schema([Playlist.self, Channel.self])
        return (try ModelContainer(for: schema, configurations: [ModelConfiguration(schema: schema, url: url)]), url)
    }

    /// Wartet, bis `probe` wahr ist; Rückgabe Wartezeit oder nil.
    @MainActor
    static func wait(_ timeout: TimeInterval, step: TimeInterval = 0.05, _ probe: () -> Bool) async -> TimeInterval? {
        let t0 = Date()
        while Date().timeIntervalSince(t0) < timeout {
            if probe() { return Date().timeIntervalSince(t0) }
            await spin(step)
        }
        return probe() ? Date().timeIntervalSince(t0) : nil
    }

    static func run(_ tool: String, _ args: [String]) throws -> String {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: tool)
        p.arguments = args
        let out = Pipe()
        p.standardOutput = out
        p.standardError = Pipe()
        try p.run()
        let data = out.fileHandleForReading.readDataToEndOfFile()
        p.waitUntilExit()
        return String(decoding: data, as: UTF8.self)
    }

    /// Offene TCP-Verbindungen dieses Prozesses zum Mock-Port (Client-Seite, lsof).
    static func establishedConnections(toPort port: UInt16) -> Int {
        let out = (try? run("/usr/sbin/lsof", ["-nP", "-a", "-p", "\(getpid())", "-iTCP@127.0.0.1:\(port)", "-sTCP:ESTABLISHED"])) ?? ""
        return out.split(separator: "\n").dropFirst().filter { $0.contains("->127.0.0.1:\(port)") }.count
    }
}

// MARK: - Testmedien (stumm)

enum B08Media {
    struct Set {
        let dir: URL
        let ts: Data
        let tsDuration: Double
        let hlsSegments: [Data]
        var tsRate: Double { Double(ts.count) / tsDuration }
    }

    private static var cached: Set?

    static func ffmpeg() -> String? {
        ["/opt/homebrew/bin/ffmpeg", "/usr/local/bin/ffmpeg"].first { FileManager.default.isExecutableFile(atPath: $0) }
    }

    /// Erzeugt (einmal je Rechner) stumme Testmedien und prüft, dass keine Datei eine Audiospur hat.
    static func ensure() throws -> Set {
        if let cached { return cached }
        guard let ff = ffmpeg() else { throw XCTSkip("ffmpeg fehlt – B08-Streamtests brauchen stumme Testmedien") }
        let probe = ff.replacingOccurrences(of: "ffmpeg", with: "ffprobe")
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("b08-qa-media-v1", isDirectory: true)
        let fm = FileManager.default
        let hls = dir.appendingPathComponent("hls", isDirectory: true)
        let src = dir.appendingPathComponent("src.ts")
        if !fm.fileExists(atPath: dir.appendingPathComponent("fertig").path) {
            try? fm.removeItem(at: dir)
            try fm.createDirectory(at: hls, withIntermediateDirectories: true)
            // Buntes Testbild (kein Schwarz), damit ein schwarzes Hauptbild eindeutig messbar ist.
            let video = ["-hide_banner", "-loglevel", "error", "-y", "-f", "lavfi", "-i", "testsrc2=size=640x360:rate=25"]
            let enc = ["-an", "-c:v", "libx264", "-preset", "veryfast", "-b:v", "500k", "-g", "25"]
            _ = try B08QA.run(ff, video + ["-t", "60"] + enc + ["-f", "mpegts", src.path])
            _ = try B08QA.run(ff, video + ["-t", "20"] + enc + ["-f", "hls", "-hls_time", "2", "-hls_list_size", "0",
                                                               "-hls_segment_filename", hls.appendingPathComponent("seg%03d.ts").path,
                                                               hls.appendingPathComponent("vod.m3u8").path])
            fm.createFile(atPath: dir.appendingPathComponent("fertig").path, contents: Data())
        }
        let segs = try fm.contentsOfDirectory(atPath: hls.path).filter { $0.hasSuffix(".ts") }.sorted()
        var checked: [String] = []
        for f in [src.path] + segs.map({ hls.appendingPathComponent($0).path }) {
            let audio = try B08QA.run(probe, ["-v", "error", "-select_streams", "a", "-show_entries", "stream=index", "-of", "csv=p=0", f])
                .split(separator: "\n").filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
            guard audio.isEmpty else {
                throw NSError(domain: "B08Media", code: 1, userInfo: [NSLocalizedDescriptionKey: "Audiospur in \(f) – Abbruch (kein Ton erlaubt)"])
            }
            checked.append((f as NSString).lastPathComponent)
        }
        let duration = Double(try B08QA.run(probe, ["-v", "error", "-show_entries", "format=duration", "-of", "csv=p=0", src.path])
            .trimmingCharacters(in: .whitespacesAndNewlines)) ?? 60
        B08QA.log("MEDIEN|ohne Tonspur geprüft (ffprobe, 0 Audiostreams): \(checked.count) Dateien \(checked.prefix(3).joined(separator: ","))…")
        let set = Set(dir: dir, ts: try Data(contentsOf: src), tsDuration: duration,
                      hlsSegments: try segs.map { try Data(contentsOf: hls.appendingPathComponent($0)) })
        cached = set
        return set
    }
}

// MARK: - Lokaler Anbieter-Mock (Xtream-API + Streams)

/// HTTP-Mock auf 127.0.0.1. Schreibt jede Anfrage (Zeile + Kopfzeilen) und jede Verbindung mit.
///
/// Routen:
/// `/player_api.php` (Xtream: Anmeldung mit `user_info.max_connections`, Kategorien, Live-Streams aus `streamIDs`) ·
/// `/live/<user>/<pass>/<id>.ts` roher TS in Echtzeit, `/live/<user>/<pass>/<id>.m3u8` Live-HLS (+ `segN.ts`);
/// falsche Zugangsdaten → 403; mit `connectionLimit` > 0 bekommt jede TS-Verbindung über dem Limit **403** ·
/// `/tslive/<id>.ts` roher TS · `/livehls/<id>/index.m3u8` Live-HLS · `/hang/…` antwortet nie · `/404/…` ·
/// `/abort/<s>/tslive/<id>.ts` bricht nach s Sekunden ab · `/seg404/<s>/<id>/index.m3u8` Segmente ab s Sekunden 404.
final class B08StreamServer: @unchecked Sendable {
    struct Request: Sendable {
        let conn: Int
        let time: Date
        let method: String
        let target: String
        let path: String
        let headers: [String: String]
        let status: Int
    }

    struct Connection: Sendable {
        let id: Int
        let opened: Date
        let closed: Date?
        let path: String
        let bytesSent: Int
        let closeReason: String?
        let streaming: Bool
        var isOpen: Bool { closed == nil }
    }

    private final class State {
        let id: Int
        let conn: NWConnection
        let opened = Date()
        var closed: Date?
        var closeReason: String?
        var path = ""
        var bytesSent = 0
        var timer: DispatchSourceTimer?
        var inFlight = false
        var streamStart: Date?
        var pos = 0
        var limit: TimeInterval?
        var streaming = false
        var liveUser: String?
        init(id: Int, conn: NWConnection) { self.id = id; self.conn = conn }
    }

    let media: B08Media.Set
    private let queue = DispatchQueue(label: "b08.stream.mock")
    private var listener: NWListener?
    private(set) var port: UInt16 = 0
    private var nextID = 0
    private var states: [Int: State] = [:]
    private var _requests: [Request] = []
    private var firstSeen: [String: Date] = [:]
    private let started = Date()

    // Konfiguration (vor dem Start oder unter `configure` ändern)
    private var _streamIDs: [Int] = [101, 102, 103, 104]
    private var _connectionLimit = 0
    private var _user = B08QA.user
    private var _pass = B08QA.pass

    init(media: B08Media.Set) { self.media = media }

    func configure(streamIDs: [Int]? = nil, connectionLimit: Int? = nil) {
        queue.sync {
            if let streamIDs { _streamIDs = streamIDs }
            if let connectionLimit { _connectionLimit = connectionLimit }
        }
    }

    var base: String { "http://127.0.0.1:\(port)" }
    var hostPort: String { "127.0.0.1:\(port)" }
    func url(_ path: String) -> URL { URL(string: base + path)! }

    var requests: [Request] { queue.sync { _requests } }
    var connections: [Connection] {
        queue.sync {
            states.values.sorted { $0.id < $1.id }.map {
                Connection(id: $0.id, opened: $0.opened, closed: $0.closed, path: $0.path, bytesSent: $0.bytesSent,
                           closeReason: $0.closeReason, streaming: $0.streaming)
            }
        }
    }

    func requests(containing s: String) -> [Request] { requests.filter { $0.target.contains(s) } }
    func openConnections(containing s: String) -> [Connection] { connections.filter { $0.isOpen && $0.path.contains(s) } }
    /// Offene Verbindungen, die gerade einen Stream liefern (TS) oder auf eine Antwort warten (hang).
    func openStreamConnections(containing s: String = "") -> [Connection] {
        connections.filter { $0.isOpen && $0.streaming && (s.isEmpty || $0.path.contains(s)) }
    }

    func summary(_ filter: String = "") -> String {
        let c = connections.filter { filter.isEmpty || $0.path.contains(filter) }
        let open = c.filter(\.isOpen)
        return "verbindungen=\(c.count) offen=\(open.count) offeneStreams=\(open.filter(\.streaming).count) " +
            open.map { "#\($0.id)\(self.redact($0.path))" }.joined(separator: " ")
    }

    /// Passwort in Protokollzeilen ersetzen (Beleg zeigt die Stelle, nicht den Wert).
    func redact(_ s: String) -> String { s.replacingOccurrences(of: _pass, with: "<pass>") }

    func start() throws {
        let params = NWParameters.tcp
        params.requiredLocalEndpoint = .hostPort(host: "127.0.0.1", port: .any)
        params.allowLocalEndpointReuse = true
        let l = try NWListener(using: params)
        let ready = DispatchSemaphore(value: 0)
        var failure: Error?
        l.stateUpdateHandler = { st in
            switch st {
            case .ready: ready.signal()
            case .failed(let e): failure = e; ready.signal()
            default: break
            }
        }
        l.newConnectionHandler = { [weak self] c in self?.accept(c) }
        l.start(queue: queue)
        guard ready.wait(timeout: .now() + 5) == .success else {
            throw NSError(domain: "B08StreamServer", code: 1, userInfo: [NSLocalizedDescriptionKey: "Listener nicht bereit"])
        }
        if let failure { throw failure }
        listener = l
        port = l.port?.rawValue ?? 0
    }

    func stop() {
        listener?.cancel()
        listener = nil
        queue.sync {
            for s in states.values where s.closed == nil {
                s.timer?.cancel()
                s.closed = Date()
                s.closeReason = "server-stop"
                s.conn.cancel()
            }
        }
    }

    // MARK: Verbindung

    private func accept(_ c: NWConnection) {
        nextID += 1
        let st = State(id: nextID, conn: c)
        states[st.id] = st
        c.stateUpdateHandler = { [weak self, weak st] s in
            guard let self, let st else { return }
            switch s {
            case .failed(let e): self.markClosed(st, "failed \(e)")
            case .cancelled: self.markClosed(st, st.closeReason ?? "cancelled")
            default: break
            }
        }
        c.start(queue: queue)
        receive(st, buffer: Data())
    }

    private func markClosed(_ st: State, _ reason: String) {
        guard st.closed == nil else { return }
        st.timer?.cancel()
        st.timer = nil
        st.closed = Date()
        st.closeReason = reason
    }

    private func close(_ st: State, _ reason: String) {
        markClosed(st, reason)
        st.conn.cancel()
    }

    private func receive(_ st: State, buffer: Data) {
        st.conn.receive(minimumIncompleteLength: 1, maximumLength: 65_536) { [weak self] data, _, complete, error in
            guard let self else { return }
            var buf = buffer
            if let data { buf.append(data) }
            if let end = buf.range(of: Data("\r\n\r\n".utf8)) {
                let head = buf.subdata(in: buf.startIndex..<end.lowerBound)
                let rest = buf.subdata(in: end.upperBound..<buf.endIndex)
                self.handle(st, head: head, leftover: rest)
            } else if complete || error != nil {
                self.close(st, complete ? "client-eof" : "receive-error")
            } else {
                self.receive(st, buffer: buf)
            }
        }
    }

    private func watchEOF(_ st: State) {
        st.conn.receive(minimumIncompleteLength: 1, maximumLength: 4096) { [weak self] _, _, complete, error in
            guard let self else { return }
            if complete || error != nil { self.close(st, "client-closed") } else if st.closed == nil { self.watchEOF(st) }
        }
    }

    private func handle(_ st: State, head: Data, leftover: Data) {
        let text = String(decoding: head, as: UTF8.self)
        var lines = text.components(separatedBy: "\r\n")
        let requestLine = lines.isEmpty ? "" : lines.removeFirst()
        let parts = requestLine.split(separator: " ").map(String.init)
        var headers: [String: String] = [:]
        for line in lines {
            guard let i = line.firstIndex(of: ":") else { continue }
            headers[line[..<i].lowercased()] = line[line.index(after: i)...].trimmingCharacters(in: .whitespaces)
        }
        let method = parts.first ?? ""
        let target = parts.count > 1 ? parts[1] : ""
        let path = String(target.split(separator: "?", maxSplits: 1, omittingEmptySubsequences: false).first ?? "")
        st.path = path
        let code = route(st, target: target, path: path, leftover: leftover)
        _requests.append(Request(conn: st.id, time: Date(), method: method, target: target, path: path, headers: headers, status: code))
    }

    private func query(_ target: String) -> [String: String] {
        guard let q = target.split(separator: "?", maxSplits: 1).dropFirst().first else { return [:] }
        var out: [String: String] = [:]
        for pair in q.split(separator: "&") {
            let kv = pair.split(separator: "=", maxSplits: 1).map { String($0).removingPercentEncoding ?? String($0) }
            if kv.count == 2 { out[kv[0]] = kv[1] }
        }
        return out
    }

    /// Rückgabe: HTTP-Status (0 = Stream/Hänger ohne Abschluss).
    @discardableResult
    private func route(_ st: State, target: String, path: String, leftover: Data) -> Int {
        let p = path.split(separator: "/").map(String.init)
        guard let first = p.first else { status(st, 404, leftover: leftover); return 404 }
        switch first {
        case "player_api.php":
            let q = query(target)
            guard q["username"] == _user, q["password"] == _pass else {
                json(st, ["user_info": ["auth": 0]], leftover: leftover); return 200
            }
            switch q["action"] {
            case nil:
                json(st, ["user_info": ["auth": 1, "status": "Active", "max_connections": "\(max(_connectionLimit, 1))",
                                        "active_cons": "0"],
                          "server_info": ["url": "127.0.0.1", "port": "\(port)"]], leftover: leftover)
            case "get_live_categories":
                json(st, [["category_id": "1", "category_name": "QA"]], leftover: leftover)
            case "get_live_streams":
                let list: [[String: Any]] = _streamIDs.enumerated().map { i, id in
                    ["name": "QA Kanal \(i + 1)", "stream_id": id, "stream_icon": "", "epg_channel_id": "qa.\(i + 1)", "category_id": "1"]
                }
                json(st, list, leftover: leftover)
            default:
                json(st, [Any](), leftover: leftover)
            }
            return 200
        case "live" where p.count >= 4:
            guard p[1] == _user, p[2] == _pass else { status(st, 403, leftover: leftover); return 403 }
            let last = p.last!
            if last.hasSuffix(".m3u8") || last.range(of: #"^seg\d+\.ts$"#, options: .regularExpression) != nil {
                return livehls(st, last: last, leftover: leftover)
            }
            if _connectionLimit > 0 {
                let open = states.values.filter { $0.closed == nil && $0.streaming && $0.liveUser == _user && $0.id != st.id }.count
                if open >= _connectionLimit {
                    send(st, 403, "text/plain", Data("Max connections reached".utf8), leftover: leftover, keepAlive: false)
                    return 403
                }
            }
            st.liveUser = _user
            realtime(st, limit: nil)
            return 200
        case "tslive":
            realtime(st, limit: nil)
            return 200
        case "list.m3u":
            // M3U mit fünf MPEG-TS-Sendern auf diesem Mock (für den Import über die echte Oberfläche)
            var body = "#EXTM3U\n"
            for i in 1...5 { body += "#EXTINF:-1 tvg-id=\"echt\(i)\" group-title=\"QA\",Echt \(i)\n\(base)/tslive/echt\(i).ts\n" }
            send(st, 200, "audio/x-mpegurl", Data(body.utf8), leftover: leftover)
            return 200
        case "livehls" where p.count >= 3:
            return livehls(st, last: p.last!, leftover: leftover)
        case "seg404" where p.count >= 4:
            let secs = Double(p[1]) ?? 0
            let key = "seg404/\(p[2])"
            if firstSeen[key] == nil { firstSeen[key] = Date() }
            let last = p.last!
            if !last.hasSuffix(".m3u8"), Date().timeIntervalSince(firstSeen[key]!) >= secs {
                status(st, 404, leftover: leftover); return 404
            }
            return livehls(st, last: last, leftover: leftover)
        case "abort" where p.count >= 3:
            realtime(st, limit: Double(p[1]) ?? 0)
            return 200
        case "hang":
            st.streaming = true
            watchEOF(st)
            return 0
        case "404":
            status(st, 404, leftover: leftover); return 404
        default:
            status(st, 404, leftover: leftover); return 404
        }
    }

    @discardableResult
    private func livehls(_ st: State, last: String, leftover: Data) -> Int {
        if last.hasSuffix(".m3u8") || last.hasSuffix(".m3u") {
            let seq = Int(Date().timeIntervalSince(started) / 2.0)
            var lines = ["#EXTM3U", "#EXT-X-VERSION:3", "#EXT-X-TARGETDURATION:2", "#EXT-X-MEDIA-SEQUENCE:\(seq)"]
            for i in seq..<(seq + 6) { lines += ["#EXTINF:2.000000,", String(format: "seg%05d.ts", i)] }
            send(st, 200, "application/vnd.apple.mpegurl", Data((lines.joined(separator: "\n") + "\n").utf8),
                 extra: ["Cache-Control": "no-cache"], leftover: leftover)
            return 200
        } else if let r = last.range(of: #"\d+"#, options: .regularExpression), let n = Int(last[r]), !media.hlsSegments.isEmpty {
            send(st, 200, "video/mp2t", media.hlsSegments[n % media.hlsSegments.count], leftover: leftover)
            return 200
        }
        status(st, 404, leftover: leftover)
        return 404
    }

    private func status(_ st: State, _ code: Int, leftover: Data) {
        send(st, code, "text/html", Data("<html><body><h1>\(code)</h1></body></html>".utf8), leftover: leftover)
    }

    private func json(_ st: State, _ obj: Any, leftover: Data) {
        let data = (try? JSONSerialization.data(withJSONObject: obj)) ?? Data("{}".utf8)
        send(st, 200, "application/json", data, leftover: leftover)
    }

    private func send(_ st: State, _ code: Int, _ ctype: String, _ body: Data, extra: [String: String] = [:], leftover: Data,
                      keepAlive: Bool = true) {
        var head = "HTTP/1.1 \(code) B08\r\nContent-Type: \(ctype)\r\nContent-Length: \(body.count)\r\n"
        if !keepAlive { head += "Connection: close\r\n" }
        for (k, v) in extra { head += "\(k): \(v)\r\n" }
        head += "\r\n"
        var data = Data(head.utf8)
        data.append(body)
        st.conn.send(content: data, completion: .contentProcessed { [weak self] err in
            guard let self else { return }
            if err != nil { return self.markClosed(st, "send-error") }
            st.bytesSent += data.count
            if keepAlive { self.receive(st, buffer: leftover) } else { self.close(st, "server-close-\(code)") }
        })
    }

    /// Roher TS in Echtzeit (1 s Vorlauf), endlos bzw. bis `limit`; sendet nur weiter, wenn der Client liest.
    private func realtime(_ st: State, limit: TimeInterval?) {
        st.streaming = true
        st.limit = limit
        let head = Data("HTTP/1.1 200 OK\r\nContent-Type: video/mp2t\r\nConnection: close\r\n\r\n".utf8)
        st.conn.send(content: head, completion: .contentProcessed { _ in })
        st.streamStart = Date()
        let t = DispatchSource.makeTimerSource(queue: queue)
        t.schedule(deadline: .now(), repeating: .milliseconds(50))
        t.setEventHandler { [weak self] in self?.pump(st) }
        st.timer = t
        t.resume()
        watchEOF(st)
    }

    private func pump(_ st: State) {
        guard st.closed == nil, let t0 = st.streamStart else { return }
        let elapsed = Date().timeIntervalSince(t0)
        if let limit = st.limit, elapsed >= limit { return close(st, "abort-after-\(Int(limit))s") }
        guard !st.inFlight else { return }
        let rate = media.tsRate
        guard Double(st.bytesSent) < elapsed * rate + rate else { return }
        let chunkSize = 1316 * 10
        let ts = media.ts
        var chunk = Data()
        var pos = st.pos
        while chunk.count < chunkSize {
            let end = min(ts.count, pos + chunkSize - chunk.count)
            chunk.append(ts.subdata(in: pos..<end))
            pos = end % ts.count
        }
        st.inFlight = true
        st.conn.send(content: chunk, completion: .contentProcessed { [weak self] err in
            guard let self else { return }
            st.inFlight = false
            if err != nil { return self.close(st, "client-closed-send") }
            st.bytesSent += chunk.count
            st.pos = pos
        })
    }
}

// MARK: - Engines von außen beobachten

/// Merkt sich jeden `AVPlayer`, den ein `AVPlayerLayer` bekommt, und jede VLC-Engine (Delegate eines
/// `VLCMediaPlayer`) – auch die Engine, die `PlayerView` intern als `@State` hält.
@MainActor
enum B08Registry {
    final class Weak { weak var obj: AnyObject?; let created = Date(); init(_ o: AnyObject?) { obj = o } }
    private(set) static var avPlayers: [Weak] = []
    private(set) static var vlcPlayers: [Weak] = []
    private(set) static var vlcEngines: [Weak] = []
    private static var installed = false

    static func install() {
        guard !installed else { return }
        installed = true
        swizzleSetter(AVPlayerLayer.self, "setPlayer:") { _, arg in
            if let p = arg as? AVPlayer {
                // Kein Ton: jeder AVPlayer, der eine Videofläche bekommt, sofort auf Lautstärke 0 (isMuted bleibt).
                p.volume = 0
                if !(avPlayers.contains { $0.obj === p }) { avPlayers.append(Weak(p)) }
            }
        }
        if let vlc = NSClassFromString("VLCMediaPlayer") {
            swizzleSetter(vlc, "setDelegate:") { obj, arg in
                if arg != nil { vlcPlayers.append(Weak(obj)); vlcEngines.append(Weak(arg)) }
            }
        }
    }

    private static func swizzleSetter(_ cls: AnyClass, _ name: String, _ record: @escaping @MainActor (AnyObject, AnyObject?) -> Void) {
        let sel = NSSelectorFromString(name)
        guard let m = class_getInstanceMethod(cls, sel) else { return }
        typealias Fn = @convention(c) (AnyObject, Selector, AnyObject?) -> Void
        let orig = unsafeBitCast(method_getImplementation(m), to: Fn.self)
        let block: @convention(block) (AnyObject, AnyObject?) -> Void = { obj, arg in
            orig(obj, sel, arg)
            if Thread.isMainThread { MainActor.assumeIsolated { record(obj, arg) } }
        }
        method_setImplementation(m, imp_implementationWithBlock(block))
    }

    static var liveAVPlayers: [AVPlayer] { avPlayers.compactMap { $0.obj as? AVPlayer } }
    static var liveVLCEngines: [any PlaybackEngine] { vlcEngines.compactMap { $0.obj as? any PlaybackEngine } }
    static var liveVLCPlayers: [NSObject] { vlcPlayers.compactMap { $0.obj as? NSObject } }

    /// Beendet alles, was noch lebt (nur Testaufräumen).
    static func stopAll() {
        for p in liveAVPlayers { p.volume = 0; p.isMuted = true; p.pause(); p.replaceCurrentItem(with: nil) }
        for v in liveVLCPlayers { _ = v.perform(NSSelectorFromString("stop")) }
    }
}

@MainActor
enum B08Engine {
    static let vlcStates = ["stopped", "opening", "buffering", "ended", "error", "playing", "paused", "esAdded"]

    static func name(_ s: PlaybackState) -> String {
        switch s {
        case .idle: return "idle"
        case .loading: return "loading"
        case .playing: return "playing"
        case .failed(let m): return "failed(\(m))"
        }
    }

    static func child(_ obj: Any, _ label: String) -> Any? {
        var m: Mirror? = Mirror(reflecting: obj)
        while let cur = m {
            if let c = cur.children.first(where: { $0.label == label || $0.label == "_" + label }) { return c.value }
            m = cur.superclassMirror
        }
        return nil
    }

    static func avPlayer(_ e: any PlaybackEngine) -> AVPlayer? { child(e, "player") as? AVPlayer }
    static func vlcPlayer(_ e: any PlaybackEngine) -> NSObject? { child(e, "mediaPlayer") as? NSObject }
    /// Am Typ erkannt: seit B06 · BUG-01/07 hat eine VLC-Engine nach einem Fehler (bzw. vor dem Start) keinen Player.
    static func isVLC(_ e: any PlaybackEngine) -> Bool { String(describing: type(of: e)).contains("VLC") }
    static func kind(_ e: any PlaybackEngine) -> String { isVLC(e) ? "VLC" : "AVKit" }

    static func vlcState(_ v: NSObject) -> String {
        let raw = (v.value(forKey: "state") as? NSNumber)?.intValue ?? -1
        return raw >= 0 && raw < vlcStates.count ? vlcStates[raw] : "\(raw)"
    }

    static func vlcAudio(_ v: NSObject) -> (volume: Int?, muted: Bool?) {
        let audio = v.value(forKey: "audio") as? NSObject
        return ((audio?.value(forKey: "volume") as? NSNumber)?.intValue, (audio?.value(forKey: "muted") as? NSNumber)?.boolValue)
    }

    /// Stummzustand am eigentlichen Player (AVPlayer.isMuted bzw. VLC audio.muted); nil, wenn nicht lesbar.
    static func innerMuted(_ e: any PlaybackEngine) -> Bool? {
        if let p = avPlayer(e) { return p.isMuted }
        if let v = vlcPlayer(e) { return vlcAudio(v).muted }
        return nil
    }

    static func detail(_ e: any PlaybackEngine) -> String {
        if let p = avPlayer(e) {
            let st: String
            switch p.currentItem?.status {
            case .readyToPlay: st = "ready"
            case .failed: st = "failed"
            case .unknown: st = "unknown"
            default: st = "nil"
            }
            return "av item=\(st) vol=\(p.volume) muted=\(p.isMuted)"
        }
        if let v = vlcPlayer(e) {
            let a = vlcAudio(v)
            return "vlc state=\(vlcState(v)) audio.volume=\(a.volume.map(String.init) ?? "-") audio.muted=\(a.muted.map { $0 ? "1" : "0" } ?? "-")"
        }
        return "?"
    }

    /// Lautstärke 0 für eine Engine (Tonschutz), `isMuted` bleibt unverändert.
    static func silence(_ e: any PlaybackEngine) {
        e.setVolume(0)
        avPlayer(e)?.volume = 0
    }

    static func describe(_ s: MultiviewSession) -> String {
        s.slots.enumerated().map { i, slot in
            "[\(i)\(i == s.focusedIndex ? "*" : "")] \(slot.channel.name) \(kind(slot.engine)) \(name(slot.engine.state)) muted=\(slot.engine.isMuted) inner=\(innerMuted(slot.engine).map { $0 ? "1" : "0" } ?? "-")"
        }.joined(separator: " ; ") + " | fokus=\(s.focusedIndex) layout=\(s.layout.rawValue)"
    }
}

/// Schwache Referenz auf eine Engine, um ihre Freigabe zu beobachten.
final class B08Weak {
    weak var object: AnyObject?
    let label: String
    init(_ o: AnyObject, _ label: String) { object = o; self.label = label }
    var alive: Bool { object != nil }
}

// MARK: - Beep-Wächter

/// Ersetzt `-[NSResponder noResponderFor:]` (der Weg zum Systembeep bei unbehandelten Tasten) durch eine Zählung.
@MainActor
enum B08BeepGuard {
    private(set) static var hits: [String] = []
    private static var installed = false
    private static var imp: IMP?

    @discardableResult
    static func install() -> Bool {
        if installed { return verify() }
        let sel = NSSelectorFromString("noResponderFor:")
        let block: @convention(block) (AnyObject, Selector) -> Void = { obj, event in
            let name = NSStringFromSelector(event)
            let line = (name == "keyDown:" ? "SYSTEMBEEP-UNTERDRUECKT " : "ohne-Empfaenger ") + "\(type(of: obj)) \(name)"
            if name == "keyDown:", Thread.isMainThread { MainActor.assumeIsolated { hits.append(line) } }
            print("B08QA|\(line)")
        }
        let newImp = imp_implementationWithBlock(block)
        imp = newImp
        for cls in [NSResponder.self, NSView.self, NSWindow.self, NSApplication.self] as [AnyClass] {
            guard let m = class_getInstanceMethod(cls, sel) else { continue }
            method_setImplementation(m, newImp)
        }
        installed = true
        return verify()
    }

    /// Alle vier Klassen landen bei der Ersatz-Implementierung – sonst keine Taste senden.
    static func verify() -> Bool {
        let sel = NSSelectorFromString("noResponderFor:")
        guard let imp else { return false }
        return [NSResponder.self, NSView.self, NSWindow.self, NSApplication.self, NSHostingView<EmptyView>.self].allSatisfy {
            class_getMethodImplementation($0, sel) == imp
        }
    }

    static func reset() { hits.removeAll() }
}

// MARK: - Fenster, Accessibility, Maus, Aufnahmen

@MainActor
enum B08UI {
    static func window<V: View>(_ view: V, size: CGSize = CGSize(width: 900, height: 600),
                                origin: CGPoint = CGPoint(x: 60, y: 120), title: String = "B08-QA") -> NSWindow {
        let w = NSWindow(contentRect: NSRect(origin: origin, size: size),
                         styleMask: [.titled, .closable, .resizable, .miniaturizable], backing: .buffered, defer: false)
        w.isReleasedWhenClosed = false
        w.title = title
        w.contentView = NSHostingView(rootView: view)
        w.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        return w
    }

    static func close(_ w: NSWindow) {
        w.contentView = nil
        w.orderOut(nil)
        w.close()
    }

    static func obj(_ e: NSObject, _ name: String) -> Any? {
        let sel = NSSelectorFromString(name)
        guard e.responds(to: sel) else { return nil }
        return e.perform(sel)?.takeUnretainedValue()
    }

    static func text(_ e: NSObject, _ name: String) -> String {
        let v = obj(e, name)
        if let s = v as? String { return s }
        if let a = v as? NSAttributedString { return a.string }
        if let n = v as? NSNumber { return n.stringValue }
        return ""
    }

    static func frame(_ e: NSObject) -> NSRect {
        let sel = NSSelectorFromString("accessibilityFrame")
        guard e.responds(to: sel), let imp = e.method(for: sel) else { return .zero }
        typealias F = @convention(c) (AnyObject, Selector) -> NSRect
        return unsafeBitCast(imp, to: F.self)(e, sel)
    }

    static func isEnabled(_ e: NSObject) -> Bool {
        let sel = NSSelectorFromString("isAccessibilityEnabled")
        guard e.responds(to: sel), let imp = e.method(for: sel) else { return true }
        typealias F = @convention(c) (AnyObject, Selector) -> Bool
        return unsafeBitCast(imp, to: F.self)(e, sel)
    }

    /// `accessibilityPerformPress` (Weg von VoiceOver).
    static func press(_ e: NSObject) -> Bool {
        let sel = NSSelectorFromString("accessibilityPerformPress")
        guard e.responds(to: sel), let imp = e.method(for: sel) else { return false }
        typealias F = @convention(c) (AnyObject, Selector) -> Bool
        return unsafeBitCast(imp, to: F.self)(e, sel)
    }

    static func role(_ e: NSObject) -> String { text(e, "accessibilityRole") }
    static func help(_ e: NSObject) -> String { text(e, "accessibilityHelp") }
    static func label(_ e: NSObject) -> String {
        [text(e, "accessibilityLabel"), text(e, "accessibilityTitle"), text(e, "accessibilityValue")]
            .filter { !$0.isEmpty }.joined(separator: " | ")
    }

    static func kids(_ e: NSObject) -> [NSObject] { (obj(e, "accessibilityChildren") as? [Any] ?? []).compactMap { $0 as? NSObject } }

    static func all(_ root: NSObject, depth: Int = 0) -> [NSObject] {
        guard depth < 60 else { return [] }
        return [root] + kids(root).flatMap { all($0, depth: depth + 1) }
    }

    static func wake(_ w: NSWindow) {
        if let v = w.contentView { _ = v.accessibilityHitTest(NSPoint(x: w.frame.midX, y: w.frame.midY)) }
    }

    static func elements(_ w: NSWindow) -> [NSObject] {
        guard let c = w.contentView else { return [] }
        wake(w)
        return all(c)
    }

    static func labels(_ w: NSWindow) -> [String] { elements(w).map(label).filter { !$0.isEmpty } }

    static func elements(_ w: NSWindow, where pred: (NSObject) -> Bool) -> [NSObject] { elements(w).filter(pred) }

    /// Bildschirmrechteck (unten links) → Fensterkoordinaten.
    static func windowPoint(_ w: NSWindow, screen p: NSPoint) -> NSPoint { w.convertPoint(fromScreen: p) }

    /// Klick an einem Punkt in Fensterkoordinaten (unten links, AppKit).
    static func click(_ w: NSWindow, at p: NSPoint) {
        for type in [NSEvent.EventType.leftMouseDown, .leftMouseUp] {
            if let ev = NSEvent.mouseEvent(with: type, location: p, modifierFlags: [], timestamp: ProcessInfo.processInfo.systemUptime,
                                           windowNumber: w.windowNumber, context: nil, eventNumber: 0, clickCount: 1, pressure: 1) {
                w.sendEvent(ev)
            }
        }
    }

    static func click(_ e: NSObject, in w: NSWindow) {
        let f = frame(e)
        click(w, at: w.convertPoint(fromScreen: NSPoint(x: f.midX, y: f.midY)))
    }

    /// Welche Ansicht bekommt einen Klick an dieser Stelle (AppKit-Hit-Test)?
    static func hitView(_ w: NSWindow, at p: NSPoint) -> String {
        guard let v = w.contentView?.superview?.hitTest(p) ?? w.contentView?.hitTest(p) else { return "-" }
        return String(describing: type(of: v))
    }

    static func image(_ w: NSWindow) -> CGImage? {
        CGWindowListCreateImage(.null, .optionIncludingWindow, CGWindowID(w.windowNumber), [.boundsIgnoreFraming, .nominalResolution])
    }

    @discardableResult
    static func shot(_ w: NSWindow, _ name: String) -> CGImage? {
        guard let img = image(w) else {
            B08QA.log("SHOT|\(name)|fehlgeschlagen")
            return nil
        }
        let rep = NSBitmapImageRep(cgImage: img)
        if let data = rep.representation(using: .png, properties: [:]) {
            try? FileManager.default.createDirectory(at: B08QA.qaFolder, withIntermediateDirectories: true)
            try? data.write(to: B08QA.qaFolder.appendingPathComponent("\(name).png"))
        }
        B08QA.log("SHOT|\(name)|\(img.width)x\(img.height)")
        return img
    }

    /// Anteil fast schwarzer Pixel (R, G, B < 16) in einem Bildausschnitt; `rect` in Anteilen (0…1, oben links).
    static func blackRatio(_ img: CGImage, rect: CGRect) -> Double {
        let w = img.width, h = img.height
        let ctxW = 160, ctxH = 90
        guard let ctx = CGContext(data: nil, width: ctxW, height: ctxH, bitsPerComponent: 8, bytesPerRow: ctxW * 4,
                                  space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return -1 }
        ctx.interpolationQuality = .none
        ctx.draw(img, in: CGRect(x: 0, y: 0, width: ctxW, height: ctxH))
        guard let data = ctx.data else { return -1 }
        let px = data.bindMemory(to: UInt8.self, capacity: ctxW * ctxH * 4)
        _ = (w, h)
        let x0 = Int(rect.minX * Double(ctxW)), x1 = Int(rect.maxX * Double(ctxW))
        let y0 = Int(rect.minY * Double(ctxH)), y1 = Int(rect.maxY * Double(ctxH))
        var black = 0, total = 0
        for y in y0..<y1 {
            // CGContext-Speicher: Zeile 0 = oben
            for x in x0..<x1 {
                let i = (y * ctxW + x) * 4
                total += 1
                if px[i] < 16 && px[i + 1] < 16 && px[i + 2] < 16 { black += 1 }
            }
        }
        return total == 0 ? -1 : Double(black) / Double(total)
    }
}

// MARK: - Die echte App (Szenen WindowGroup + Window("Multiview"))

/// Zugriff auf die Szenen der laufenden App im Test-Host: Menü „Window › Multiview", das echte Multiview-Fenster
/// und die **eine** `MultiviewSession`, die `MikaPlusPlayerApp` als `@State` hält (per Reflection aus der Wurzelansicht
/// des Fensters gelesen – kein Eingriff in den Produktcode).
@MainActor
enum B08App {
    static func windowMenuItem() -> NSMenuItem? {
        let windowMenu = NSApp.windowsMenu ?? NSApp.mainMenu?.items.first { ["Window", "Fenster"].contains($0.submenu?.title ?? "") }?.submenu
        return windowMenu?.items.first { $0.title == "Multiview" }
    }

    static func windowMenuTitles() -> [String] {
        let windowMenu = NSApp.windowsMenu ?? NSApp.mainMenu?.items.first { ["Window", "Fenster"].contains($0.submenu?.title ?? "") }?.submenu
        return windowMenu?.items.map { $0.isSeparatorItem ? "—" : $0.title } ?? []
    }

    /// Sichtbare echte Multiview-Fenster (Szene `Window("Multiview", id: "multiview")`).
    static func multiviewWindows() -> [NSWindow] {
        NSApp.windows.filter { $0.isVisible && ($0.identifier?.rawValue.contains("multiview") == true || $0.title == "Multiview") &&
            !($0.title == "B08-QA") }
    }

    static func openViaMenu() -> Bool {
        guard let item = windowMenuItem(), let menu = item.menu, let idx = menu.items.firstIndex(of: item) else { return false }
        menu.performActionForItem(at: idx)
        return true
    }

    /// Sucht eine `MultiviewSession` in der Wurzelansicht eines SwiftUI-Fensters.
    static func session(in window: NSWindow) -> MultiviewSession? { first(MultiviewSession.self, in: window) }

    /// Sucht den `ModelContainer` der Szene (`.modelContainer(modelContainer)`) in der Wurzelansicht eines Fensters.
    static func container(in window: NSWindow) -> ModelContainer? { first(ModelContainer.self, in: window) }

    static func first<T>(_ type: T.Type, in window: NSWindow) -> T? {
        guard let host = window.contentView else { return nil }
        var budget = 60_000
        return find(T.self, host, depth: 0, budget: &budget)
    }

    /// Die Session der App: aus dem echten Multiview-Fenster, sonst aus einem Hauptfenster.
    static func appSession() -> MultiviewSession? {
        for w in multiviewWindows() { if let s = session(in: w) { return s } }
        for w in NSApp.windows where w.isVisible { if let s = session(in: w) { return s } }
        return nil
    }

    private static func find<T>(_ type: T.Type, _ value: Any, depth: Int, budget: inout Int) -> T? {
        if let s = value as? T { return s }
        guard depth < 20, budget > 0 else { return nil }
        var mirror: Mirror? = Mirror(reflecting: value)
        while let cur = mirror {
            for child in cur.children {
                budget -= 1
                if budget <= 0 { return nil }
                let v = child.value
                if let s = v as? T { return s }
                // Keine Ansichten/Fenster-Hierarchien und keine großen Sammlungen durchwandern.
                if v is NSView || v is NSWindow || v is NSResponder { continue }
                let cm = Mirror(reflecting: v)
                if cm.displayStyle == .collection || cm.displayStyle == .set || cm.displayStyle == .dictionary, cm.children.count > 50 { continue }
                if let found = find(T.self, v, depth: depth + 1, budget: &budget) { return found }
            }
            mirror = cur.superclassMirror
        }
        return nil
    }

    /// Hauptfenster der App (WindowGroup mit ContentView).
    static func mainWindows() -> [NSWindow] {
        NSApp.windows.filter { $0.isVisible && $0.contentView != nil && !multiviewWindows().contains($0) && $0.title != "B08-QA" &&
            String(describing: type(of: $0)).contains("SwiftUI") }
    }
}

// MARK: - Basisklasse

/// Startet Medien und Mock, registriert Engines und Beep-Wächter, räumt alles auf (Engines stumm und gestoppt,
/// Fenster zu, Mock aus, Schlüsselbund-Einträge des Test-Dienstes gelöscht).
@MainActor
class B08TestCase: XCTestCase {
    var server: B08StreamServer!
    var media: B08Media.Set!
    var windows: [NSWindow] = []
    var sessions: [MultiviewSession] = []

    override func setUp() async throws {
        try await super.setUp()
        B08Registry.install()
        media = try B08Media.ensure()
        server = B08StreamServer(media: media)
        try server.start()
        B08QA.log("=== \(name) · mock \(server.hostPort)")
    }

    override func tearDown() async throws {
        for s in sessions where s.layout != .focus {
            s.layout = .focus
        }
        if !sessions.isEmpty { await B08QA.spin(0.4) }
        for s in sessions { s.clear() }
        sessions.removeAll()
        for w in windows { B08UI.close(w) }
        windows.removeAll()
        B08Registry.stopAll()
        await B08QA.spin(0.3)
        server?.stop()
        server = nil
        try? XtreamCredentialStore.standard.deleteAll()
        try await super.tearDown()
    }

    func session() -> MultiviewSession {
        let s = MultiviewSession()
        sessions.append(s)
        return s
    }

    func channel(_ name: String, _ path: String) -> Channel {
        Channel(name: name, streamURL: server.url(path))
    }

    /// `add` + sofortiger Tonschutz (Lautstärke 0, Stummzustand unverändert).
    @discardableResult
    func add(_ s: MultiviewSession, _ c: Channel) -> MultiviewSession.Slot? {
        let before = s.slots.map(\.id)
        s.add(c)
        let new = s.slots.first { !before.contains($0.id) }
        if let new { B08Engine.silence(new.engine) }
        return new
    }

    func silenceAll(_ s: MultiviewSession) { s.slots.forEach { B08Engine.silence($0.engine) } }

    /// Leeren ohne Absturz: erst „Fokus“ zeichnen lassen, dann `clear()`. Leeren bei sichtbarem Raster stürzt ab (FB-01).
    func safeClear(_ s: MultiviewSession) async {
        if s.layout != .focus {
            s.layout = .focus
            await B08QA.spin(0.6)
        }
        s.clear()
    }

    func track(_ w: NSWindow) -> NSWindow { windows.append(w); return w }

    /// Xtream-Playlist über den echten Importpfad gegen den Mock (Zugangsdaten in den Test-Schlüsselbund).
    func importXtream(_ ctx: ModelContext, output: XtreamOutput = .mpegts, name: String = "QA Xtream") async throws -> Playlist {
        let importer = PlaylistImporter(modelContext: ctx, loginThrottle: XtreamLoginThrottle())
        return try await importer.importFromXtream(
            XtreamCredentials(host: server.base, username: B08QA.user, password: B08QA.pass), output: output, name: name)
    }
}
