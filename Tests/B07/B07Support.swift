import Foundation
import Network
import XCTest
import SwiftUI
import SwiftData
import AppKit
import AVFoundation
import AVKit
import ObjectiveC
@testable import MikaPlusPlayer

// B07 · Bild-in-Bild — gemeinsame Hilfen der QA (Durchlauf 1, 2026-09-26).
//
// Kein Ton: Alle Testmedien entstehen mit `ffmpeg -an` und werden vor der ersten Wiedergabe mit `ffprobe`
// geprüft (keine Audiospur, sonst Abbruch). Engines, die ein Test selbst erzeugt, werden vor `load` stumm
// geschaltet; Engines, die `PlayerView` erzeugt, spielen ausschließlich Medien ohne Tonspur. Tastenereignisse
// nur für belegte Tasten; ein Beep-Wächter ersetzt `noResponderFor:` (kein Systembeep, stattdessen Protokoll).
// Streams ausschließlich von 127.0.0.1 (`B07StreamServer`), Zugangsdaten erfunden (qa-user / qa-pass-123).
// Aufbau des Stream-Mocks nach dem Vorbild der B06-QA, als eigene Typen (B07…), damit dieser Ordner allein steht.

enum B07QA {
    static func log(_ s: String) {
        print("B07QA|\(stamp())|\(s)")
        fflush(stdout)
    }

    static func stamp() -> String {
        let f = DateFormatter()
        f.dateFormat = "HH:mm:ss.SSS"
        return f.string(from: Date())
    }

    static func f1(_ t: TimeInterval) -> String { String(format: "%.1f", t) }
    static func f2(_ t: Double) -> String { String(format: "%.2f", t) }

    static let user = "qa-user"
    static let pass = "qa-pass-123"

    /// `features/B07-bild-in-bild/qa/` neben den Tests (in der Kopie) — wird am Ende ins Repository übernommen.
    static var qaFolder: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("features/B07-bild-in-bild/qa", isDirectory: true)
    }

    /// Aufnahme eines **eigenen** Fensters (keine Berechtigung nötig, kein fremder Bildschirminhalt).
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

    @MainActor
    static func inMemoryContainer() throws -> ModelContainer {
        let schema = Schema([Playlist.self, Channel.self])
        return try ModelContainer(for: schema, configurations: [ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)])
    }

    /// Auftrag an den Helfer außerhalb des Test-Hosts (Shell der QA, `bridge.sh`). Er nimmt nur zwei Befehle an:
    /// `shot <fensternummer> <datei>` (Aufnahme **nur** dieses Fensters mit `screencapture -l`) und
    /// `front <pid>` (holt den Test-Host nach vorn). Ohne Helfer (Variable `B07_BRIDGE` fehlt) passiert nichts.
    @discardableResult
    static func bridge(_ line: String, timeout: TimeInterval = 10) async -> String? {
        guard let dir = ProcessInfo.processInfo.environment["B07_BRIDGE"] else {
            log("BRIDGE|kein Helfer|\(line)")
            return nil
        }
        let id = UUID().uuidString.prefix(8)
        let req = URL(fileURLWithPath: dir).appendingPathComponent("req-\(id).cmd")
        let done = URL(fileURLWithPath: dir).appendingPathComponent("req-\(id).done")
        try? line.write(to: req, atomically: true, encoding: .utf8)
        let t0 = Date()
        while Date().timeIntervalSince(t0) < timeout {
            if FileManager.default.fileExists(atPath: done.path) {
                let out = ((try? String(contentsOf: done, encoding: .utf8)) ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
                try? FileManager.default.removeItem(at: done)
                log("BRIDGE|\(line)|\(out)")
                return out
            }
            await spin(0.2)
        }
        try? FileManager.default.removeItem(at: req)
        log("BRIDGE|\(line)|Zeitablauf")
        return nil
    }

    /// Aufnahme nur des Fensters `windowID` (z. B. des Bild-in-Bild-Fensters) nach `qa/<name>.png`.
    @discardableResult
    static func requestWindowShot(_ windowID: Int, _ name: String) async -> Bool {
        let out = await bridge("shot \(windowID) \(qaFolder.appendingPathComponent(name + ".png").path)")
        return out?.hasPrefix("ok") ?? false
    }
}

