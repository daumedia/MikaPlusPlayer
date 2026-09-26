import XCTest
import SwiftUI
import SwiftData
import AppKit
@testable import MikaPlusPlayer

/// Basis für Oberflächentests mit den **echten Szenen** der App im Test-Host:
/// das echte Fenster „Multiview" (Szene `Window("Multiview", id: "multiview")`) samt der einen `MultiviewSession`
/// der App. Senderlisten laufen in Testfenstern mit derselben Session (`.environment(appSession)`), der ⊞-Button ruft
/// dort das echte `openWindow(id: "multiview")`.
///
/// Wichtig gegen den Absturz FB-01: Vor jedem Schließen und am Ende wird das Layout auf „Fokus" gestellt.
@MainActor
class B08UITestCase: B08TestCase {
    var container: ModelContainer!
    var appSession: MultiviewSession?
    /// Echtes Multiview-Fenster am Ende offen lassen (nur Neustart-Prüfung, Phase 1).
    var keepMultiviewOpen = false

    override func setUp() async throws {
        try await super.setUp()
        container = try B08QA.inMemoryContainer()
    }

    override func tearDown() async throws {
        if let s = appSession {
            // Erst das Layout wechseln und zeichnen lassen, dann leeren: Beides in einem Durchlauf stürzt im Raster ab (FB-01).
            s.layout = .focus
            await B08QA.spin(0.6)
            s.clear()
        }
        if !keepMultiviewOpen { for w in B08App.multiviewWindows() { w.performClose(nil) } }
        await B08QA.spin(0.4)
        appSession = nil
        try await super.tearDown()
    }

    // MARK: Echtes Multiview-Fenster

    /// Öffnet das echte Fenster über „Window › Multiview" und liefert es mit der Session der App.
    func openRealMultiview() async throws -> (NSWindow, MultiviewSession) {
        // AK-02: Öffnet sich das Fenster ohne gespeicherte Größe (erstes Öffnen unter dieser Bundle-ID), ist es 1280 × 720 pt.
        let savedFrame = UserDefaults.standard.string(forKey: "NSWindow Frame multiview")
        if B08App.multiviewWindows().isEmpty {
            XCTAssertTrue(B08App.openViaMenu(), "Menüeintrag Window › Multiview fehlt")
        }
        _ = await B08QA.wait(4) { !B08App.multiviewWindows().isEmpty }
        let w = try XCTUnwrap(B08App.multiviewWindows().first, "echtes Multiview-Fenster nicht sichtbar")
        if savedFrame == nil {
            B08QA.log("AK-02|erstes Öffnen ohne gespeicherte Größe|Titel „\(w.title)“|\(Int(w.frame.width)) x \(Int(w.frame.height)) pt|in \(name)")
            XCTAssertEqual(w.frame.size, CGSize(width: 1280, height: 720), "AK-02: erstes Öffnen 1280 × 720 pt")
        }
        let s = try XCTUnwrap(B08App.session(in: w), "Session der App nicht gefunden")
        appSession = s
        return (w, s)
    }

    func realWindow() -> NSWindow? { B08App.multiviewWindows().first }

    /// Setzt die App-Session in einen definierten Ausgangszustand (leer, Fokus).
    func resetAppSession() async throws -> (NSWindow, MultiviewSession) {
        let (w, s) = try await openRealMultiview()
        await safeClear(s)
        await B08QA.spin(0.3)
        return (w, s)
    }

    // MARK: Senderlisten mit ⊞

    /// M3U-Playlist mit Sendern auf dem Mock (Pfad je Sender), im Test-Container.
    func playlist(_ name: String, _ channels: [(String, String)], favorites: Bool = false) throws -> Playlist {
        let ctx = container.mainContext
        let p = Playlist(name: name, sourceURL: server.url("/list-\(name.count).m3u"))
        ctx.insert(p)
        for (n, path) in channels {
            let c = Channel(name: n, streamURL: server.url(path), group: "QA", isFavorite: favorites, playlist: p, playlistID: p.id)
            ctx.insert(c)
        }
        p.channelCount = channels.count
        try ctx.save()
        return p
    }

