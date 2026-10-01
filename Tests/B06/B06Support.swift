import Foundation
import Network
import XCTest
import SwiftUI
import SwiftData
import AppKit
import AVFoundation
import ObjectiveC
@testable import MikaPlusPlayer

// B06 · Wiedergabe — gemeinsame Hilfen der QA (Durchlauf 1, 2026-09-16).
//
// Kein Ton: Alle Testmedien entstehen mit `ffmpeg -an` und werden vor der ersten Wiedergabe mit `ffprobe`
// geprüft (keine Audiospur, sonst Abbruch). Engines, die ein Test selbst erzeugt, werden vor `load` stumm
// geschaltet. Tastenereignisse nur für belegte Tasten; ein Beep-Wächter ersetzt `noResponderFor:`.
// Streams ausschließlich von 127.0.0.1 (`B06StreamServer`), Zugangsdaten erfunden.

enum B06QA {
    static func log(_ s: String) {
        print("B06QA|\(stamp())|\(s)")
        fflush(stdout)
    }

    static func stamp() -> String {
        let f = DateFormatter()
        f.dateFormat = "HH:mm:ss.SSS"
        return f.string(from: Date())
    }

    static func f1(_ t: TimeInterval) -> String { String(format: "%.1f", t) }

    static let user = "qa-user"
    static let pass = "qa-pass-b06"

    /// `features/B06-wiedergabe/qa/` im Repository.
    static var qaFolder: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("features/B06-wiedergabe/qa", isDirectory: true)
    }

    @MainActor
    static func shot(_ w: NSWindow, _ name: String) {
        guard let img = CGWindowListCreateImage(.null, .optionIncludingWindow, CGWindowID(w.windowNumber),
                                                [.boundsIgnoreFraming, .nominalResolution]) else {
            log("SHOT|\(name)|fehlgeschlagen")
            return
        }
        let rep = NSBitmapImageRep(cgImage: img)
        guard let data = rep.representation(using: .png, properties: [:]) else { return }
        try? FileManager.default.createDirectory(at: qaFolder, withIntermediateDirectories: true)
        try? data.write(to: qaFolder.appendingPathComponent("\(name).png"))
        log("SHOT|\(name)|\(img.width)x\(img.height)")
    }

    static func spin(_ seconds: TimeInterval) async {
        try? await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
    }

    /// Liest die Systemlautstärke (nur lesen – die QA verändert sie nie).
    static func systemVolume() -> String {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        p.arguments = ["-e", "output volume of (get volume settings) & \" muted:\" & output muted of (get volume settings)"]
        let out = Pipe()
        p.standardOutput = out
        p.standardError = Pipe()
        try? p.run()
        let d = out.fileHandleForReading.readDataToEndOfFile()
        p.waitUntilExit()
        return String(decoding: d, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
    }

    @MainActor
    static func inMemoryContainer() throws -> ModelContainer {
        let schema = Schema([Playlist.self, Channel.self])
        return try ModelContainer(for: schema, configurations: [ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)])
    }
}

// MARK: - Testmedien (stumm)

enum B06Media {
    struct Set {
        let dir: URL
        let ts: Data
        let tsDuration: Double
        let hlsSegments: [Data]
        let shortTS: Data
        var tsRate: Double { Double(ts.count) / tsDuration }
    }

    private static var cached: Set?

    static func ffmpeg() -> String? {
        ["/opt/homebrew/bin/ffmpeg", "/usr/local/bin/ffmpeg"].first { FileManager.default.isExecutableFile(atPath: $0) }
    }

    @discardableResult
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

