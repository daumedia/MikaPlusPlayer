import XCTest
import SwiftUI
import SwiftData
import AppKit
import SQLite3
import Darwin
import CoreGraphics
@testable import MikaPlusPlayer

// B03 · Playlist-Verwaltung — gemeinsame Hilfen der QA (Durchlauf 1, 2026-09-16).
//
// Regeln für alle B03-Tests:
// - Datenbanken nur als Datei im Temp-Verzeichnis (über den Produktionsweg `AppPersistence.diskContainer`) oder
//   in-memory. Die Datenbank des Nutzers wird nie geöffnet; der Test-Host selbst arbeitet im Speicher.
// - Schlüsselbund nur über `XtreamCredentialStore.standard`, das im Test-Host einen eigenen Dienst je Lauf hat
//   (`lu.daumedia.MikaPlusPlayer.xtream.tests.<UUID>`); jeder Test leert ihn am Ende.
// - Anbieter nur als Mock auf 127.0.0.1 (`MockXtreamServer` aus Tests/Support), erfundene Zugangsdaten
//   (`qa-user` / `qa-pass-b03…`).
// - Tonlos: Stream-Pfade `/live/…` antworten nie (oder mit 404), M3U-Stream-Adressen zeigen auf den geschlossenen
//   Port 9. Keine Tastaturereignisse (unbehandelte Tasten würden piepen).

enum B03QA {
    static let dead = "http://127.0.0.1:9"
    typealias M3UEntry = (name: String, tvg: String?, group: String?, url: String)
    typealias XEntry = (name: String?, id: Int, epg: String?, cat: String?)

    static func log(_ s: String) { print("B03QA|\(s)") }
    static func f2(_ t: TimeInterval) -> String { String(format: "%.2f", t) }

    #if DEBUG
    static let buildConfiguration = "Debug"
    #else
    static let buildConfiguration = "Release"
    #endif

    /// Grundliste mit Namens- und tvg-ID-Dubletten.
    static let v1: [M3UEntry] = [
        ("Alpha", "alpha.id", "News", "\(dead)/a.m3u8"),
        ("Beta", nil, "News", "\(dead)/b.m3u8"),
        ("Sport HD", nil, "Sport", "\(dead)/s1.m3u8"),
        ("sport hd", nil, "Sport", "\(dead)/s2.m3u8"),
        ("Film HD", "film.id", "Film", "\(dead)/f1.m3u8"),
        ("Film SD", "film.id", "Film", "\(dead)/f2.m3u8"),
        ("Gamma", nil, "Doku", "\(dead)/g.m3u8")
    ]

    static func m3u(_ entries: [M3UEntry]) -> Data {
        var s = "#EXTM3U\n"
        for e in entries {
            var attrs = ""
            if let t = e.tvg { attrs += " tvg-id=\"\(t)\"" }
            if let g = e.group { attrs += " group-title=\"\(g)\"" }
            s += "#EXTINF:-1\(attrs),\(e.name)\n\(e.url)\n"
        }
        return Data(s.utf8)
    }

    static func streams(_ entries: [XEntry], logoPrefix: String? = nil) -> Data {
        let arr: [[String: Any]] = entries.map { e in
            var d: [String: Any] = ["stream_id": e.id]
            d["name"] = e.name ?? NSNull()
            d["epg_channel_id"] = e.epg ?? NSNull()
            d["category_id"] = e.cat ?? NSNull()
            if let logoPrefix { d["stream_icon"] = "\(logoPrefix)\(e.id).png" }
            return d
        }
        return try! JSONSerialization.data(withJSONObject: arr)
    }

    // MARK: SQLite (nur Test-Dateien)