// MARK: - Systemfenster „Bild-in-Bild“

/// Fenster anderer Prozesse, die das System für Bild-in-Bild zeigt (CGWindowList, nur Metadaten).
enum B07PiPWindows {
    struct Info: CustomStringConvertible {
        let id: Int
        let owner: String
        let ownerPID: Int
        let layer: Int
        let name: String
        let bounds: CGRect
        let sharing: Int
        let alpha: Double
        var description: String {
            "\(owner)[pid \(ownerPID)] id=\(id) layer=\(layer) name='\(name)' \(Int(bounds.width))x\(Int(bounds.height))@(\(Int(bounds.minX)),\(Int(bounds.minY))) sharing=\(sharing) alpha=\(alpha)"
        }
    }

    static func all(onScreen: Bool = true) -> [Info] {
        let opts: CGWindowListOption = onScreen ? [.optionOnScreenOnly] : [.optionAll]
        let list = CGWindowListCopyWindowInfo(opts, kCGNullWindowID) as? [[String: Any]] ?? []
        return list.map { w in
            let b = w[kCGWindowBounds as String] as? [String: Any] ?? [:]
            let rect = CGRect(x: b["X"] as? Double ?? 0, y: b["Y"] as? Double ?? 0,
                              width: b["Width"] as? Double ?? 0, height: b["Height"] as? Double ?? 0)
            return Info(id: w[kCGWindowNumber as String] as? Int ?? 0,
                        owner: w[kCGWindowOwnerName as String] as? String ?? "?",
                        ownerPID: w[kCGWindowOwnerPID as String] as? Int ?? 0,
                        layer: w[kCGWindowLayer as String] as? Int ?? 0,
                        name: w[kCGWindowName as String] as? String ?? "",
                        bounds: rect,
                        sharing: w[kCGWindowSharingState as String] as? Int ?? -1,
                        alpha: w[kCGWindowAlpha as String] as? Double ?? -1)
        }
    }

    /// Das schwebende Bild-in-Bild-Fenster: Besitzer „Bild-in-Bild“ / „Picture in Picture“ / PIPAgent,
    /// sichtbar, größer als ein Symbol.
    static func current() -> [Info] {
        all().filter { i in
            let o = i.owner.lowercased()
            return (o.contains("bild-in-bild") || o.contains("picture in picture") || o.contains("pip"))
                && i.bounds.width > 80 && i.bounds.height > 45
        }
    }
}

// MARK: - Testmedien (stumm)

enum B07Media {
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

    /// Temp-Ordner des Test-Hosts; wird am Ende der QA gelöscht.
    static var dir: URL { FileManager.default.temporaryDirectory.appendingPathComponent("b07-qa-media-v1", isDirectory: true) }

    /// Erzeugt (einmal) stumme Testmedien und prüft, dass keine Datei eine Audiospur hat.
    static func ensure() throws -> Set {
        if let cached { return cached }
        guard let ff = ffmpeg() else { throw XCTSkip("ffmpeg fehlt – B07-Streamtests brauchen stumme Testmedien") }
        let probe = ff.replacingOccurrences(of: "ffmpeg", with: "ffprobe")
        let fm = FileManager.default
        let hls = dir.appendingPathComponent("hls", isDirectory: true)
        let src = dir.appendingPathComponent("src.ts")
        if !fm.fileExists(atPath: dir.appendingPathComponent("fertig").path) {
            try? fm.removeItem(at: dir)
            try fm.createDirectory(at: hls, withIntermediateDirectories: true)
            let video = ["-hide_banner", "-loglevel", "error", "-y", "-f", "lavfi", "-i", "testsrc2=size=480x270:rate=25"]
            let enc = ["-an", "-c:v", "libx264", "-preset", "veryfast", "-b:v", "400k", "-g", "50"]
            try run(ff, video + ["-t", "60"] + enc + ["-f", "mpegts", src.path])
            try run(ff, video + ["-t", "40"] + enc + ["-f", "hls", "-hls_time", "2", "-hls_list_size", "0",
                                                      "-hls_segment_filename", hls.appendingPathComponent("seg%03d.ts").path,
                                                      hls.appendingPathComponent("vod.m3u8").path])
            fm.createFile(atPath: dir.appendingPathComponent("fertig").path, contents: Data())
        }
        let segs = try fm.contentsOfDirectory(atPath: hls.path).filter { $0.hasSuffix(".ts") }.sorted()
        for f in [src.path] + segs.map({ hls.appendingPathComponent($0).path }) {
            let audio = try run(probe, ["-v", "error", "-select_streams", "a", "-show_entries", "stream=index", "-of", "csv=p=0", f])
                .split(separator: "\n").filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
            guard audio.isEmpty else {
                throw NSError(domain: "B07Media", code: 1, userInfo: [NSLocalizedDescriptionKey: "Audiospur in \(f) – Abbruch (kein Ton erlaubt)"])
            }
        }
        let duration = Double(try run(probe, ["-v", "error", "-show_entries", "format=duration", "-of", "csv=p=0", src.path])
            .trimmingCharacters(in: .whitespacesAndNewlines)) ?? 60
        let set = Set(dir: dir, ts: try Data(contentsOf: src), tsDuration: duration,
                      hlsSegments: try segs.map { try Data(contentsOf: hls.appendingPathComponent($0)) })
        cached = set
        return set
    }
}

