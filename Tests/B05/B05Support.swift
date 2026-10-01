import Foundation
import XCTest
import SwiftUI
import SwiftData
import AppKit
import SQLite3
import QuartzCore
@testable import MikaPlusPlayer

// B05 · Favoriten — gemeinsame Hilfen der QA (Durchlauf 1, 2026-09-26).
//
// Regeln für alle B05-Tests:
// - Datenbanken nur als Datei in einem eigenen Temp-Ordner (Produktionsweg `AppPersistence.diskContainer`) oder im
//   Speicher. Die Datenbank des Nutzers wird nie geöffnet; der Test-Host selbst arbeitet im Speicher.
// - Anbieter und Logo-Hosts nur als `MockXtreamServer` auf 127.0.0.1, erfundene Zugangsdaten (`qa-user` / `qa-pass-123`).
// - Tonlos: Stream-Adressen zeigen auf den geschlossenen Port 9, keine Tastaturereignisse (keine Systembeeps).
// - Fenster: Die Hosting-View steckt in einer Halter-View, sonst bestimmt sie die Fenstergröße und `LazyVStack`
//   realisiert keine Karten (Hinweis aus B04).
// - Nachweise (Aufnahmen, Messzeilen) landen nur mit `TEST_RUNNER_B05_EVIDENCE=1` in `features/B05-favoriten/qa/`,
//   sonst in einem Temp-Ordner.

enum B05QA {
    static let dead = "http://127.0.0.1:9"
    static let user = "qa-user"
    static let pass = "qa-pass-123"

    static func log(_ s: String) {
        print("B05QA|\(s)")
        fflush(stdout)
    }

    static func env(_ key: String) -> String? { ProcessInfo.processInfo.environment[key] }

    static var evidenceEnabled: Bool { env("B05_EVIDENCE") == "1" }