    static func rows(_ path: String, _ sql: String) -> [[String]] {
        var db: OpaquePointer?
        guard sqlite3_open_v2(path, &db, SQLITE_OPEN_READONLY, nil) == SQLITE_OK else { sqlite3_close(db); return [] }
        defer { sqlite3_close(db) }
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return [] }
        defer { sqlite3_finalize(stmt) }
        var result: [[String]] = []
        while sqlite3_step(stmt) == SQLITE_ROW {
            var cols: [String] = []
            for i in 0..<sqlite3_column_count(stmt) {
                if let c = sqlite3_column_text(stmt, i) { cols.append(String(cString: c)) } else { cols.append("NULL") }
            }
            result.append(cols)
        }
        return result
    }

    static func int(_ path: String, _ sql: String) -> Int {
        Int(rows(path, sql).first?.first ?? "") ?? -1
    }

    /// Zeilen je Tabelle der Test-Datenbank.
    static func dbSummary(_ url: URL) -> String {
        let p = url.path
        return "ZPLAYLIST=\(int(p, "select count(*) from ZPLAYLIST"))"
            + "|ZCHANNEL=\(int(p, "select count(*) from ZCHANNEL"))"
            + "|ohnePlaylist=\(int(p, "select count(*) from ZCHANNEL where ZPLAYLIST is null"))"
            + "|favoriten=\(int(p, "select count(*) from ZCHANNEL where ZISFAVORITE = 1"))"
    }

    /// Summe der Vorkommen einer Bytefolge in Store, -wal, -shm.
    static func bytes(_ marker: String, _ storeURL: URL) -> Int {
        B01.rawOccurrences(of: marker, inFilesWithPrefix: storeURL).values.reduce(0, +)
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

    /// `features/B03-playlist-verwaltung/qa/` im Repository (aus dem Pfad dieser Datei).
    static var qaFolder: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("features/B03-playlist-verwaltung/qa", isDirectory: true)
    }

    static func appendEvidence(_ file: String, _ line: String) {
        let url = qaFolder.appendingPathComponent(file)
        try? FileManager.default.createDirectory(at: qaFolder, withIntermediateDirectories: true)
        let data = Data((line + "\n").utf8)
        if let h = try? FileHandle(forWritingTo: url) {
            h.seekToEndOfFile()
            h.write(data)
            try? h.close()
        } else {
            try? data.write(to: url)
        }
    }

    /// Offene TCP-Verbindungen des Test-Prozesses zu einem lokalen Port (lsof, nur lesend).
    static func establishedConnections(toPort port: UInt16) -> Int {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/sbin/lsof")
        p.arguments = ["-nP", "-a", "-p", "\(getpid())", "-iTCP@127.0.0.1:\(port)", "-sTCP:ESTABLISHED"]
        let pipe = Pipe()
        p.standardOutput = pipe
        p.standardError = Pipe()
        do { try p.run() } catch { return -1 }
        p.waitUntilExit()
        let out = String(decoding: pipe.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
        // Kopfzeile abziehen; jede Verbindung erscheint zweimal (Client- und Server-Seite im selben Prozess)
        let lines = out.split(separator: "\n").dropFirst()
        return lines.filter { $0.contains("->") }.count
    }
}

/// Konfigurierbares Verhalten des Mocks: M3U-Datei unter `*.m3u`, `player_api.php`, Stream-Pfade `/live/…`.
struct B03QAPanel {
    var m3u: Data? = nil
    var m3uStatus = 200
    var m3uDelay: TimeInterval = 0
    var auth: Data = try! JSONSerialization.data(withJSONObject: MockXtreamServer.okAuth)
    var authStatus = 200
    var categories: Data = try! JSONSerialization.data(withJSONObject: [
        ["category_id": "1", "category_name": "News"],
        ["category_id": "2", "category_name": "Sport"]
    ])
    var streams: Data = try! JSONSerialization.data(withJSONObject: MockXtreamServer.streams)
    var streamsStatus = 200
    var streamsDelay: TimeInterval = 0
    /// `nil` → Verbindung annehmen und nie antworten (stumm); sonst HTTP-Status ohne Inhalt
    var liveStatus: Int? = nil

    func handler() -> @Sendable (MockXtreamServer.Request) -> MockXtreamServer.Reply {
        let m3u = self.m3u, m3uStatus = self.m3uStatus, m3uDelay = self.m3uDelay
        let auth = self.auth, authStatus = self.authStatus, categories = self.categories, streams = self.streams
        let streamsStatus = self.streamsStatus, streamsDelay = self.streamsDelay, liveStatus = self.liveStatus
        return { req in
            if req.path.hasSuffix(".m3u") {
                guard let body = m3u else { return .raw(status: 404, contentType: "text/plain", body: Data("nicht gefunden".utf8)) }
                let r = MockXtreamServer.Reply.raw(status: m3uStatus, contentType: "audio/x-mpegurl", body: body)
                return m3uDelay > 0 ? .delayed(m3uDelay, r) : r
            }
            if req.path == "/player_api.php" {
                switch req.action {
                case nil: return .raw(status: authStatus, contentType: "application/json", body: auth)
                case "get_live_categories": return .raw(status: 200, contentType: "application/json", body: categories)
                case "get_live_streams":
                    let r = MockXtreamServer.Reply.raw(status: streamsStatus, contentType: "application/json", body: streams)
                    return streamsDelay > 0 ? .delayed(streamsDelay, r) : r
                default: return .raw(status: 200, contentType: "application/json", body: Data("[]".utf8))
                }
            }
            if req.path.hasPrefix("/live/") {
                if let liveStatus { return .raw(status: liveStatus, contentType: "text/plain", body: Data()) }
                return .hang
            }
            return .raw(status: 404, contentType: "text/plain", body: Data())
        }
    }
}