    func listWindow(_ p: Playlist, session: MultiviewSession, origin: CGPoint = CGPoint(x: 40, y: 60),
                    size: CGSize = CGSize(width: 520, height: 600)) -> NSWindow {
        track(B08UI.window(NavigationStack { ChannelListView(playlist: p) }.environment(session).modelContainer(container),
                           size: size, origin: origin, title: "B08-QA"))
    }

    func favoritesWindow(session: MultiviewSession, origin: CGPoint = CGPoint(x: 600, y: 60),
                         size: CGSize = CGSize(width: 520, height: 600)) -> NSWindow {
        track(B08UI.window(NavigationStack { FavoritesView() }.environment(session).modelContainer(container),
                           size: size, origin: origin, title: "B08-QA"))
    }

    /// Senderkarten (die Karte ist ein zusammengefasstes Accessibility-Element; ihr Tooltip ist der des ⊞).
    func cards(_ w: NSWindow) -> [NSObject] {
        B08UI.elements(w) { B08UI.help($0).contains("Multiview") }
    }

    func card(_ w: NSWindow, _ name: String) -> NSObject? {
        cards(w).first { let l = B08UI.label($0); return l == name || l.hasPrefix(name + ",") || l.hasPrefix(name + " |") }
    }

    /// ⊞ sitzt links neben dem Stern: Kartenrand 14 pt, Stern ≈ 20 pt, Abstand 12 pt, ⊞ ≈ 22 pt → Mitte ≈ maxX − 57.
    /// Die Stelle wird in `testAK01…` am aktiven Button kalibriert (Klick fügt hinzu, kein Player).
    func plusPoint(_ w: NSWindow, _ name: String) -> NSPoint? {
        guard let c = card(w, name) else { return nil }
        let f = B08UI.frame(c)
        return w.convertPoint(fromScreen: NSPoint(x: f.maxX - 57, y: f.midY))
    }

    @discardableResult
    func clickPlus(_ w: NSWindow, _ name: String, session: MultiviewSession) async -> Bool {
        guard let p = plusPoint(w, name) else {
            B08QA.log("UI|karte fehlt|\(name)|karten=\(cards(w).map(B08UI.label))")
            return false
        }
        B08UI.click(w, at: p)
        silenceAll(session)            // Tonschutz sofort nach dem Hinzufügen
        await B08QA.spin(0.6)
        silenceAll(session)
        return true
    }

    /// Helligkeit des ⊞-Symbols (mittlere Abweichung vom Kartenhintergrund) – belegt das Abblenden.
    func plusContrast(_ w: NSWindow, _ name: String) -> Double {
        guard let p = plusPoint(w, name), let img = B08UI.image(w) else { return -1 }
        let scale = Double(img.width) / Double(w.frame.width)
        let cx = Int(p.x * scale), cy = Int((w.frame.height - p.y) * scale)
        let r = Int(11 * scale)
        guard let crop = img.cropping(to: CGRect(x: cx - r, y: cy - r, width: 2 * r, height: 2 * r)),
              let bgCrop = img.cropping(to: CGRect(x: cx - r - Int(40 * scale), y: cy - r, width: 2 * r, height: 2 * r)) else { return -1 }
        return abs(Self.meanLuma(crop) - Self.meanLuma(bgCrop))
    }