// MARK: - Lokaler Stream-Mock

/// HTTP-Mock auf 127.0.0.1 für stumme Testmedien; schreibt jede Anfrage und Verbindung mit.
///
/// Routen (Pfad ohne Query):
/// `/hls/vod.m3u8`, `/hls/segNNN.ts` · `/livehls/<id>/index.m3u8|.m3u|index`, `/livehls/<id>/segN.ts`
/// · `/tslive/<id>[.ext]` roher TS in Echtzeit · `/404/…` · `/delay/<s>/<rest>` (nur erste Anfrage je Pfad)
/// · `/abort/<s>/livehls/<id>/…` (ab `s` Sekunden nach der ersten Anfrage Verbindungsabbruch)
/// · `/live/<user>/<pass>/<id>.m3u8|.ts` (Xtream-Form; `.m3u8` als Live-HLS, sonst roher TS)
final class B07StreamServer: @unchecked Sendable {
    struct Request: Sendable {
        let conn: Int
        let time: Date
        let method: String
        let target: String
        let path: String
        let headers: [String: String]
    }

    struct Connection: Sendable {
        let id: Int
        let opened: Date
        let closed: Date?
        let path: String
        let bytesSent: Int
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
        init(id: Int, conn: NWConnection) { self.id = id; self.conn = conn }
    }

    let media: B07Media.Set
    private let queue = DispatchQueue(label: "b07.stream.mock")
    private var listener: NWListener?
    private(set) var port: UInt16 = 0
    private var nextID = 0
    private var states: [Int: State] = [:]
    private var _requests: [Request] = []
    private var firstSeen: [String: Date] = [:]
    private let started = Date()

    init(media: B07Media.Set) { self.media = media }

    var base: String { "http://127.0.0.1:\(port)" }
    func url(_ path: String) -> URL { URL(string: base + path)! }

    var requests: [Request] { queue.sync { _requests } }
    var connections: [Connection] {
        queue.sync {
            states.values.sorted { $0.id < $1.id }.map {
                Connection(id: $0.id, opened: $0.opened, closed: $0.closed, path: $0.path, bytesSent: $0.bytesSent)
            }
        }
    }

    func requests(containing s: String, since: Date = .distantPast) -> [Request] {
        requests.filter { $0.target.contains(s) && $0.time >= since }
    }
    /// Segmentabrufe (Live-HLS) eines Senders im Zeitfenster.
    func segments(_ id: String, from: Date, to: Date = .distantFuture) -> Int {
        requests.filter { $0.path.contains("/\(id)/") && $0.path.hasSuffix(".ts") && $0.time >= from && $0.time <= to }.count
    }
    func openConnections(containing s: String) -> [Connection] { connections.filter { $0.path.contains(s) && $0.closed == nil } }

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
            throw NSError(domain: "B07StreamServer", code: 1, userInfo: [NSLocalizedDescriptionKey: "Listener nicht bereit"])
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