/// Misst, wie lange der Main-Thread höchstens nicht auf `DispatchQueue.main.async` reagiert.
final class B03QAWatchdog: @unchecked Sendable {
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
                _ = done.wait(timeout: .now() + 900)
                Thread.sleep(forTimeInterval: 0.02)
            }
        }
    }

    func stop() -> TimeInterval {
        lock.withLock { running = false; return maxGap }
    }
}

final class B03QACounter: @unchecked Sendable {
    private let lock = NSLock()
    private var n = 0
    func next() -> Int { lock.withLock { n += 1; return n } }
}

/// Basisklasse: frischer Mock je Test, Temp-Ordner, Aufräumen von Schlüsselbund (Test-Dienst) und Plattencache.
class B03QATestCase: XCTestCase {
    var mock: MockXtreamServer!
    var tempDirs: [URL] = []

    override func setUpWithError() throws {
        try super.setUpWithError()
        mock = MockXtreamServer()
        try mock.start()
        XCTAssertTrue(XtreamCredentialStore.standard.service.hasPrefix("lu.daumedia.MikaPlusPlayer.xtream.tests."),
                      "Tests dürfen nur den eigenen Schlüsselbund-Dienst benutzen")
    }

    override func tearDown() {
        if let mock {
            B01.removeCachedResponses(for: mock)
            mock.stop()
        }
        mock = nil
        for d in tempDirs { try? FileManager.default.removeItem(at: d) }
        tempDirs = []
        XCTAssertNoThrow(try XtreamCredentialStore.standard.deleteAll())
        super.tearDown()
    }

    func tempDir(_ label: String) throws -> URL {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("b03-qa-\(label)-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        tempDirs.append(dir)
        return dir
    }

    /// Datenbankdatei im Temp-Verzeichnis über den Produktionsweg (`AppPersistence.diskContainer`, Schema + Migrationsplan).
    @MainActor func fileContainer(_ label: String) throws -> (ModelContainer, URL) {
        let url = try tempDir(label).appendingPathComponent("MikaPlusPlayer.store")
        return (try AppPersistence.diskContainer(at: url, schema: AppSchema.schema), url)
    }

    var m3uAddress: String { "http://\(mock.hostPort)/list.m3u" }

    @MainActor func importM3U(_ ctx: ModelContext, entries: [B03QA.M3UEntry] = B03QA.v1, name: String = "QA M3U",
                              address: String? = nil) async throws -> Playlist {
        var cfg = B03QAPanel()
        cfg.m3u = B03QA.m3u(entries)
        mock.handler = cfg.handler()
        return try await PlaylistImporter(modelContext: ctx).importFromURL(address ?? m3uAddress, name: name)
    }

    @MainActor func importXtream(_ ctx: ModelContext, streams: Data? = nil, pass: String = "qa-pass-b03",
                                 output: XtreamOutput = .mpegts, name: String = "QA Xtream") async throws -> Playlist {
        var cfg = B03QAPanel()
        if let streams { cfg.streams = streams }
        mock.handler = cfg.handler()
        return try await PlaylistImporter(modelContext: ctx, loginThrottle: XtreamLoginThrottle()).importFromXtream(
            XtreamCredentials(host: mock.hostPort, username: "qa-user", password: pass), output: output, name: name)
    }

    @MainActor func refresh(_ p: Playlist, _ ctx: ModelContext, throttle: XtreamLoginThrottle = XtreamLoginThrottle(),
                            limits: XtreamClient.Limits = .standard) async throws {
        try await PlaylistImporter(modelContext: ctx, xtreamLimits: limits, loginThrottle: throttle).refresh(p)
    }

    @MainActor func favorites(_ p: Playlist) -> [String] {
        p.channels.filter(\.isFavorite).map(\.name).sorted()
    }

    @MainActor func waitFor<T>(_ what: String, timeout: TimeInterval = 5, _ probe: () -> T?) async throws -> T {
        let end = Date().addingTimeInterval(timeout)
        while Date() < end {
            if let v = probe() { return v }
            await B03UI.spin(0.05)
        }
        throw NSError(domain: "B03QA", code: 1, userInfo: [NSLocalizedDescriptionKey: "Zeitüberschreitung: \(what)"])
    }
}

// MARK: - Oberfläche (AppKit-Accessibility, synthetische Mausereignisse)

final class B03MenuBox: @unchecked Sendable {
    var titles: [String] = []
    var items: [NSMenuItem] = []
    var menu: NSMenu?
    var shown = 0
}

@MainActor
enum B03UI {
    static func window<V: View>(_ view: V, size: CGSize, origin: CGPoint = CGPoint(x: 80, y: 80)) -> NSWindow {
        let w = NSWindow(contentRect: NSRect(origin: origin, size: size),
                         styleMask: [.titled, .closable, .resizable], backing: .buffered, defer: false)
        w.isReleasedWhenClosed = false
        w.contentView = NSHostingView(rootView: view)
        w.makeKeyAndOrderFront(nil)
        return w
    }