    /// Erzeugt (einmal je Rechner) stumme Testmedien und prüft, dass keine Datei eine Audiospur hat.
    static func ensure() throws -> Set {
        if let cached { return cached }
        guard let ff = ffmpeg() else { throw XCTSkip("ffmpeg fehlt – B06-Streamtests brauchen stumme Testmedien") }
        let probe = ff.replacingOccurrences(of: "ffmpeg", with: "ffprobe")
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("b06-qa-media-v2", isDirectory: true)
        let fm = FileManager.default
        let hls = dir.appendingPathComponent("hls", isDirectory: true)
        let src = dir.appendingPathComponent("src.ts")
        let clip = dir.appendingPathComponent("clip.mp4")
        let short = dir.appendingPathComponent("short.ts")
        if !fm.fileExists(atPath: dir.appendingPathComponent("fertig").path) {
            try? fm.removeItem(at: dir)
            try fm.createDirectory(at: hls, withIntermediateDirectories: true)
            let video = ["-hide_banner", "-loglevel", "error", "-y", "-f", "lavfi", "-i", "testsrc2=size=480x270:rate=25"]
            let enc = ["-an", "-c:v", "libx264", "-preset", "veryfast", "-b:v", "400k", "-g", "50"]
            try run(ff, video + ["-t", "60"] + enc + ["-f", "mpegts", src.path])
            try run(ff, video + ["-t", "20"] + enc + ["-f", "hls", "-hls_time", "2", "-hls_list_size", "0",
                                                      "-hls_segment_filename", hls.appendingPathComponent("seg%03d.ts").path,
                                                      hls.appendingPathComponent("vod.m3u8").path])
            try run(ff, video + ["-t", "10"] + enc + ["-movflags", "+faststart", clip.path])
            try run(ff, video + ["-t", "8"] + enc + ["-f", "mpegts", short.path])
            fm.createFile(atPath: dir.appendingPathComponent("fertig").path, contents: Data())
        }
        // Tonspur-Prüfung: jede Datei muss 0 Audioströme und genau einen Videostrom haben.
        let segs = try fm.contentsOfDirectory(atPath: hls.path).filter { $0.hasSuffix(".ts") }.sorted()
        for f in [src.path, clip.path, short.path] + segs.map({ hls.appendingPathComponent($0).path }) {
            let audio = try run(probe, ["-v", "error", "-select_streams", "a", "-show_entries", "stream=index", "-of", "csv=p=0", f])
                .split(separator: "\n").filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
            guard audio.isEmpty else { throw NSError(domain: "B06Media", code: 1, userInfo: [NSLocalizedDescriptionKey: "Audiospur in \(f) – Abbruch (kein Ton erlaubt)"]) }
        }
        let duration = Double(try run(probe, ["-v", "error", "-show_entries", "format=duration", "-of", "csv=p=0", src.path])
            .trimmingCharacters(in: .whitespacesAndNewlines)) ?? 60
        let set = Set(dir: dir, ts: try Data(contentsOf: src), tsDuration: duration,
                      hlsSegments: try segs.map { try Data(contentsOf: hls.appendingPathComponent($0)) },
                      shortTS: try Data(contentsOf: short))
        cached = set
        return set
    }
}

// MARK: - Lokaler Stream-Mock

/// HTTP-Mock auf 127.0.0.1 für stumme Testmedien. Schreibt jede Anfrage und jede Verbindung mit
/// (geöffnet, geschlossen, gesendete Bytes je Sekunde).
///
/// Routen (Pfad ohne Query):
/// `/hls/vod.m3u8`, `/hls/segNNN.ts` · `/clip.mp4` · `/static/src.ts` · `/livehls/<id>/index.m3u8|.m3u`, `/livehls/<id>/segN.ts`
/// · `/tslive/<id>[.ext]` roher TS in Echtzeit · `/401/…` (mit WWW-Authenticate) · `/403/…` · `/404/…` · `/html/…`
/// · `/hang/…` · `/delay/<s>/<rest>` (nur erste Anfrage je Pfad) · `/abort/<s>/tslive/…` · `/abort/<s>/livehls/<id>/…`
/// · `/m3uplaylist/list.m3u` · `/live/<user>/<pass>/<id>.ts|.m3u8` (Xtream-Form), `/live/<u>/<p>/404/<id>.<ext>`
/// · `/stall/<s>/tslive/…` roher TS, der nach s Sekunden verstummt, ohne die Verbindung zu schließen (Build B06 · BUG-01)
final class B06StreamServer: @unchecked Sendable {
    struct Request: Sendable {
        let conn: Int
        let time: Date
        let method: String
        let target: String
        let path: String
        let headers: [String: String]
        var userAgent: String { headers["user-agent"] ?? "" }
        var range: String { headers["range"] ?? "" }
    }

    struct Connection: Sendable {
        let id: Int
        let opened: Date
        let closed: Date?
        let path: String
        let bytesSent: Int
        let samples: [Sample]
        let closeReason: String?

        /// Gesendete Bytes im Zeitfenster [from, to].
        func bytes(from: Date, to: Date) -> Int {
            let before = samples.last { $0.time <= from }?.bytes ?? 0
            let atEnd = samples.last { $0.time <= to }?.bytes ?? bytesSent
            return max(0, atEnd - before)
        }
    }