    static func meanLuma(_ img: CGImage) -> Double {
        let w = 16, h = 16
        guard let ctx = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w * 4,
                                  space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return -1 }
        ctx.draw(img, in: CGRect(x: 0, y: 0, width: w, height: h))
        guard let d = ctx.data else { return -1 }
        let px = d.bindMemory(to: UInt8.self, capacity: w * h * 4)
        var sum = 0.0
        for i in 0..<(w * h) { sum += 0.299 * Double(px[i * 4]) + 0.587 * Double(px[i * 4 + 1]) + 0.114 * Double(px[i * 4 + 2]) }
        return sum / Double(w * h)
    }

    // MARK: Kacheln im Multiview

    /// X-Knöpfe „Stream entfernen" (Bildschirmkoordinaten via Accessibility).
    func closeButtons(_ w: NSWindow) -> [NSObject] {
        B08UI.elements(w) { B08UI.role($0) == "AXButton" && (B08UI.help($0) == "Stream entfernen" || B08UI.label($0) == "Close") }
    }

    /// Kachelrechteck aus der Lage ihres X (oben rechts, 8 pt Innenabstand) und der Kachelgröße, in Bildschirmkoordinaten.
    func tileRect(fromX f: NSRect, size: CGSize) -> NSRect {
        NSRect(x: f.maxX + 8 - size.width, y: f.maxY + 8 - size.height, width: size.width, height: size.height)
    }

    /// Klick mit Mausbewegung und Zeitabstand (wie ein Mensch) auf einen Punkt in Bildschirmkoordinaten.
    func humanClick(_ w: NSWindow, screen p: NSPoint) async {
        let pw = w.convertPoint(fromScreen: p)
        func ev(_ t: NSEvent.EventType, _ ts: TimeInterval) -> NSEvent? {
            NSEvent.mouseEvent(with: t, location: pw, modifierFlags: [], timestamp: ts, windowNumber: w.windowNumber, context: nil,
                               eventNumber: Int.random(in: 1...10_000), clickCount: t == .mouseMoved ? 0 : 1, pressure: t == .leftMouseUp ? 0 : 1)
        }
        let t0 = ProcessInfo.processInfo.systemUptime
        if let m = ev(.mouseMoved, t0) { w.sendEvent(m) }
        await B08QA.spin(0.1)
        if let d = ev(.leftMouseDown, t0 + 0.1) { w.sendEvent(d) }
        await B08QA.spin(0.08)
        if let u = ev(.leftMouseUp, t0 + 0.18) { w.sendEvent(u) }
        await B08QA.spin(0.6)
    }

    // MARK: Layout-Umschalter in der Titelleiste

    func picker(_ w: NSWindow) -> NSSegmentedControl? {
        func walk(_ v: NSView) -> NSSegmentedControl? {
            if let s = v as? NSSegmentedControl { return s }
            for sub in v.subviews { if let s = walk(sub) { return s } }
            return nil
        }
        for item in w.toolbar?.items ?? [] { if let v = item.view, let s = walk(v) { return s } }
        return nil
    }

    func pickerState(_ w: NSWindow) -> String {
        guard let p = picker(w) else { return "kein Umschalter" }
        return "\((0..<p.segmentCount).map { p.label(forSegment: $0) ?? "" }.joined(separator: "|")) gewählt=\(p.selectedSegment) aktiv=\(p.isEnabled)"
    }

    /// Klick auf ein Segment des Umschalters (echtes Mausereignis in der Titelleiste).
    func clickSegment(_ w: NSWindow, _ index: Int) async {
        guard let p = picker(w) else { return }
        let r = p.convert(p.bounds, to: nil)
        let x = r.minX + r.width * (CGFloat(index) + 0.5) / CGFloat(max(p.segmentCount, 1))
        let pt = NSPoint(x: x, y: r.midY)
        for type in [NSEvent.EventType.leftMouseDown, .leftMouseUp] {
            if let ev = NSEvent.mouseEvent(with: type, location: pt, modifierFlags: [], timestamp: ProcessInfo.processInfo.systemUptime,
                                           windowNumber: w.windowNumber, context: nil, eventNumber: 0, clickCount: 1, pressure: 1) {
                w.sendEvent(ev)
            }
        }
        await B08QA.spin(0.5)
    }

    // MARK: Tasten (nur mit Beep-Wächter)

    func key(_ chars: String, keyCode: UInt16, in w: NSWindow) {
        guard B08BeepGuard.verify() else { return XCTFail("Beep-Wächter nicht aktiv – keine Taste gesendet") }
        for type in [NSEvent.EventType.keyDown, .keyUp] {
            if let ev = NSEvent.keyEvent(with: type, location: .zero, modifierFlags: [], timestamp: ProcessInfo.processInfo.systemUptime,
                                         windowNumber: w.windowNumber, context: nil, characters: chars, charactersIgnoringModifiers: chars,
                                         isARepeat: false, keyCode: keyCode) {
                w.sendEvent(ev)
            }
        }
    }
}