    static func spin(_ seconds: TimeInterval) async {
        try? await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
    }

    // Accessibility
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
    static func role(_ e: NSObject) -> String { text(e, "accessibilityRole") }
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
    static func labels(_ w: NSWindow) -> [String] {
        guard let c = w.contentView else { return [] }
        wake(w)
        return all(c).map(label).filter { !$0.isEmpty }
    }
    static func element(_ w: NSWindow, _ text: String, role r: String? = nil) -> NSObject? {
        guard let c = w.contentView else { return nil }
        wake(w)
        let list = all(c)
        return list.first { (r == nil || role($0) == r) && label($0) == text }
            ?? list.first { (r == nil || role($0) == r) && label($0).contains(text) }
    }
    static func busyCount(_ w: NSWindow) -> Int {
        guard let c = w.contentView else { return -1 }
        wake(w)
        return all(c).filter { role($0).contains("ProgressIndicator") || role($0).contains("BusyIndicator") }.count
    }

    static func click(_ e: NSObject, in w: NSWindow) {
        let f = frame(e)
        let p = w.convertPoint(fromScreen: NSPoint(x: f.midX, y: f.midY))
        for type in [NSEvent.EventType.leftMouseDown, .leftMouseUp] {
            if let ev = NSEvent.mouseEvent(with: type, location: p, modifierFlags: [], timestamp: ProcessInfo.processInfo.systemUptime,
                                           windowNumber: w.windowNumber, context: nil, eventNumber: 0, clickCount: 1, pressure: 1) {
                w.sendEvent(ev)
            }
        }
    }

    /// Öffnet das Kontextmenü einer Karte per Rechtsklick, liest die Einträge, schließt das Menü und führt optional
    /// einen Eintrag aus.
    @discardableResult
    static func contextMenu(_ w: NSWindow, row: String, perform title: String? = nil, shot: String? = nil) async -> B03MenuBox {
        let box = B03MenuBox()
        guard let el = element(w, row) else {
            B03QA.log("UI|kontextmenue|zeile nicht gefunden: \(row)")
            return box
        }
        let f = frame(el)
        let pt = w.convertPoint(fromScreen: NSPoint(x: f.midX, y: f.midY))
        let obs = NotificationCenter.default.addObserver(forName: NSMenu.didBeginTrackingNotification, object: nil, queue: nil) { note in
            guard let menu = note.object as? NSMenu else { return }
            box.menu = menu
            box.shown += 1
            box.items = menu.items
            box.titles = menu.items.map { $0.isSeparatorItem ? "—" : $0.title }
            if let shot {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                    B03UI.shotMenu(shot)
                    menu.cancelTracking()
                }
            } else {
                DispatchQueue.main.async { menu.cancelTracking() }
            }
        }
        defer { NotificationCenter.default.removeObserver(obs) }
        if let down = NSEvent.mouseEvent(with: .rightMouseDown, location: pt, modifierFlags: [], timestamp: ProcessInfo.processInfo.systemUptime,
                                         windowNumber: w.windowNumber, context: nil, eventNumber: 0, clickCount: 1, pressure: 1) {
            w.sendEvent(down)
        }
        await spin(0.3)
        if let title, let menu = box.menu, let idx = menu.items.firstIndex(where: { $0.title == title }) {
            menu.performActionForItem(at: idx)
        }
        return box
    }