    struct Sample: Sendable {
        let time: Date
        let bytes: Int
    }

    private final class State {
        let id: Int
        let conn: NWConnection
        let opened = Date()
        var closed: Date?
        var closeReason: String?
        var path = ""
        var bytesSent = 0
        var samples: [Sample] = []
        var timer: DispatchSourceTimer?
        var inFlight = false
        var streamStart: Date?
        var pos = 0
        var limit: TimeInterval?
        /// Build B06 · BUG-01: nach so vielen Sekunden nichts mehr senden, Verbindung aber offen lassen.
        var stallAfter: TimeInterval?
        var streaming = false
        init(id: Int, conn: NWConnection) { self.id = id; self.conn = conn }
    }

    let media: B06Media.Set
    private let queue = DispatchQueue(label: "b06.stream.mock")
    private var listener: NWListener?
    private(set) var port: UInt16 = 0
    private var nextID = 0
    private var states: [Int: State] = [:]
    private var _requests: [Request] = []
    private var firstSeen: [String: Date] = [:]
    private let started = Date()

    init(media: B06Media.Set) { self.media = media }

    var base: String { "http://127.0.0.1:\(port)" }
    func url(_ path: String) -> URL { URL(string: base + path)! }

    var requests: [Request] { queue.sync { _requests } }
    var connections: [Connection] {
        queue.sync {
            states.values.sorted { $0.id < $1.id }.map {
                Connection(id: $0.id, opened: $0.opened, closed: $0.closed, path: $0.path, bytesSent: $0.bytesSent,
                           samples: $0.samples, closeReason: $0.closeReason)
            }
        }
    }

    func requests(containing s: String) -> [Request] { requests.filter { $0.target.contains(s) } }
    func connections(containing s: String) -> [Connection] { connections.filter { $0.path.contains(s) } }

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
            throw NSError(domain: "B06StreamServer", code: 1, userInfo: [NSLocalizedDescriptionKey: "Listener nicht bereit"])
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
        st.samples.append(Sample(time: Date(), bytes: st.bytesSent))
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