    private func accept(_ c: NWConnection) {
        nextID += 1
        let st = State(id: nextID, conn: c)
        states[st.id] = st
        c.stateUpdateHandler = { [weak self, weak st] s in
            guard let self, let st else { return }
            switch s {
            case .failed: self.markClosed(st, "failed")
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
        _requests.append(Request(conn: st.id, time: Date(), method: method, target: target, path: path, headers: headers))
        route(st, path: path, headers: headers, leftover: leftover)
    }

    private func route(_ st: State, path: String, headers: [String: String], leftover: Data) {
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
                route(st, path: rest, headers: headers, leftover: leftover)
            } else {
                queue.asyncAfter(deadline: .now() + secs) { [weak self] in
                    guard let self, st.closed == nil else { return }
                    self.route(st, path: rest, headers: headers, leftover: leftover)
                }
            }
        case "abort" where p.count >= 4 && p[2] == "livehls":
            let secs = Double(p[1]) ?? 0
            let key = p.prefix(4).joined(separator: "/")
            let firstTime = firstSeen[key] ?? Date()
            if firstSeen[key] == nil { firstSeen[key] = firstTime }
            let since = Date().timeIntervalSince(firstTime)
            // Störung von `secs` bis `secs + 45` Sekunden (Verbindung wird ohne Antwort geschlossen), danach wieder Daten.
            if since >= secs && since < secs + 45 { return close(st, "abort") }
            route(st, path: "/" + p.dropFirst(2).joined(separator: "/"), headers: headers, leftover: leftover)
        case "hls" where p.count == 2:
            if p[1] == "vod.m3u8" {
                send(st, 200, "application/vnd.apple.mpegurl", (try? Data(contentsOf: media.dir.appendingPathComponent("hls/vod.m3u8"))) ?? Data(), leftover: leftover)
            } else if let d = try? Data(contentsOf: media.dir.appendingPathComponent("hls/\(p[1])")) {
                send(st, 200, "video/mp2t", d, leftover: leftover)
            } else { status(st, 404, leftover: leftover) }
        case "livehls" where p.count >= 3:
            livehls(st, last: p.last!, leftover: leftover)
        case "tslive":
            realtime(st)
        case "404":
            status(st, 404, leftover: leftover)
        case "live" where p.count >= 4:
            let last = p.last!
            if last.hasSuffix(".m3u8") || last.range(of: #"^seg\d+\.ts$"#, options: .regularExpression) != nil {
                return livehls(st, last: last, leftover: leftover)
            }
            realtime(st)
        default:
            status(st, 404, leftover: leftover)
        }
    }