    /// Texte eines angehängten Sheets/Alerts.
    static func sheetTexts(_ sheet: NSWindow?) -> [String] {
        guard let root = sheet?.contentView else { return [] }
        var out: [String] = []
        func walk(_ v: NSView) {
            if let t = v as? NSTextField, !t.stringValue.isEmpty { out.append(t.stringValue) }
            if let b = v as? NSButton, !b.title.isEmpty { out.append(b.title) }
            v.subviews.forEach(walk)
        }
        walk(root)
        return out
    }

    static func pressButton(_ sheet: NSWindow?, _ title: String) -> Bool {
        guard let root = sheet?.contentView else { return false }
        var found: NSButton?
        func walk(_ v: NSView) {
            if found == nil, let b = v as? NSButton, b.title == title { found = b }
            v.subviews.forEach(walk)
        }
        walk(root)
        found?.performClick(nil)
        return found != nil
    }

    /// Fensteraufnahme (nur eigene Fenster) nach `features/B03-playlist-verwaltung/qa/<name>.png`.
    static func shot(_ w: NSWindow, _ name: String) {
        guard let img = CGWindowListCreateImage(.null, .optionIncludingWindow, CGWindowID(w.windowNumber),
                                                [.boundsIgnoreFraming, .nominalResolution]) else {
            B03QA.log("SHOT|\(name)|fehlgeschlagen")
            return
        }
        let rep = NSBitmapImageRep(cgImage: img)
        guard let data = rep.representation(using: .png, properties: [:]) else { return }
        try? FileManager.default.createDirectory(at: B03QA.qaFolder, withIntermediateDirectories: true)
        try? data.write(to: B03QA.qaFolder.appendingPathComponent("\(name).png"))
        B03QA.log("SHOT|\(name)|\(img.width)x\(img.height)")
    }

    /// Aufnahme des offenen Kontextmenüs (Fenster dieses Prozesses oberhalb der Normalebene).
    static func shotMenu(_ name: String) {
        let info = (CGWindowListCopyWindowInfo([.optionAll], kCGNullWindowID) as? [[String: Any]]) ?? []
        let mine = info.filter { ($0[kCGWindowOwnerPID as String] as? Int32) == getpid() }
        B03QA.log("SHOT|\(name)|eigeneFenster=\(mine.map { "\($0[kCGWindowLayer as String] ?? "-")/\($0[kCGWindowIsOnscreen as String] ?? "-")/\($0[kCGWindowName as String] ?? "")" })|appFenster=\(NSApp.windows.filter(\.isVisible).map { "\(type(of: $0)):\($0.level.rawValue)" })")
        let own = mine.filter { (($0[kCGWindowLayer as String] as? Int) ?? 0) > 0 && (($0[kCGWindowIsOnscreen as String] as? Bool) ?? false) }
        guard let menu = own.max(by: { ($0[kCGWindowLayer as String] as? Int ?? 0) < ($1[kCGWindowLayer as String] as? Int ?? 0) }),
              let id = menu[kCGWindowNumber as String] as? UInt32,
              let img = CGWindowListCreateImage(.null, .optionIncludingWindow, CGWindowID(id), [.boundsIgnoreFraming, .nominalResolution]) else {
            B03QA.log("SHOT|\(name)|kein Menüfenster (\(own.count))")
            return
        }
        let rep = NSBitmapImageRep(cgImage: img)
        guard let data = rep.representation(using: .png, properties: [:]) else { return }
        try? data.write(to: B03QA.qaFolder.appendingPathComponent("\(name).png"))
        B03QA.log("SHOT|\(name)|\(img.width)x\(img.height)")
    }

    static func closeStrayWindows() {
        for win in NSApp.windows where win.isVisible {
            let t = String(describing: Swift.type(of: win))
            if t.contains("SheetPresentationWindow") || t.contains("AlertPanel") { win.close() }
        }
    }
}