    /// Nur für Streams/Hänger: wartet auf das Schließen durch den Client.
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
        _requests.append(Request(conn: st.id, time: Date(), method: method, target: target, path: path, headers: headers))
        route(st, path: path, headers: headers, head: method == "HEAD", leftover: leftover)
    }

    private func route(_ st: State, path: String, headers: [String: String], head: Bool, leftover: Data) {
        let p = path.split(separator: "/").map(String.init)
        guard let first = p.first else { return status(st, 404, leftover: leftover) }
        switch first {
        case "delay" where p.count >= 3:
            let secs = Double(p[1]) ?? 0
            let key = p.dropLast().joined(separator: "/")
            let seen = firstSeen[key] != nil
            if !seen { firstSeen[key] = Date() }
            let rest = "/" + p.dropFirst(2).joined(separator: "/")
            if seen {
                route(st, path: rest, headers: headers, head: head, leftover: leftover)
            } else {
                // kein paralleles receive während der Wartezeit (sonst zwei ausstehende receive-Aufrufe)
                queue.asyncAfter(deadline: .now() + secs) { [weak self] in
                    guard let self, st.closed == nil else { return }
                    self.route(st, path: rest, headers: headers, head: head, leftover: leftover)
                }
            }
        case "abort" where p.count >= 3:
            let secs = Double(p[1]) ?? 0
            if p[2] == "tslive" { return realtime(st, limit: secs) }
            if p[2] == "livehls" {
                let key = p.prefix(4).joined(separator: "/")
                let firstTime = firstSeen[key] ?? Date()
                if firstSeen[key] == nil { firstSeen[key] = firstTime }
                if Date().timeIntervalSince(firstTime) >= secs { return close(st, "abort-livehls") }
                return route(st, path: "/" + p.dropFirst(2).joined(separator: "/"), headers: headers, head: head, leftover: leftover)
            }
            status(st, 404, leftover: leftover)
        case "stall" where p.count >= 3 && p[2] == "tslive":
            realtime(st, limit: nil, stallAfter: Double(p[1]) ?? 0)
        case "hls" where p.count == 2:
            if p[1] == "vod.m3u8" {
                send(st, 200, "application/vnd.apple.mpegurl", (try? Data(contentsOf: media.dir.appendingPathComponent("hls/vod.m3u8"))) ?? Data(), leftover: leftover)
            } else if let d = try? Data(contentsOf: media.dir.appendingPathComponent("hls/\(p[1])")) {
                send(st, 200, "video/mp2t", d, leftover: leftover)
            } else { status(st, 404, leftover: leftover) }
        case "clip.mp4":
            ranged(st, (try? Data(contentsOf: media.dir.appendingPathComponent("clip.mp4"))) ?? Data(), "video/mp4", headers, leftover: leftover)
        case "static":
            ranged(st, p.last == "short.ts" ? media.shortTS : media.ts, "video/mp2t", headers, leftover: leftover)
        case "livehls" where p.count >= 3:
            livehls(st, last: p.last!, leftover: leftover)
        case "tslive":
            realtime(st, limit: nil)
        case "401":
            send(st, 401, "text/html", Data("<html><body>401</body></html>".utf8), extra: ["WWW-Authenticate": "Basic realm=\"B06-QA\""], leftover: leftover)
        case "403":
            send(st, 403, "text/html", Data("<html><body>403</body></html>".utf8), leftover: leftover)
        case "404":
            status(st, 404, leftover: leftover)
        case "html":
            let page = String(repeating: "<!doctype html><html><head><title>Portal</title></head><body><p>Bitte anmelden</p></body></html>", count: 20)
            send(st, 200, "text/html; charset=utf-8", Data(page.utf8), leftover: leftover)
        case "hang":
            watchEOF(st)
        case "m3uplaylist":
            let body = "#EXTM3U\n#EXTINF:-1 tvg-id=\"a\",Sender A\n\(base)/hls/vod.m3u8\n#EXTINF:-1 tvg-id=\"b\",Sender B\n\(base)/clip.mp4\n"
            send(st, 200, "audio/x-mpegurl", Data(body.utf8), leftover: leftover)
        case "live" where p.count >= 4:
            if p[3] == "404" { return status(st, 404, leftover: leftover) }
            let last = p.last!
            if last.hasSuffix(".m3u8") || last.range(of: #"^seg\d+\.ts$"#, options: .regularExpression) != nil {
                return livehls(st, last: last, leftover: leftover)
            }
            realtime(st, limit: nil)
        default:
            status(st, 404, leftover: leftover)
        }
    }

    private func livehls(_ st: State, last: String, leftover: Data) {
        if last.hasSuffix(".m3u8") || last.hasSuffix(".m3u") {
            let seq = Int(Date().timeIntervalSince(started) / 2.0)
            var lines = ["#EXTM3U", "#EXT-X-VERSION:3", "#EXT-X-TARGETDURATION:2", "#EXT-X-MEDIA-SEQUENCE:\(seq)"]
            for i in seq..<(seq + 6) { lines += ["#EXTINF:2.000000,", String(format: "seg%05d.ts", i)] }
            send(st, 200, "application/vnd.apple.mpegurl", Data((lines.joined(separator: "\n") + "\n").utf8),
                 extra: ["Cache-Control": "no-cache"], leftover: leftover)
        } else if let r = last.range(of: #"\d+"#, options: .regularExpression), let n = Int(last[r]), !media.hlsSegments.isEmpty {
            send(st, 200, "video/mp2t", media.hlsSegments[n % media.hlsSegments.count], leftover: leftover)
        } else {
            status(st, 404, leftover: leftover)
        }
    }

    private func status(_ st: State, _ code: Int, leftover: Data) {
        send(st, code, "text/html", Data("<html><body><h1>\(code)</h1></body></html>".utf8), leftover: leftover)
    }

    private func ranged(_ st: State, _ data: Data, _ ctype: String, _ headers: [String: String], leftover: Data) {
        let rng = headers["range"] ?? ""
        if let m = rng.range(of: #"^bytes=(\d*)-(\d*)$"#, options: .regularExpression) {
            let spec = String(rng[m]).dropFirst("bytes=".count)
            let ab = spec.split(separator: "-", omittingEmptySubsequences: false).map(String.init)
            var startIdx = 0, endIdx = data.count - 1
            if let a = Int(ab[0]) {
                startIdx = a
                if let b = Int(ab[1]) { endIdx = min(b, data.count - 1) }
            } else if let n = Int(ab[1]) {
                startIdx = max(0, data.count - n)
            }
            guard startIdx < data.count, startIdx <= endIdx else { return status(st, 416, leftover: leftover) }
            let part = data.subdata(in: startIdx..<(endIdx + 1))
            return send(st, 206, ctype, part, extra: ["Content-Range": "bytes \(startIdx)-\(endIdx)/\(data.count)", "Accept-Ranges": "bytes"], leftover: leftover)
        }
        send(st, 200, ctype, data, extra: ["Accept-Ranges": "bytes"], leftover: leftover)
    }

    /// Antwort mit Länge; danach bleibt die Verbindung für die nächste Anfrage offen (keep-alive).
    private func send(_ st: State, _ code: Int, _ ctype: String, _ body: Data, extra: [String: String] = [:], leftover: Data) {
        var head = "HTTP/1.1 \(code) B06\r\nContent-Type: \(ctype)\r\nContent-Length: \(body.count)\r\n"
        for (k, v) in extra { head += "\(k): \(v)\r\n" }
        head += "\r\n"
        var data = Data(head.utf8)
        data.append(body)
        st.conn.send(content: data, completion: .contentProcessed { [weak self] err in
            guard let self else { return }
            if err != nil { return self.markClosed(st, "send-error") }
            st.bytesSent += data.count
            st.samples.append(Sample(time: Date(), bytes: st.bytesSent))
            self.receive(st, buffer: leftover)
        })
    }

    /// Roher TS in Echtzeit (1 s Vorlauf), endlos bzw. bis `limit`; sendet nur weiter, wenn der Client liest.
    private func realtime(_ st: State, limit: TimeInterval?, stallAfter: TimeInterval? = nil) {
        st.streaming = true
        st.limit = limit
        st.stallAfter = stallAfter
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
        let now = Date()
        if st.samples.last.map({ now.timeIntervalSince($0.time) >= 1 }) ?? true {
            st.samples.append(Sample(time: now, bytes: st.bytesSent))
        }
        let elapsed = now.timeIntervalSince(t0)
        if let limit = st.limit, elapsed >= limit { return close(st, "abort-after-\(Int(limit))s") }
        if let stall = st.stallAfter, elapsed >= stall { return }
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
/// `VLCMediaPlayer`). So lassen sich auch Engines prüfen, die `PlayerView` intern als `@State` hält.
@MainActor
enum B06Registry {
    final class Weak { weak var obj: AnyObject?; let created = Date(); init(_ o: AnyObject?) { obj = o } }
    private(set) static var avPlayers: [Weak] = []
    private(set) static var vlcPlayers: [Weak] = []
    private(set) static var vlcEngines: [Weak] = []
    private static var installed = false

    static func install() {
        guard !installed else { return }
        installed = true
        swizzleSetter(AVPlayerLayer.self, "setPlayer:") { obj, arg in
            if let p = arg as? AVPlayer, !(avPlayers.contains { $0.obj === p }) { avPlayers.append(Weak(p)) }
            _ = obj
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
            if Thread.isMainThread { MainActor.assumeIsolated { record(obj, arg) } }
            orig(obj, sel, arg)
        }
        method_setImplementation(m, imp_implementationWithBlock(block))
    }

    static func reset() {
        avPlayers.removeAll()
        vlcPlayers.removeAll()
        vlcEngines.removeAll()
    }

    static var liveAVPlayers: [AVPlayer] { avPlayers.compactMap { $0.obj as? AVPlayer } }
    static var liveVLCEngines: [any PlaybackEngine] { vlcEngines.compactMap { $0.obj as? any PlaybackEngine } }
    static var liveVLCPlayers: [NSObject] { vlcPlayers.compactMap { $0.obj as? NSObject } }

    /// Beendet alles, was noch lebt (nur Testaufräumen, nicht Teil der geprüften Logik).
    static func stopAll() {
        for p in liveAVPlayers { p.isMuted = true; p.pause(); p.replaceCurrentItem(with: nil) }
        for v in liveVLCPlayers { _ = v.perform(NSSelectorFromString("stop")) }
    }
}

@MainActor
enum B06Engine {
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

    static func vlcState(_ v: NSObject) -> String {
        let raw = (v.value(forKey: "state") as? NSNumber)?.intValue ?? -1
        return raw >= 0 && raw < vlcStates.count ? vlcStates[raw] : "\(raw)"
    }

    static func vlcIsPlaying(_ v: NSObject) -> Bool { (v.value(forKey: "playing") as? NSNumber)?.boolValue ?? false }

    static func vlcAudio(_ v: NSObject) -> (volume: Int?, muted: Bool?) {
        let audio = v.value(forKey: "audio") as? NSObject
        return ((audio?.value(forKey: "volume") as? NSNumber)?.intValue, (audio?.value(forKey: "muted") as? NSNumber)?.boolValue)
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
            return "av rate=\(p.rate) item=\(st) vol=\(p.volume) muted=\(p.isMuted)"
        }
        if let v = vlcPlayer(e) {
            let a = vlcAudio(v)
            return "vlc state=\(vlcState(v)) isPlaying=\((v.value(forKey: "playing") as? NSNumber)?.boolValue ?? false) audio.volume=\(a.volume.map(String.init) ?? "-") audio.muted=\(a.muted.map { $0 ? "1" : "0" } ?? "-")"
        }
        return "?"
    }

    /// Wartet, bis `probe` wahr ist; gibt die Wartezeit zurück oder nil bei Zeitablauf.
    static func wait(_ timeout: TimeInterval, step: TimeInterval = 0.05, _ probe: () -> Bool) async -> TimeInterval? {
        let t0 = Date()
        while Date().timeIntervalSince(t0) < timeout {
            if probe() { return Date().timeIntervalSince(t0) }
            await B06QA.spin(step)
        }
        return probe() ? Date().timeIntervalSince(t0) : nil
    }

    /// Beobachtet den Zustand und protokolliert jeden Wechsel; Rückgabe: Liste (Sekunde, Zustand).
    static func watch(_ label: String, _ e: any PlaybackEngine, seconds: TimeInterval) async -> [(TimeInterval, String)] {
        var out: [(TimeInterval, String)] = []
        let t0 = Date()
        var last = ""
        while true {
            let t = Date().timeIntervalSince(t0)
            let s = name(e.state)
            if s != last {
                last = s
                out.append((t, s))
                B06QA.log("\(label)|t=\(B06QA.f1(t))s|state=\(s)|\(detail(e))")
            }
            if t >= seconds { break }
            await B06QA.spin(0.05)
        }
        return out
    }
}