    /// `features/B05-favoriten/qa/` (aus dem Pfad dieser Datei) bzw. ein Temp-Ordner.
    static var qaFolder: URL {
        if evidenceEnabled {
            return URL(fileURLWithPath: #filePath)
                .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
                .appendingPathComponent("features/B05-favoriten/qa", isDirectory: true)
        }
        return FileManager.default.temporaryDirectory.appendingPathComponent("b05-qa-evidence", isDirectory: true)
    }

    /// Hängt eine Zeile an eine Nachweisdatei an (mit Zeitstempel und Konfiguration).
    static func evidence(_ file: String, _ line: String) {
        log("\(file)|\(line)")
        try? FileManager.default.createDirectory(at: qaFolder, withIntermediateDirectories: true)
        let url = qaFolder.appendingPathComponent(file)
        let stamp = ISO8601DateFormatter().string(from: Date())
        let data = Data("\(stamp) \(line)\n".utf8)
        if let h = try? FileHandle(forWritingTo: url) {
            h.seekToEndOfFile()
            h.write(data)
            try? h.close()
        } else {
            try? data.write(to: url)
        }
    }

    static func loadAverage() -> String {
        var load = [Double](repeating: 0, count: 3)
        return getloadavg(&load, 3) == 3 ? String(format: "%.1f/%.1f/%.1f", load[0], load[1], load[2]) : "-"
    }

    static func f1(_ t: Double) -> String { String(format: "%.1f", t) }

    // MARK: Datenbank

    @MainActor
    static func fileContainer(_ label: String) throws -> (container: ModelContainer, store: URL, dir: URL) {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("b05-qa-\(label)-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let url = dir.appendingPathComponent("MikaPlusPlayer.store")
        return (try AppPersistence.diskContainer(at: url, schema: AppSchema.schema), url, dir)
    }

    /// Öffnet eine vorhandene Datei neu (wie ein Neustart der App mit derselben Datenbank).
    @MainActor
    static func reopen(_ store: URL) throws -> ModelContainer {
        try AppPersistence.diskContainer(at: store, schema: AppSchema.schema)
    }

    @MainActor
    static func memoryContainer() throws -> ModelContainer {
        let schema = AppSchema.schema
        return try ModelContainer(for: schema, configurations: [ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)])
    }

    static func rows(_ path: String, _ sql: String) -> [[String]] {
        var db: OpaquePointer?
        guard sqlite3_open_v2(path, &db, SQLITE_OPEN_READONLY, nil) == SQLITE_OK else { sqlite3_close(db); return [["OPEN-FEHLER"]] }
        defer { sqlite3_close(db) }
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else {
            return [["SQL-FEHLER: " + String(cString: sqlite3_errmsg(db))]]
        }
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

    static func int(_ path: String, _ sql: String) -> Int { Int(rows(path, sql).first?.first ?? "") ?? -1 }

    static func sqlQuote(_ s: String) -> String { "'" + s.replacingOccurrences(of: "'", with: "''") + "'" }

    /// Wert von `ZISFAVORITE` eines Senders in der Datei („?“, wenn nicht gefunden).
    static func dbFavorite(_ store: URL, name: String) -> String {
        rows(store.path, "SELECT ZISFAVORITE FROM ZCHANNEL WHERE ZNAME = \(sqlQuote(name))").first?.first ?? "?"
    }

    static func rawOccurrences(_ marker: String, _ store: URL) -> [String: Int] {
        var result: [String: Int] = [:]
        let needle = Data(marker.utf8)
        for suffix in ["", "-wal", "-shm"] {
            let file = URL(fileURLWithPath: store.path + suffix)
            guard let data = try? Data(contentsOf: file) else { continue }
            var count = 0
            var range = data.startIndex..<data.endIndex
            while let found = data.range(of: needle, options: [], in: range) {
                count += 1
                range = found.upperBound..<data.endIndex
            }
            result[file.lastPathComponent] = count
        }
        return result
    }

    // MARK: Favoriten lesen

    /// `@Query(sort: \Channel.name)` erzeugt einen `SortDescriptor` über den generischen `Comparable`-Weg (ohne
    /// Kollation); `SortDescriptor(\Channel.name)` direkt wählte die String-Überladung (Finder-Sortierung).
    static func comparableSort<V: Comparable>(_ kp: KeyPath<Channel, V>) -> SortDescriptor<Channel> { SortDescriptor(kp) }

    /// Dieselbe Abfrage wie `FavoritesView` (Filter `isFavorite == true`, Sortierung `\Channel.name`).
    @MainActor
    static func tabQuery(_ ctx: ModelContext) throws -> [Channel] {
        try ctx.fetch(FetchDescriptor<Channel>(predicate: #Predicate { $0.isFavorite == true }, sortBy: [comparableSort(\Channel.name)]))
    }

    /// Favoriten als „Name@Playlist“, sortiert (für Vergleiche).
    @MainActor
    static func favLabels(_ ctx: ModelContext) throws -> [String] {
        try ctx.fetch(FetchDescriptor<Channel>(predicate: #Predicate { $0.isFavorite == true }))
            .map { "\($0.name)@\($0.playlist?.name ?? "-")" }.sorted()
    }

    /// Setzt den Stern wie `ChannelRowView` (umschalten, dann `save()`); `index` wählt unter gleichnamigen Sendern
    /// in Reihenfolge der Stream-Adresse.
    @MainActor
    static func setFavorite(_ playlist: Playlist, _ name: String, _ value: Bool = true, index: Int = 0,
                            ctx: ModelContext, file: StaticString = #filePath, line: UInt = #line) throws {
        let matches = playlist.channels.filter { $0.name == name }
            .sorted { $0.streamURL.absoluteString < $1.streamURL.absoluteString }
        guard index < matches.count else {
            XCTFail("Sender \(name)[\(index)] nicht gefunden", file: file, line: line)
            return
        }
        if matches[index].isFavorite != value { matches[index].isFavorite.toggle() }
        try ctx.save()
    }

    // MARK: M3U

    struct E {
        var name: String
        var tvg: String? = nil
        var url: String
        var group: String? = nil
        var logo: String? = nil
    }

    static func m3u(_ es: [E]) -> String {
        var s = "#EXTM3U\n"
        for e in es {
            var attrs = ""
            if let t = e.tvg { attrs += " tvg-id=\"\(t)\"" }
            if let l = e.logo { attrs += " tvg-logo=\"\(l)\"" }
            if let g = e.group { attrs += " group-title=\"\(g)\"" }
            s += "#EXTINF:-1\(attrs),\(e.name)\n\(e.url)\n"
        }
        return s
    }

    static func stream(_ n: Int) -> String { "\(dead)/b05/stream\(n).m3u8" }

    // MARK: Warten

    static func spin(_ seconds: TimeInterval) {
        RunLoop.main.run(until: Date().addingTimeInterval(seconds))
    }

    @discardableResult
    static func wait(_ timeout: TimeInterval, poll: TimeInterval = 0.05, _ condition: () -> Bool) -> Bool {
        let end = Date().addingTimeInterval(timeout)
        while Date() < end {
            if condition() { return true }
            spin(poll)
        }
        return condition()
    }

    static func ms(_ block: () throws -> Void) rethrows -> Double {
        let t0 = DispatchTime.now().uptimeNanoseconds
        try block()
        return Double(DispatchTime.now().uptimeNanoseconds - t0) / 1_000_000
    }
}

/// Zuordnung Pfad → Antwort für den M3U-Mock (thread-sicher).
final class B05Routes: @unchecked Sendable {
    private let lock = NSLock()
    private var map: [String: MockXtreamServer.Reply] = [:]
    func set(_ path: String, _ status: Int, _ text: String, delay: TimeInterval = 0) {
        let reply = MockXtreamServer.Reply.raw(status: status, contentType: "audio/x-mpegurl", body: Data(text.utf8))
        lock.withLock { map[path] = delay > 0 ? .delayed(delay, reply) : reply }
    }
    func setReply(_ path: String, _ reply: MockXtreamServer.Reply) { lock.withLock { map[path] = reply } }
    func get(_ path: String) -> MockXtreamServer.Reply? { lock.withLock { map[path] } }
}

/// Misst die längste Blockade des Main-Threads über einen 5-ms-Timer.
@MainActor
final class B05Heartbeat {
    private var stamps: [CFTimeInterval] = []
    private var timer: Timer?

    func start() {
        stamps = [CACurrentMediaTime()]
        let t = Timer(timeInterval: 0.005, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.stamps.append(CACurrentMediaTime()) }
        }
        RunLoop.main.add(t, forMode: .common)
        timer = t
    }

    func stopMaxGapMs() -> Double {
        timer?.invalidate()
        stamps.append(CACurrentMediaTime())
        var maxGap = 0.0
        for i in 1..<stamps.count { maxGap = max(maxGap, (stamps[i] - stamps[i - 1]) * 1000) }
        return maxGap
    }
}

// MARK: - Accessibility

@MainActor
enum B05AX {
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

    static func bool(_ e: NSObject, _ name: String) -> Bool? {
        let sel = NSSelectorFromString(name)
        guard e.responds(to: sel), let imp = e.method(for: sel) else { return nil }
        typealias F = @convention(c) (AnyObject, Selector) -> Bool
        return unsafeBitCast(imp, to: F.self)(e, sel)
    }

    static func role(_ e: NSObject) -> String { text(e, "accessibilityRole") }
    static func labelOnly(_ e: NSObject) -> String { text(e, "accessibilityLabel") }

    static func label(_ e: NSObject) -> String {
        [text(e, "accessibilityLabel"), text(e, "accessibilityTitle"), text(e, "accessibilityValue")]
            .filter { !$0.isEmpty }.joined(separator: " | ")
    }

    static func kids(_ e: NSObject) -> [NSObject] {
        (obj(e, "accessibilityChildren") as? [Any] ?? []).compactMap { $0 as? NSObject }
    }

    static func all(_ root: NSObject, depth: Int = 0) -> [NSObject] {
        guard depth < 60 else { return [] }
        return [root] + kids(root).flatMap { all($0, depth: depth + 1) }
    }

    @discardableResult
    static func press(_ e: NSObject) -> Bool { bool(e, "accessibilityPerformPress") ?? false }

    static func customActions(_ e: NSObject) -> [NSAccessibilityCustomAction] {
        (obj(e, "accessibilityCustomActions") as? [NSAccessibilityCustomAction]) ?? []
    }

    /// Führt eine benutzerdefinierte Aktion aus, wie VoiceOver es über das Aktionen-Menü tut.
    @discardableResult
    static func perform(_ action: NSAccessibilityCustomAction) -> Bool {
        if let h = action.handler { return h() }
        if let t = action.target as? NSObject, let sel = action.selector { t.perform(sel, with: action); return true }
        return false
    }

    static func describe(_ e: NSObject) -> String {
        "role=\(role(e))|label=\(text(e, "accessibilityLabel"))|title=\(text(e, "accessibilityTitle"))|value=\(text(e, "accessibilityValue"))"
            + "|help=\(text(e, "accessibilityHelp"))|roleDescription=\(text(e, "accessibilityRoleDescription"))"
            + "|selected=\(bool(e, "isAccessibilitySelected").map { String($0) } ?? "-")"
            + "|actions=\(customActions(e).map(\.name))"
    }

    static func tree(_ root: NSObject) -> [String] {
        var out: [String] = []
        func walk(_ e: NSObject, _ d: Int) {
            guard d < 60 else { return }
            let f = frame(e)
            out.append("\(String(repeating: " ", count: d))\(role(e)) \"\(label(e))\" \(Int(f.width))x\(Int(f.height))")
            for k in kids(e) { walk(k, d + 1) }
        }
        walk(root, 0)
        return out
    }

    static func views<T: NSView>(_ root: NSView, of type: T.Type) -> [T] {
        var out: [T] = []
        func walk(_ v: NSView) {
            if let t = v as? T { out.append(t) }
            v.subviews.forEach(walk)
        }
        walk(root)
        return out
    }
}

// MARK: - Fenster

/// Fenster mit einer beliebigen SwiftUI-Wurzel, eigenem Container und eigener Multiview-Session.
@MainActor
final class B05Window {
    let window: NSWindow
    let hosting: NSView

    init<V: View>(_ view: V, _ container: ModelContainer, size: CGSize = CGSize(width: 760, height: 620),
                  origin: CGPoint = CGPoint(x: 60, y: 60), multiview: MultiviewSession? = nil, borderless: Bool = false) {
        let root = view.environment(multiview ?? MultiviewSession()).modelContainer(container)
        let hv = NSHostingView(rootView: root)
        let w = NSWindow(contentRect: NSRect(origin: origin, size: size),
                         styleMask: borderless ? [.borderless] : [.titled, .closable, .resizable], backing: .buffered, defer: false)
        w.isReleasedWhenClosed = false
        hv.sizingOptions = []
        hv.sceneBridgingOptions = [.all]
        let holder = NSView(frame: NSRect(origin: .zero, size: size))
        hv.frame = holder.bounds
        hv.autoresizingMask = [.width, .height]
        holder.addSubview(hv)
        w.contentView = holder
        w.setContentSize(size)
        w.setFrameOrigin(NSPoint(x: origin.x, y: origin.y))
        w.makeKeyAndOrderFront(nil)
        window = w
        hosting = hv
        B05QA.spin(0.8)
        w.setContentSize(size)
        B05QA.spin(0.3)
    }

    func close() {
        if let sheet = window.attachedSheet { window.endSheet(sheet) }
        window.orderOut(nil)
        window.close()
    }

    /// Beschriftungen eines Alerts an diesem Fenster (SwiftUI `.alert` erscheint unter macOS als Sheet); leer ohne Alert.
    var alertTexts: [String] {
        guard let sheet = window.attachedSheet else { return [] }
        if let v = sheet.contentView { _ = v.accessibilityHitTest(NSPoint(x: sheet.frame.midX, y: sheet.frame.midY)) }
        return B05AX.all(sheet).map(B05AX.label).filter { !$0.isEmpty }
    }

    /// Bestätigt den Alert an diesem Fenster mit „OK“. Rückgabe: Taste gefunden und der Alert danach geschlossen.
    @discardableResult
    func confirmAlert(wait: TimeInterval = 0.6) -> Bool {
        guard let sheet = window.attachedSheet,
              let ok = B05AX.all(sheet).first(where: { B05AX.role($0) == "AXButton" && B05AX.label($0) == "OK" }) else { return false }
        _ = B05AX.press(ok)   // NSAlert-Tasten melden das Drücken nicht immer zurück; maßgeblich ist, ob der Alert zu ist
        B05QA.spin(wait)
        return window.attachedSheet == nil
    }

    func wake() { _ = hosting.accessibilityHitTest(NSPoint(x: window.frame.midX, y: window.frame.midY)) }

    var elements: [NSObject] {
        wake()
        return B05AX.all(hosting)
    }

    /// Tab-Knöpfe der Fenster-Toolbar (`AXTabGroup` „Navigation Tab Bar“): Titel → Element, Wert 1 = gewählt.
    var tabButtons: [(title: String, selected: Bool, element: NSObject)] {
        wake()
        return B05AX.all(window).filter { B05AX.role($0) == "AXRadioButton" }
            .map { (B05AX.text($0, "accessibilityLabel").isEmpty ? B05AX.text($0, "accessibilityTitle") : B05AX.text($0, "accessibilityLabel"),
                    B05AX.text($0, "accessibilityValue") == "1", $0) }
            .map { (title: $0.0, selected: $0.1, element: $0.2) }
    }

    @discardableResult
    func selectTab(_ title: String, wait: TimeInterval = 1.2) -> Bool {
        guard let t = tabButtons.first(where: { $0.title == title }) else { return false }
        let ok = B05AX.press(t.element)
        B05QA.spin(wait)
        return ok
    }

    /// Alle Beschriftungen (Label | Titel | Wert), von oben nach unten.
    var texts: [String] {
        elements.filter { !B05AX.label($0).isEmpty }
            .sorted { B05AX.frame($0).midY > B05AX.frame($1).midY }
            .map(B05AX.label)
    }

    var staticTexts: [String] {
        elements.filter { B05AX.role($0) == "AXStaticText" }
            .sorted { B05AX.frame($0).midY > B05AX.frame($1).midY }
            .map(B05AX.label)
    }

    /// Senderkarten (der `NavigationLink` ist EIN Element „Name, Gruppe“), oben zuerst.
    var cards: [(label: String, frame: NSRect, element: NSObject)] {
        elements.filter { e in
            let f = B05AX.frame(e)
            return ["AXButton", "AXBusyIndicator", "AXLink"].contains(B05AX.role(e)) && f.width > 200 && f.height > 40 && f.height < 140
        }
        .map { (B05AX.labelOnly($0), B05AX.frame($0), $0) }
        .sorted { $0.1.midY > $1.1.midY }
        .map { (label: $0.0, frame: $0.1, element: $0.2) }
    }

    var cardLabels: [String] { cards.map(\.label) }

    /// Karten, deren Beschriftung mit `name` beginnt („name“ oder „name, Gruppe“).
    func cards(named name: String) -> [(label: String, frame: NSRect, element: NSObject)] {
        cards.filter { $0.label == name || $0.label.hasPrefix(name + ", ") }
    }

    func card(_ name: String, index: Int = 0) -> (label: String, frame: NSRect, element: NSObject)? {
        let list = cards(named: name)
        return index < list.count ? list[index] : nil
    }

    /// Bildschirmpunkt des Sterns: rechter Kartenrand minus Innenabstand (14 pt) minus halbe Symbolbreite.
    func starPoint(_ name: String, index: Int = 0) -> NSPoint? {
        guard let c = card(name, index: index) else { return nil }
        return NSPoint(x: c.frame.maxX - 24, y: c.frame.midY)
    }

    func clickScreen(_ pt: NSPoint, clickCount: Int = 1) {
        let p = window.convertPoint(fromScreen: pt)
        for type in [NSEvent.EventType.leftMouseDown, .leftMouseUp] {
            if let ev = NSEvent.mouseEvent(with: type, location: p, modifierFlags: [],
                                           timestamp: ProcessInfo.processInfo.systemUptime,
                                           windowNumber: window.windowNumber, context: nil,
                                           eventNumber: 0, clickCount: clickCount, pressure: 1) {
                window.sendEvent(ev)
            }
        }
    }

    /// Klickt den Stern einer Karte (synthetischer Linksklick). Rückgabe: Karte gefunden.
    @discardableResult
    func clickStar(_ name: String, index: Int = 0, wait: TimeInterval = 0.6) -> Bool {
        guard let pt = starPoint(name, index: index) else { return false }
        clickScreen(pt)
        B05QA.spin(wait)
        return true
    }

    /// Klickt die Karte auf dem Namen (links, außerhalb von Stern und ⊞).
    @discardableResult
    func clickCardBody(_ name: String, index: Int = 0, wait: TimeInterval = 1.5) -> Bool {
        guard let c = card(name, index: index) else { return false }
        clickScreen(NSPoint(x: c.frame.minX + 120, y: c.frame.midY))
        B05QA.spin(wait)
        return true
    }

    /// Farbe des Sterns aus dem gerenderten Bild: „akzent“ (rot), „grau“ oder „?“.
    func starColor(_ name: String, index: Int = 0) -> String {
        guard let pt = starPoint(name, index: index), let v = window.contentView,
              let rep = v.bitmapImageRepForCachingDisplay(in: v.bounds) else { return "?" }
        v.cacheDisplay(in: v.bounds, to: rep)
        let pView = v.convert(window.convertPoint(fromScreen: pt), from: nil)
        let scale = CGFloat(rep.pixelsWide) / v.bounds.width
        var red = 0, gray = 0
        for dx in -10...10 {
            for dy in -10...10 {
                let x = Int((pView.x + CGFloat(dx)) * scale)
                let yFlipped = v.isFlipped ? pView.y + CGFloat(dy) : v.bounds.height - (pView.y + CGFloat(dy))
                let y = Int(yFlipped * scale)
                guard x >= 0, y >= 0, x < rep.pixelsWide, y < rep.pixelsHigh,
                      let col = rep.colorAt(x: x, y: y)?.usingColorSpace(.sRGB) else { continue }
                let r = col.redComponent, g = col.greenComponent, b = col.blueComponent
                if r - max(g, b) > 0.25 { red += 1 } else if abs(r - g) < 0.06 && abs(g - b) < 0.06 && r < 0.8 && r > 0.3 { gray += 1 }
            }
        }
        return red > 8 ? "akzent" : (gray > 8 ? "grau" : "?(r\(red)/g\(gray))")
    }

    /// Aufnahme des ganzen Fensters vom Bildschirm (mit Titelleiste und Tab-Leiste in der Toolbar). Offscreen gerendert
    /// erscheint das gewählte Segment der Tab-Leiste als weiße Fläche ohne Text – deshalb hier die Bildschirmaufnahme.
    func shotScreen(_ name: String) {
        guard let img = CGWindowListCreateImage(.null, .optionIncludingWindow, CGWindowID(window.windowNumber),
                                                [.boundsIgnoreFraming, .nominalResolution]),
              let data = NSBitmapImageRep(cgImage: img).representation(using: .png, properties: [:]) else { return }
        try? FileManager.default.createDirectory(at: B05QA.qaFolder, withIntermediateDirectories: true)
        try? data.write(to: B05QA.qaFolder.appendingPathComponent("\(name).png"))
        B05QA.log("SHOT|\(name).png|\(img.width)x\(img.height)|bildschirm")
    }

    /// Aufnahme des Fensterinhalts nach `qa/<name>.png`.
    func shot(_ name: String) {
        guard let v = window.contentView, let rep = v.bitmapImageRepForCachingDisplay(in: v.bounds) else { return }
        v.cacheDisplay(in: v.bounds, to: rep)
        guard let data = rep.representation(using: .png, properties: [:]) else { return }
        try? FileManager.default.createDirectory(at: B05QA.qaFolder, withIntermediateDirectories: true)
        try? data.write(to: B05QA.qaFolder.appendingPathComponent("\(name).png"))
        B05QA.log("SHOT|\(name).png|\(Int(v.bounds.width))x\(Int(v.bounds.height))")
    }
}

/// Sichtbare Alert- bzw. Sheet-Fenster der App (für „keine Meldung“).
@MainActor
func b05AlertWindows() -> [String] {
    NSApp.windows.filter { $0.isVisible && ($0 is NSPanel || String(describing: type(of: $0)).contains("Alert") || $0.attachedSheet != nil) }
        .map { String(describing: type(of: $0)) + ":" + $0.title }
}

// MARK: - Basisklasse

/// Mock je Test (M3U-Routen + Xtream-Panel + Logos), Temp-Ordner, Fenster; räumt Cache-Einträge des Mocks,
/// Fenster, Temp-Ordner und Schlüsselbund-Einträge des Test-Dienstes auf.
@MainActor
class B05TestCase: XCTestCase {
    var mock: MockXtreamServer!
    let routes = B05Routes()
    var windows: [B05Window] = []
    var dirs: [URL] = []

    override func setUpWithError() throws {
        try super.setUpWithError()
        continueAfterFailure = true
        mock = MockXtreamServer()
        try mock.start()
        let r = routes
        mock.handler = { req in
            if let reply = r.get(req.path) { return reply }
            return .raw(status: 404, contentType: "text/plain", body: Data())
        }
    }

    override func tearDown() {
        for w in windows { w.close() }
        windows = []
        B05QA.spin(0.3)
        if let mock {
            for req in mock.requests {
                if let url = URL(string: "http://\(mock.hostPort)\(req.target)") {
                    URLCache.shared.removeCachedResponse(for: URLRequest(url: url))
                }
            }
            mock.stop()
        }
        mock = nil
        try? XtreamCredentialStore.standard.deleteAll()
        if B05QA.env("B05_KEEP_STORES") != "1" {
            for d in dirs { try? FileManager.default.removeItem(at: d) }
        }
        dirs = []
        super.tearDown()
    }

    func window<V: View>(_ view: V, _ c: ModelContainer, size: CGSize = CGSize(width: 760, height: 620),
                         origin: CGPoint = CGPoint(x: 60, y: 60), borderless: Bool = false) -> B05Window {
        let w = B05Window(view, c, size: size, origin: origin, borderless: borderless)
        windows.append(w)
        return w
    }

    func fileContainer(_ label: String) throws -> (ModelContainer, URL) {
        let r = try B05QA.fileContainer(label)
        dirs.append(r.dir)
        return (r.container, r.store)
    }

    func url(_ path: String) -> String { "http://\(mock.hostPort)\(path)" }

    /// Import über den echten Pfad (`PlaylistImporter.importFromURL`).
    func importM3U(_ ctx: ModelContext, path: String, name: String, _ es: [B05QA.E]) async throws -> Playlist {
        routes.set(path, 200, B05QA.m3u(es))
        return try await PlaylistImporter(modelContext: ctx).importFromURL(url(path), name: name)
    }

    /// Aktualisieren über den echten Pfad (`PlaylistImporter.refresh`), die Quelle liefert `es`.
    func refreshM3U(_ ctx: ModelContext, _ pl: Playlist, path: String, _ es: [B05QA.E]) async throws {
        routes.set(path, 200, B05QA.m3u(es))
        try await PlaylistImporter(modelContext: ctx).refresh(pl)
    }

    /// Xtream-Panel mit `streams` auf `/player_api.php`, M3U-Routen bleiben erhalten.
    func installPanel(_ streams: [[String: Any]]) {
        let panel = MockXtreamServer.panel(streams: streams, categories: [
            ["category_id": "1", "category_name": "Deutschland"],
            ["category_id": "2", "category_name": "Sport"],
        ])
        let r = routes
        mock.handler = { req in
            if req.path == "/player_api.php" { return panel(req) }
            if let reply = r.get(req.path) { return reply }
            return .raw(status: 404, contentType: "text/plain", body: Data())
        }
    }

    func importXtream(_ ctx: ModelContext, name: String = "QA Xtream") async throws -> Playlist {
        let importer = PlaylistImporter(modelContext: ctx, loginThrottle: XtreamLoginThrottle())
        return try await importer.importFromXtream(
            XtreamCredentials(host: mock.hostPort, username: B05QA.user, password: B05QA.pass), output: .hls, name: name)
    }

    func refreshXtream(_ ctx: ModelContext, _ pl: Playlist) async throws {
        try await PlaylistImporter(modelContext: ctx, loginThrottle: XtreamLoginThrottle()).refresh(pl)
    }

    /// Legt Sender direkt an (Blöcke, `playlistID`, `channelCount`) – dieselben Zeilen wie der Import.
    @discardableResult
    func seed(_ ctx: ModelContext, name: String, _ items: [(name: String, group: String?, tvg: String?, fav: Bool, logo: String?)]) throws -> Playlist {
        let pl = Playlist(name: name)
        ctx.insert(pl)
        var batch: [Channel] = []
        for (i, it) in items.enumerated() {
            let ch = Channel(name: it.name, streamURL: URL(string: "\(B05QA.dead)/b05/\(pl.id.uuidString.prefix(8))/\(i).m3u8")!,
                             logoURL: it.logo.flatMap { URL(string: $0) }, group: it.group, tvgID: it.tvg,
                             isFavorite: it.fav, playlistID: pl.id)
            ctx.insert(ch)
            batch.append(ch)
        }
        pl.channels.append(contentsOf: batch)
        pl.channelCount = items.count
        try ctx.save()
        return pl
    }
}