    private func livehls(_ st: State, last: String, leftover: Data) {
        let isPlaylist = last.hasSuffix(".m3u8") || last.hasSuffix(".m3u") || last == "index"
        if isPlaylist {
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

    private func send(_ st: State, _ code: Int, _ ctype: String, _ body: Data, extra: [String: String] = [:], leftover: Data) {
        var head = "HTTP/1.1 \(code) B07\r\nContent-Type: \(ctype)\r\nContent-Length: \(body.count)\r\n"
        for (k, v) in extra { head += "\(k): \(v)\r\n" }
        head += "\r\n"
        var data = Data(head.utf8)
        data.append(body)
        st.conn.send(content: data, completion: .contentProcessed { [weak self] err in
            guard let self else { return }
            if err != nil { return self.markClosed(st, "send-error") }
            st.bytesSent += data.count
            self.receive(st, buffer: leftover)
        })
    }

    /// Roher TS in Echtzeit (1 s Vorlauf), endlos; sendet nur weiter, wenn der Client liest.
    private func realtime(_ st: State) {
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
        guard st.closed == nil, let t0 = st.streamStart, !st.inFlight else { return }
        let elapsed = Date().timeIntervalSince(t0)
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

// MARK: - Engines und PiP-Controller von außen beobachten

/// Merkt sich jeden `AVPlayer`, den ein `AVPlayerLayer` bekommt, und jeden `AVPictureInPictureController`
/// samt Delegate. Über den Delegate (`PiPDelegate.engine`, schwach) erreicht der Test die Engine, die
/// `PlayerView` als `@State` hält – ohne den Produktcode zu ändern.
@MainActor
enum B07Registry {
    final class Weak { weak var obj: AnyObject?; let created = Date(); init(_ o: AnyObject?) { obj = o } }
    private(set) static var avPlayers: [Weak] = []
    private(set) static var controllers: [Weak] = []
    private(set) static var delegates: [Weak] = []
    private static var installed = false

    static func install() {
        guard !installed else { return }
        installed = true
        swizzleSetter(AVPlayerLayer.self, "setPlayer:") { _, arg in
            if let p = arg as? AVPlayer, !(avPlayers.contains { $0.obj === p }) { avPlayers.append(Weak(p)) }
        }
        swizzleSetter(AVPictureInPictureController.self, "setDelegate:") { obj, arg in
            if !(controllers.contains { $0.obj === obj }) { controllers.append(Weak(obj)) }
            if let arg, !(delegates.contains { $0.obj === arg }) { delegates.append(Weak(arg)) }
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
        controllers.removeAll()
        delegates.removeAll()
    }

    static var liveAVPlayers: [AVPlayer] { avPlayers.compactMap { $0.obj as? AVPlayer } }
    static var liveControllers: [AVPictureInPictureController] { controllers.compactMap { $0.obj as? AVPictureInPictureController } }
    static var liveDelegates: [NSObject] { delegates.compactMap { $0.obj as? NSObject } }

    /// Engines, die über einen PiP-Delegate erreichbar sind (in Anlage-Reihenfolge).
    static var engines: [AVKitPlaybackEngine] {
        liveDelegates.compactMap { d in
            guard let v = B07Engine.child(d, "engine") else { return nil }
            if let e = v as? AVKitPlaybackEngine { return e }
            if let o = v as? AVKitPlaybackEngine? { return o }
            return nil
        }
    }

    /// Beendet alles, was noch lebt (nur Testaufräumen, nicht Teil der geprüften Logik).
    static func stopAll() {
        for c in liveControllers where c.isPictureInPictureActive { c.stopPictureInPicture() }
        for p in liveAVPlayers { p.isMuted = true; p.pause(); p.replaceCurrentItem(with: nil) }
    }
}

@MainActor
enum B07Engine {
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
            if let c = cur.children.first(where: { $0.label == label || $0.label == "_" + label }) {
                // Optional auspacken
                let mm = Mirror(reflecting: c.value)
                if mm.displayStyle == .optional { return mm.children.first?.value }
                return c.value
            }
            m = cur.superclassMirror
        }
        return nil
    }

    static func avPlayer(_ e: any PlaybackEngine) -> AVPlayer? { child(e, "player") as? AVPlayer }
    static func pipController(_ e: any PlaybackEngine) -> AVPictureInPictureController? { child(e, "pipController") as? AVPictureInPictureController }

    static func detail(_ e: any PlaybackEngine) -> String {
        var s = "type=\(type(of: e)) state=\(name(e.state)) isPaused=\(e.isPaused) pipActive=\(e.isPictureInPictureActive) supports=\(e.supportsPictureInPicture)"
        if let p = avPlayer(e) { s += " rate=\(p.rate) tcs=\(p.timeControlStatus.rawValue) muted=\(p.isMuted)" }
        if let c = pipController(e) { s += " ctrl.active=\(c.isPictureInPictureActive) ctrl.possible=\(c.isPictureInPicturePossible)" }
        return s
    }

    /// Wartet, bis `probe` wahr ist; gibt die Wartezeit zurück oder nil bei Zeitablauf.
    static func wait(_ timeout: TimeInterval, step: TimeInterval = 0.05, _ probe: () -> Bool) async -> TimeInterval? {
        let t0 = Date()
        while Date().timeIntervalSince(t0) < timeout {
            if probe() { return Date().timeIntervalSince(t0) }
            await B07QA.spin(step)
        }
        return probe() ? Date().timeIntervalSince(t0) : nil
    }
}

// MARK: - Beep-Wächter

/// Ersetzt `-[NSResponder noResponderFor:]` (der Weg zum Systembeep bei unbehandelten Tasten) durch eine
/// Protokollzeile. So bleibt jeder Fehlgriff stumm und wird trotzdem sichtbar.
@MainActor
enum B07BeepGuard {
    private(set) static var hits: [String] = []
    /// Eine einzige Ersatz-Implementierung für alle Aufrufe. `install()` prüft bei jedem Aufruf, ob sie noch gilt
    /// (ein Wächter aus einem anderen Testordner kann sie im selben Lauf ersetzt haben) und setzt sie sonst erneut.
    private static let guardIMP: IMP = {
        let block: @convention(block) (AnyObject, Selector) -> Void = { obj, event in
            let name = NSStringFromSelector(event)
            let line = (name == "keyDown:" ? "SYSTEMBEEP-UNTERDRUECKT " : "ohne-Empfaenger ") + "\(type(of: obj)) \(name)"
            if name == "keyDown:", Thread.isMainThread { MainActor.assumeIsolated { hits.append(line) } }
            print("B07QA|\(line)")
        }
        return imp_implementationWithBlock(block)
    }()

    @discardableResult
    static func install() -> Bool {
        let sel = NSSelectorFromString("noResponderFor:")
        let classes = [NSResponder.self, NSView.self, NSWindow.self, NSApplication.self] as [AnyClass]
        for cls in classes where class_getMethodImplementation(cls, sel) != guardIMP {
            guard let m = class_getInstanceMethod(cls, sel) else { continue }
            method_setImplementation(m, guardIMP)
        }
        return classes.allSatisfy { class_getMethodImplementation($0, sel) == guardIMP }
    }

    static func reset() { hits.removeAll() }
}

// MARK: - Fenster, Accessibility, Tasten

@MainActor
enum B07UI {
    static func window<V: View>(_ view: V, size: CGSize = CGSize(width: 640, height: 400),
                                origin: CGPoint = CGPoint(x: 80, y: 120), title: String = "B07-QA") -> NSWindow {
        let w = NSWindow(contentRect: NSRect(origin: origin, size: size),
                         styleMask: [.titled, .closable, .resizable, .miniaturizable], backing: .buffered, defer: false)
        w.isReleasedWhenClosed = false
        w.title = title
        let host = NSHostingView(rootView: view)
        host.sizingOptions = []   // Fenstergröße nicht dem Inhalt anpassen (Test-Host, nicht App-Verhalten)
        w.contentView = host
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
    static func help(_ e: NSObject) -> String { text(e, "accessibilityHelp") }

    static func kids(_ e: NSObject) -> [NSObject] { (obj(e, "accessibilityChildren") as? [Any] ?? []).compactMap { $0 as? NSObject } }

    static func all(_ root: NSObject, depth: Int = 0, into list: inout [(Int, NSObject)]) {
        guard depth < 60 else { return }
        list.append((depth, root))
        for k in kids(root) { all(k, depth: depth + 1, into: &list) }
    }

    /// Elemente des Fensters: Inhalt **und** Titelleiste/Toolbar (für „Zurück“).
    static func elements(_ w: NSWindow, includeFrame: Bool = false) -> [NSObject] {
        var l: [(Int, NSObject)] = []
        if includeFrame, let frameView = w.contentView?.superview {
            all(frameView, into: &l)
        } else if let v = w.contentView {
            _ = v.accessibilityHitTest(NSPoint(x: w.frame.midX, y: w.frame.midY))
            all(v, into: &l)
        }
        return l.map(\.1)
    }

    static func labels(_ w: NSWindow) -> [String] { elements(w).map { "\(role($0)):\(label($0))" } }

    static func dump(_ w: NSWindow, _ tag: String) {
        for e in elements(w) where !role(e).isEmpty {
            B07QA.log("AX|\(tag)|\(role(e)) \(label(e)) help='\(help(e))' frame=\(frame(e))")
        }
    }

    static func find(_ w: NSWindow, role r: String? = nil, _ t: String, includeFrame: Bool = false) -> NSObject? {
        elements(w, includeFrame: includeFrame).first { (r == nil || role($0) == r) && label($0).contains(t) }
    }

    static func buttons(_ w: NSWindow) -> [String] {
        elements(w).filter { role($0) == "AXButton" }.map(label)
    }

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

    enum Key {
        case space, char(String)

        var code: UInt16 {
            switch self {
            case .space: return 49
            case .char(let c):
                switch c.lowercased() {
                case "m": return 46
                case "p": return 35
                case "f": return 3
                default: return 0
                }
            }
        }

        var chars: String {
            switch self {
            case .space: return " "
            case .char(let c): return c
            }
        }
    }

    /// Nur belegte Tasten senden (kein Systembeep); nur keyDown (ein unbehandeltes keyUp liefe über noResponderFor:).
    static func key(_ w: NSWindow, _ k: Key, flags: NSEvent.ModifierFlags = []) {
        var ignoring = k.chars
        if case .char(let c) = k { ignoring = c.lowercased() }
        let ev = NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: flags, timestamp: ProcessInfo.processInfo.systemUptime,
                                  windowNumber: w.windowNumber, context: nil, characters: k.chars,
                                  charactersIgnoringModifiers: ignoring, isARepeat: false, keyCode: k.code)!
        w.sendEvent(ev)
    }
}

// MARK: - Navigation wie in der App

/// Navigationszustand, den der Test von außen steuert („Zurück“, erneut öffnen, Tabwechsel).
@MainActor @Observable
final class B07Nav {
    var path: [Channel] = []
    var tab = 0
}

/// Senderliste-Ersatz mit echtem `navigationDestination` wie in `ChannelListView`.
struct B07StackHost: View {
    @Bindable var nav: B07Nav
    var body: some View {
        NavigationStack(path: $nav.path) {
            Text("B07 Liste")
                .navigationDestination(for: Channel.self) { PlayerView(channel: $0) }
        }
    }
}

/// Zwei Tabs wie `ContentView`: Tab 0 mit Stapel, Tab 1 leer.
struct B07TabHost: View {
    @Bindable var nav: B07Nav
    var body: some View {
        TabView(selection: $nav.tab) {
            B07StackHost(nav: nav).tabItem { Text("Playlists") }.tag(0)
            Text("B07 Favoriten").tabItem { Text("Favoriten") }.tag(1)
        }
    }
}

// MARK: - Basisklasse

@MainActor
class B07TestCase: XCTestCase {
    var mock: B07StreamServer!
    var windows: [NSWindow] = []
    var engines: [any PlaybackEngine] = []
    var container: ModelContainer!
    var playlist: Playlist!

    override func setUp() async throws {
        try await super.setUp()
        let media = try B07Media.ensure()
        mock = B07StreamServer(media: media)
        try mock.start()
        B07Registry.install()
        B07Registry.reset()
        B07BeepGuard.reset()
        XCTAssertTrue(B07BeepGuard.install(), "Beep-Wächter muss aktiv sein, bevor Tasten gesendet werden")
        XCTAssertTrue(XtreamCredentialStore.standard.service.hasPrefix("lu.daumedia.MikaPlusPlayer.xtream.tests."),
                      "Tests dürfen nur den eigenen Schlüsselbund-Dienst benutzen")
        container = try B07QA.inMemoryContainer()
        playlist = Playlist(name: "QA M3U", sourceURL: mock.url("/list.m3u"))
        container.mainContext.insert(playlist)
        // Kein Rest eines vorigen Tests auf dem Bildschirm
        _ = await B07Engine.wait(6) { B07PiPWindows.current().isEmpty }
    }

    override func tearDown() async throws {
        if !B07BeepGuard.hits.isEmpty { B07QA.log("tearDown|unbehandelte Tasten (auch fremde, globale)=\(B07BeepGuard.hits)") }
        B07Registry.stopAll()
        for w in windows { B07UI.close(w) }
        windows.removeAll()
        for e in engines { e.setMuted(true); e.stopPictureInPicture(); e.pause() }
        engines.removeAll()
        _ = await B07Engine.wait(6) { B07PiPWindows.current().isEmpty }
        B07Registry.reset()
        await B07QA.spin(0.5)
        mock?.stop()
        mock = nil
        try? XtreamCredentialStore.standard.deleteAll()
        container = nil
        try await super.tearDown()
    }

    func channel(_ name: String, _ path: String, in p: Playlist? = nil) -> Channel {
        let pl = p ?? playlist!
        let c = Channel(name: name, streamURL: path.hasPrefix("/") ? mock.url(path) : URL(string: path)!, playlist: pl, playlistID: pl.id)
        container.mainContext.insert(c)
        return c
    }

    /// Engine über die Factory, **vor** dem Laden stumm.
    func mutedEngine(for url: URL) -> any PlaybackEngine {
        let e = PlaybackEngineFactory.engine(for: url)
        e.setMuted(true)
        engines.append(e)
        return e
    }

    /// `PlayerView` in einem `NavigationStack` (wie aus der Senderliste geöffnet).
    func playerWindow(_ c: Channel, origin: CGPoint = CGPoint(x: 80, y: 120),
                      size: CGSize = CGSize(width: 640, height: 400)) -> NSWindow {
        let w = B07UI.window(NavigationStack { PlayerView(channel: c) }.modelContainer(container), size: size, origin: origin)
        windows.append(w)
        return w
    }

    /// Tab-Stapel wie in der App; der Test öffnet/schließt den Player über `nav.path`.
    func stackWindow(_ nav: B07Nav, tabs: Bool = false, origin: CGPoint = CGPoint(x: 80, y: 120),
                     size: CGSize = CGSize(width: 640, height: 400)) -> NSWindow {
        let view: AnyView = tabs ? AnyView(B07TabHost(nav: nav)) : AnyView(B07StackHost(nav: nav))
        let w = B07UI.window(view.modelContainer(container), size: size, origin: origin)
        windows.append(w)
        return w
    }

    /// Holt den Test-Host nach vorn (für Tastenereignisse). Ohne Erfolg → Test übersprungen, nicht bestanden.
    func activate(_ w: NSWindow) async throws {
        w.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        if await B07Engine.wait(1.5, { NSApp.isActive }) == nil {
            await B07QA.bridge("front \(getpid())")
        }
        let ok = await B07Engine.wait(10) {
            if !NSApp.isActive { NSApp.activate(ignoringOtherApps: true) }
            if NSApp.isActive && NSApp.keyWindow !== w { w.makeKeyAndOrderFront(nil) }
            return NSApp.isActive && NSApp.keyWindow === w
        }
        if ok == nil { throw XCTSkip("Test-Host wurde nicht aktiv (keyWindow=\(String(describing: NSApp.keyWindow)))") }
    }

    /// PiP-Knopf (Symbol) im Fenster: „pip.enter“/„pip.exit“ bzw. deren Accessibility-Namen.
    func pipButton(_ w: NSWindow) -> NSObject? {
        B07UI.elements(w).first { e in
            guard B07UI.role(e) == "AXButton" else { return false }
            let l = B07UI.label(e).lowercased()
            return l.contains("pip") || l.contains("picture") || l.contains("bild-in-bild") || l.contains("minimi")
        }
    }

    func fullscreenButton(_ w: NSWindow) -> NSObject? {
        B07UI.elements(w).first { e in
            B07UI.role(e) == "AXButton" && (B07UI.label(e).contains("arrow.up.left.and.arrow.down.right")
                || B07UI.label(e).contains("arrow.down.right.and.arrow.up.left") || B07UI.label(e).lowercased().contains("full screen")
                || B07UI.label(e).lowercased().contains("vollbild"))
        }
    }

    func controlsVisible(_ w: NSWindow) -> Bool { fullscreenButton(w) != nil }

    /// Blendet die Steuerung per Klick aufs Bild ein (holt vorher den Test-Host nach vorn – parallele QA-Läufe
    /// holen ihre eigenen Fenster nach vorn). Rückgabe: sichtbar.
    @discardableResult
    func showControls(_ w: NSWindow) async -> Bool {
        for _ in 0..<4 {
            if controlsVisible(w) { return true }
            try? await activate(w)
            B07UI.click(w, at: NSPoint(x: w.frame.width / 2, y: w.frame.height / 2 - 40))
            if await B07Engine.wait(2, { self.controlsVisible(w) }) != nil { return true }
        }
        return controlsVisible(w)
    }

    /// Sendet eine belegte Taste an den Player und prüft, dass sie behandelt wurde (kein Systembeep).
    /// Rückgabe: unbehandelte Tastenereignisse unmittelbar danach.
    @discardableResult
    func press(_ w: NSWindow, _ k: B07UI.Key, flags: NSEvent.ModifierFlags = []) async -> [String] {
        try? await activate(w)
        B07BeepGuard.reset()
        B07UI.key(w, k, flags: flags)
        await B07QA.spin(0.3)
        let hits = B07BeepGuard.hits
        B07BeepGuard.reset()
        return hits
    }

    /// Engine des Players in `w` – über den PiP-Delegate (nur AVKit) bzw. die zuletzt angelegte.
    var lastEngine: AVKitPlaybackEngine? { B07Registry.engines.last }
}