// MARK: - Beep-Wächter

/// Ersetzt `-[NSResponder noResponderFor:]` (der Weg zum Systembeep bei unbehandelten Tasten) durch eine
/// Protokollzeile. Die Tests senden nur belegte Tasten; der Wächter macht einen Fehler hörbar still und sichtbar.
@MainActor
enum B06BeepGuard {
    private(set) static var hits: [String] = []
    private static var installed = false

    @discardableResult
    static func install() -> Bool {
        if installed { return true }
        let sel = NSSelectorFromString("noResponderFor:")
        let block: @convention(block) (AnyObject, Selector) -> Void = { obj, event in
            // AppKit beept nur für keyDown:; andere Ereignisse (mouseExited:, flagsChanged:) nur protokollieren.
            let name = NSStringFromSelector(event)
            let line = (name == "keyDown:" ? "SYSTEMBEEP-UNTERDRUECKT " : "ohne-Empfaenger ") + "\(type(of: obj)) \(name)"
            if name == "keyDown:", Thread.isMainThread { MainActor.assumeIsolated { hits.append(line) } }
            print("B06QA|\(line)")
        }
        let imp = imp_implementationWithBlock(block)
        var replaced = Set<String>()
        for cls in [NSResponder.self, NSView.self, NSWindow.self, NSApplication.self] as [AnyClass] {
            guard let m = class_getInstanceMethod(cls, sel) else { continue }
            let key = "\(method_getImplementation(m))"
            if replaced.contains(key) { continue }
            method_setImplementation(m, imp)
            replaced.insert("\(imp)")
        }
        // Prüfen: alle vier Klassen landen bei der Ersatz-Implementierung.
        installed = [NSResponder.self, NSView.self, NSWindow.self, NSApplication.self].allSatisfy {
            class_getMethodImplementation($0, sel) == imp
        }
        return installed
    }

    static func reset() { hits.removeAll() }
}

// MARK: - Fenster, Accessibility, Tasten

@MainActor
enum B06UI {
    static func window<V: View>(_ view: V, size: CGSize = CGSize(width: 640, height: 400),
                                origin: CGPoint = CGPoint(x: 80, y: 120), title: String = "B06-QA") -> NSWindow {
        let w = NSWindow(contentRect: NSRect(origin: origin, size: size),
                         styleMask: [.titled, .closable, .resizable, .miniaturizable], backing: .buffered, defer: false)
        w.isReleasedWhenClosed = false
        w.title = title
        w.collectionBehavior.insert(.fullScreenPrimary)
        w.contentView = NSHostingView(rootView: view)
        w.makeKeyAndOrderFront(nil)
        return w
    }

    static func close(_ w: NSWindow) {
        if w.styleMask.contains(.fullScreen) { w.toggleFullScreen(nil) }
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

    static func role(_ e: NSObject) -> String { text(e, "accessibilityRole") }
    static func label(_ e: NSObject) -> String {
        [text(e, "accessibilityLabel"), text(e, "accessibilityTitle"), text(e, "accessibilityValue"), text(e, "accessibilityIdentifier")]
            .filter { !$0.isEmpty }.joined(separator: " | ")
    }

    static func kids(_ e: NSObject) -> [NSObject] { (obj(e, "accessibilityChildren") as? [Any] ?? []).compactMap { $0 as? NSObject } }

    static func all(_ root: NSObject, depth: Int = 0, into list: inout [(Int, NSObject)]) {
        guard depth < 60 else { return }
        list.append((depth, root))
        for k in kids(root) { all(k, depth: depth + 1, into: &list) }
    }

    static func elements(_ w: NSWindow) -> [NSObject] {
        guard let v = w.contentView else { return [] }
        _ = v.accessibilityHitTest(NSPoint(x: w.frame.midX, y: w.frame.midY))
        var l: [(Int, NSObject)] = []
        all(v, into: &l)
        return l.map(\.1)
    }

    static func labels(_ w: NSWindow) -> [String] {
        elements(w).map { "\(role($0)):\(label($0))" }
    }

    static func dump(_ w: NSWindow, _ tag: String) {
        guard let v = w.contentView else { return }
        var l: [(Int, NSObject)] = []
        all(v, into: &l)
        for (d, e) in l { B06QA.log("AX|\(tag)|\(String(repeating: "  ", count: d))\(role(e)) \(label(e)) frame=\(frame(e))") }
    }

    static func find(_ w: NSWindow, role r: String? = nil, _ t: String) -> NSObject? {
        elements(w).first { (r == nil || role($0) == r) && label($0).contains(t) }
    }

    static func has(_ w: NSWindow, _ t: String) -> Bool { find(w, t) != nil }

    static func frame(_ e: NSObject) -> NSRect {
        let sel = NSSelectorFromString("accessibilityFrame")
        guard e.responds(to: sel), let imp = e.method(for: sel) else { return .zero }
        typealias F = @convention(c) (AnyObject, Selector) -> NSRect
        return unsafeBitCast(imp, to: F.self)(e, sel)
    }

    @discardableResult
    static func press(_ e: NSObject) -> Bool {
        let sel = NSSelectorFromString("accessibilityPerformPress")
        guard e.responds(to: sel), let imp = e.method(for: sel) else { return false }
        typealias F = @convention(c) (AnyObject, Selector) -> Bool
        return unsafeBitCast(imp, to: F.self)(e, sel)
    }

    /// Synthetischer Mausklick (Fensterkoordinaten, Ursprung unten links).
    static func click(_ w: NSWindow, at p: NSPoint) {
        for type in [NSEvent.EventType.leftMouseDown, .leftMouseUp] {
            let ev = NSEvent.mouseEvent(with: type, location: p, modifierFlags: [], timestamp: ProcessInfo.processInfo.systemUptime,
                                        windowNumber: w.windowNumber, context: nil, eventNumber: 0, clickCount: 1, pressure: 1)!
            w.sendEvent(ev)
        }
    }

    static func click(_ e: NSObject, in w: NSWindow) {
        let f = frame(e)
        click(w, at: w.convertPoint(fromScreen: NSPoint(x: f.midX, y: f.midY)))
    }

    /// Mausbewegung (Fensterkoordinaten, Ursprung unten links).
    static func move(_ w: NSWindow, to p: NSPoint) {
        let ev = NSEvent.mouseEvent(with: .mouseMoved, location: p, modifierFlags: [], timestamp: ProcessInfo.processInfo.systemUptime,
                                    windowNumber: w.windowNumber, context: nil, eventNumber: 0, clickCount: 0, pressure: 0)!
        w.sendEvent(ev)
    }

    enum Key {
        case space, up, down, escape, char(String)

        var code: UInt16 {
            switch self {
            case .space: return 49
            case .up: return 126
            case .down: return 125
            case .escape: return 53
            case .char(let c):
                switch c.lowercased() {
                case "m": return 46
                case "f": return 3
                case "p": return 35
                case "=", "+": return 24
                case "-": return 27
                default: return 0
                }
            }
        }

        var chars: String {
            switch self {
            case .space: return " "
            case .up: return String(UnicodeScalar(NSUpArrowFunctionKey)!)
            case .down: return String(UnicodeScalar(NSDownArrowFunctionKey)!)
            case .escape: return "\u{1B}"
            case .char(let c): return c
            }
        }
    }

    /// Nur belegte Tasten senden (kein Systembeep). `viaApp` geht über `NSApp.sendEvent` (Menü-Tastenkürzel zuerst).
    static func key(_ w: NSWindow, _ k: Key, flags: NSEvent.ModifierFlags = [], viaApp: Bool = false) {
        var ignoring = k.chars
        if case .char(let c) = k { ignoring = c.lowercased() == "+" ? "=" : c.lowercased() }
        // Nur keyDown: ein unbehandeltes keyUp liefe über noResponderFor: (Erkundung 2026-09-16).
        for type in [NSEvent.EventType.keyDown] {
            let ev = NSEvent.keyEvent(with: type, location: .zero, modifierFlags: flags, timestamp: ProcessInfo.processInfo.systemUptime,
                                      windowNumber: w.windowNumber, context: nil, characters: k.chars,
                                      charactersIgnoringModifiers: ignoring, isARepeat: false, keyCode: k.code)!
            if viaApp { NSApp.sendEvent(ev) } else { w.sendEvent(ev) }
        }
    }
}

// MARK: - Basisklasse

@MainActor
class B06TestCase: XCTestCase {
    var mock: B06StreamServer!
    var windows: [NSWindow] = []
    var engines: [any PlaybackEngine] = []
    var keychain: XtreamCredentialStore!

    override func setUp() async throws {
        try await super.setUp()
        let media = try B06Media.ensure()
        mock = B06StreamServer(media: media)
        try mock.start()
        B06Registry.install()
        keychain = XtreamCredentialStore(service: "lu.daumedia.MikaPlusPlayer.xtream.tests.b06.\(UUID().uuidString)")
        XCTAssertTrue(XtreamCredentialStore.standard.service.hasPrefix("lu.daumedia.MikaPlusPlayer.xtream.tests."),
                      "Tests dürfen nur den eigenen Schlüsselbund-Dienst benutzen")
    }

    override func tearDown() async throws {
        // Build B06 · BUG-01: kürzere VLC-Fristen gelten nur für den Test, der sie setzt.
        VLCPlaybackEngine.limitsForNewEngines = .standard
        for w in windows { B06UI.close(w) }
        windows.removeAll()
        for e in engines { e.setMuted(true); e.pause() }
        engines.removeAll()
        B06Registry.stopAll()
        // Warten, bis libVLC die Player wirklich abgebaut hat. Wird hier nicht gewartet, hängt der nächste Test beim
        // Erzeugen eines neuen `VLCMediaPlayer` im libVLC-Konfigurationslock (QA 2026-09-26, BUG-07: zweimal in zwei
        // Läufen am Übergang AK-09 → AK-10, Samples in features/B06-wiedergabe/qa/BUG-07-*.txt).
        let t0 = Date()
        var offen = B06Registry.liveVLCPlayers.count
        while offen > 0, Date().timeIntervalSince(t0) < 15 {
            await B06QA.spin(0.25)
            offen = B06Registry.liveVLCPlayers.count
        }
        B06QA.log("tearDown|VLC-Player abgebaut nach \(B06QA.f1(Date().timeIntervalSince(t0)))s|noch offen=\(offen)")
        B06Registry.reset()
        await B06QA.spin(0.5)
        mock?.stop()
        mock = nil
        try? keychain?.deleteAll()
        try? XtreamCredentialStore.standard.deleteAll()
        try await super.tearDown()
    }

    /// Engine über die Factory, **vor** dem Laden stumm.
    func mutedEngine(for url: URL) -> any PlaybackEngine {
        let e = PlaybackEngineFactory.engine(for: url)
        e.setMuted(true)
        engines.append(e)
        return e
    }

    /// Hängt die Videofläche in ein kleines Fenster (wie eingebettet in der App).
    func host(_ e: any PlaybackEngine, index: Int) {
        let col = index % 6, row = index / 6
        let w = B06UI.window(e.makePlayerView(), size: CGSize(width: 200, height: 112),
                             origin: CGPoint(x: 40 + CGFloat(col) * 210, y: 60 + CGFloat(row) * 150), title: "B06-Engine \(index)")
        windows.append(w)
    }
}
