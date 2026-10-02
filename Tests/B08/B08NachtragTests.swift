import XCTest
import SwiftUI
import SwiftData
import AppKit
@testable import MikaPlusPlayer

/// B08 · Multiview — Nachträge der QA (Durchlauf 1, Fortsetzung 2026-09-26).
///
/// - Klicks bei **aktiver** App: Tipp-Gesten (`onTapGesture`) reagieren im Test-Host nur, wenn die App aktiv ist;
///   der abgebrochene Teil hatte deshalb den Fokuswechsel per Klick nur über `setFocus` nachgestellt.
/// - ⊞ im Senderlisten-Fenster ohne Zugangsdaten und zweimal auf denselben Sender (AK-06, AK-07 über die Oberfläche).
/// - BF-101 (B06 BUG-07): libVLC-Hänger beim Erzeugen neuer Player, während vier VLC-Kacheln abgebaut werden –
///   nur mit `B08_HAENGER=1` (Wachhund schreibt ein Sample und beendet den Prozess, falls der Hauptthread hängt).
///
/// Kein Ton: Medien ohne Tonspur, jede Engine sofort auf Lautstärke 0 (`add`, `clickPlus`), keine Tasten.
@MainActor
final class B08NachtragTests: B08UITestCase {

    // MARK: Hilfen

    /// Holt den Test-Host nach vorn (nur so lösen synthetische Klicks die Tipp-Geste der Kacheln aus).
    /// Seit macOS 14 aktiviert sich ein Hintergrundprozess nicht selbst (kooperative Aktivierung). Deshalb zusätzlich eine
    /// Anforderungsdatei (`TEST_RUNNER_B08_AKTIVIEREN=<Pfad>`): Der Test schreibt seine PID hinein, ein Helfer außerhalb des
    /// Test-Hosts (Prozess mit Bedienungshilfen-Recht, z. B. aus dem Terminal) liest sie und ruft
    /// `AXUIElementSetAttributeValue(AXUIElementCreateApplication(pid), kAXFrontmostAttribute as CFString, kCFBooleanTrue)`.
    /// Ohne Helfer wird der Test übersprungen.
    private func activate(_ w: NSWindow) async -> Bool {
        NSApp.activate(ignoringOtherApps: true)
        w.makeKeyAndOrderFront(nil)
        _ = await B08QA.wait(2) { NSApp.isActive }
        if !NSApp.isActive, let req = ProcessInfo.processInfo.environment["B08_AKTIVIEREN"], !req.isEmpty {
            try? "\(getpid())".write(toFile: req, atomically: true, encoding: .utf8)
            _ = await B08QA.wait(6) { NSApp.isActive }
        }
        w.makeKeyAndOrderFront(nil)
        _ = await B08QA.wait(2) { w.isKeyWindow }
        return NSApp.isActive
    }

    /// Klick über die Ereigniswarteschlange der App (`NSApp.postEvent`) statt `NSWindow.sendEvent`: So erreicht das
    /// Loslassen der Maustaste die Verfolgungsschleife der Tipp-Geste wie bei einem echten Klick.
    /// Parallel laufende Prüfungen anderer Features können die Aktivierung übernehmen; vor jedem Klick wird sie erneuert.
    private func queuedClick(_ w: NSWindow, screen p: NSPoint) async {
        if !NSApp.isActive || !w.isKeyWindow {
            let ok = await activate(w)
            B08QA.log("KLICK|App erneut aktiviert=\(ok)")
        }
        let pw = w.convertPoint(fromScreen: p)
        let t0 = ProcessInfo.processInfo.systemUptime
        func ev(_ t: NSEvent.EventType, _ ts: TimeInterval) -> NSEvent? {
            NSEvent.mouseEvent(with: t, location: pw, modifierFlags: [], timestamp: ts, windowNumber: w.windowNumber, context: nil,
                               eventNumber: Int.random(in: 1...10_000), clickCount: t == .mouseMoved ? 0 : 1, pressure: t == .leftMouseUp ? 0 : 1)
        }
        if let m = ev(.mouseMoved, t0) { NSApp.postEvent(m, atStart: false) }
        await B08QA.spin(0.1)
        if let d = ev(.leftMouseDown, t0 + 0.1) { NSApp.postEvent(d, atStart: false) }
        if let u = ev(.leftMouseUp, t0 + 0.18) { NSApp.postEvent(u, atStart: false) }
        await B08QA.spin(0.7)
    }

    /// X-Knöpfe von oben nach unten (Bildschirmkoordinaten). Im Fokus-Layout: [großes X, X der 1., 2., 3. kleinen Kachel].
    private func xFramesTopDown(_ w: NSWindow) -> [NSRect] {
        closeButtons(w).map(B08UI.frame).sorted { $0.maxY > $1.maxY }
    }

    private func tileCenter(fromX f: NSRect, size: CGSize) -> NSPoint {
        let r = tileRect(fromX: f, size: size)
        return NSPoint(x: r.midX, y: r.midY - 20)      // unterhalb von Etikett und X
    }

    // MARK: AK-14 · AK-15 · AK-16 — Klicks bei aktiver App

    func testAK14_AK15_AK16_KlicksBeiAktiverApp() async throws {
        let (w, app) = try await resetAppSession()
        w.setFrame(NSRect(x: 320, y: 165, width: 1280, height: 720), display: true)
        let aktiv = await activate(w)
        B08QA.log("AK-14|aktive App|isActive=\(aktiv)|key=\(w.isKeyWindow)")
        guard aktiv else { throw XCTSkip("Test-Host ließ sich nicht aktivieren – Tipp-Gesten nicht auslösbar") }

        // Fokus-Layout, gemischt: HLS groß, VLC und HLS klein
        add(app, channel("Eins HLS", "/livehls/k1/index.m3u8"))
        add(app, channel("Zwei TS", "/tslive/k2.ts"))
        add(app, channel("Drei HLS", "/livehls/k3/index.m3u8"))
        _ = await B08QA.wait(12) { app.slots.allSatisfy { $0.engine.state == .playing } }
        await B08QA.spin(2)
        var xs = xFramesTopDown(w)
        XCTAssertEqual(xs.count, 3)
        // Klick auf die zweite kleine Kachel („Drei HLS", Index 2)
        await queuedClick(w, screen: tileCenter(fromX: xs[2], size: CGSize(width: 240, height: 135)))
        let nachKlick = B08Engine.describe(app)
        B08UI.shot(w, "AK-14-fokus-klick-kleine-kachel")
        let etiketten = B08UI.labels(w).map(SystemSprache.englischerName).filter { $0.contains("HLS") || $0.contains("TS") || $0 == "Volume High" || $0 == "Mute" } // B09 · OF-01: englisch oder deutsch
        B08QA.log("AK-14|Fokus|Mausklick auf 2. kleine Kachel|\(nachKlick)|etiketten oben→unten=\(etiketten)")
        XCTAssertEqual(app.focusedIndex, 2, "Klick auf die kleine Kachel fokussiert sie")
        XCTAssertEqual(app.slots.map(\.engine.isMuted), [true, true, false], "nur sie hat Ton")
        XCTAssertEqual(app.slots.map { B08Engine.innerMuted($0.engine) }, [true, true, false], "am eigentlichen Player")
        // Klick auf das (große) fokussierte Bild bewirkt nichts
        let big = w.contentRect(forFrameRect: w.frame)
        await queuedClick(w, screen: NSPoint(x: big.minX + 200, y: big.minY + 150))
        B08QA.log("AK-14|Klick auf das große Bild|fokus=\(app.focusedIndex)")
        XCTAssertEqual(app.focusedIndex, 2, "Klick auf den fokussierten Stream bewirkt nichts")

        // AK-16 / BUG-04 (Build 2026-09-28): ein Klick auf das große X entfernt den großen Stream („Drei HLS", Index 2);
        // als letzter in der Reihe bekommt der davor den Ton (AK-17).
        xs = xFramesTopDown(w)
        let bigX = xs[0]
        await queuedClick(w, screen: NSPoint(x: bigX.midX, y: bigX.midY))
        B08UI.shot(w, "BUILD-AK-16-klick-aufs-grosse-x-aktive-app")
        B08QA.log("AK-16|aktive App|Klick auf das große X bei \(bigX)|fokus=\(app.focusedIndex)|slots=\(app.slots.map(\.channel.name))")
        XCTAssertEqual(app.slots.map(\.channel.name), ["Eins HLS", "Zwei TS"], "der große Stream ist entfernt")
        XCTAssertEqual(app.focusedIndex, 1)
        XCTAssertEqual(app.slots.map(\.engine.isMuted), [true, false])

        // Raster: Klick auf die Kachel unten links (Index 2)
        await safeClear(app)
        await B08QA.spin(0.5)
        for (i, p) in ["/tslive/r1.ts", "/livehls/r2/index.m3u8", "/tslive/r3.ts", "/livehls/r4/index.m3u8"].enumerated() {
            add(app, channel("R\(i + 1)", p))
        }
        _ = await B08QA.wait(12) { app.slots.allSatisfy { $0.engine.state == .playing } }
        await clickSegment(w, 1)
        XCTAssertEqual(app.layout, .grid)
        await B08QA.spin(1.5)
        let c = w.contentRect(forFrameRect: w.frame)
        // Raster 2 × 2 unter der Titelleiste: unten links = linke Hälfte, untere Hälfte
        await queuedClick(w, screen: NSPoint(x: c.minX + c.width * 0.25, y: c.minY + c.height * 0.2))
        B08UI.shot(w, "AK-14-raster-klick-unten-links-aktive-app")
        B08QA.log("AK-14|Raster|Mausklick unten links|\(B08Engine.describe(app))")
        XCTAssertEqual(app.focusedIndex, 2, "Raster: Klick fokussiert die Kachel unten links")
        XCTAssertEqual(app.slots.map(\.engine.isMuted), [true, true, false, true])
        app.layout = .focus
        await B08QA.spin(0.8)

        // AK-15 mit echtem Klick: VLC groß, VLC klein → Klick auf die kleine
        await safeClear(app)
        await B08QA.spin(0.5)
        add(app, channel("VLC A", "/tslive/k15a.ts")); add(app, channel("VLC B", "/tslive/k15b.ts"))
        _ = await B08QA.wait(12) { app.slots.allSatisfy { $0.engine.state == .playing } }
        await B08QA.spin(3)
        let region = CGRect(x: 0.04, y: 0.35, width: 0.5, height: 0.6)
        let vorher = B08UI.image(w).map { B08UI.blackRatio($0, rect: region) } ?? -1
        xs = xFramesTopDown(w)
        await queuedClick(w, screen: tileCenter(fromX: xs[1], size: CGSize(width: 240, height: 135)))
        let geklickt = app.focusedIndex == 1
        await B08QA.spin(2)
        let nach2 = B08UI.shot(w, "AK-15-vlc-echter-klick-2s").map { B08UI.blackRatio($0, rect: region) } ?? -1
        await B08QA.spin(8)
        let nach10 = B08UI.shot(w, "AK-15-vlc-echter-klick-10s").map { B08UI.blackRatio($0, rect: region) } ?? -1
        B08QA.log("AK-15|VLC|echter Klick wirkt=\(geklickt)|Schwarzanteil Hauptbild vorher/2 s/10 s=\(B08QA.f2(vorher))/\(B08QA.f2(nach2))/\(B08QA.f2(nach10))|\(B08Engine.describe(app))")
        XCTAssertTrue(geklickt)
        XCTAssertLessThan(vorher, 0.2)
        // Seit B08 · BUG-02 (Build 2026-09-28): das große Bild zeigt den angeklickten VLC-Stream
        XCTAssertLessThan(max(nach2, nach10), 0.2, "VLC-Hauptbild nach dem Klick sichtbar")
        NSApp.deactivate()
    }

    // MARK: Code-Review-Fund — Raster: nach dem Entfernen einer vorderen VLC-Kachel bleiben Zellen schwarz (Identität je Index)

    func testCR_AK11_AK19_RasterVorneEntfernenVLCBilder() async throws {
        let (w, app) = try await resetAppSession()
        w.setFrame(NSRect(x: 320, y: 165, width: 1280, height: 720), display: true)
        for i in 1...4 { add(app, channel("V\(i)", "/tslive/cr-\(i).ts")) }
        _ = await B08QA.wait(12) { app.slots.allSatisfy { $0.engine.state == .playing } }
        app.layout = .grid
        await B08QA.spin(3)
        // Zellen des 2 × 2-Rasters im Fensterbild (y von oben, Titelleiste ≈ 7 %), ohne Etikett und X
        let zellen = [CGRect(x: 0.03, y: 0.20, width: 0.44, height: 0.30), CGRect(x: 0.53, y: 0.20, width: 0.44, height: 0.30),
                      CGRect(x: 0.03, y: 0.64, width: 0.44, height: 0.30), CGRect(x: 0.53, y: 0.64, width: 0.44, height: 0.30)]
        func schwarz(_ name: String) -> [String] {
            guard let img = B08UI.shot(w, name) else { return [] }
            return zellen.map { B08QA.f2(B08UI.blackRatio(img, rect: $0)) }
        }
        let vorher = schwarz("CR-raster-vier-vlc-vorher")
        // X der ersten Kachel (oben links) per Mausklick: 4 → 3, kein Absturz (AK-23 Gegenprobe)
        // oben links = größtes maxY (Bildschirmkoordinaten), bei Gleichstand kleinstes minX
        let xs: [NSRect] = closeButtons(w).map(B08UI.frame)
        let obenLinks: [NSRect] = xs.sorted { a, b in a.maxY != b.maxY ? a.maxY > b.maxY : a.minX < b.minX }
        let x0: NSRect = obenLinks[0]
        await humanClick(w, screen: NSPoint(x: x0.midX, y: x0.midY))
        await B08QA.spin(3)
        let nach = schwarz("CR-raster-nach-x-vorne-vlc")
        let etiketten = B08UI.labels(w).filter { $0.hasPrefix("V") && $0.count == 2 }
        B08QA.log("CR|Raster VLC|Schwarzanteil Zellen oben links, oben rechts, unten links, unten rechts vorher=\(vorher) nach X auf V1=\(nach)|slots=\(app.slots.map(\.channel.name))|etiketten=\(etiketten)|\(B08Engine.describe(app))")
        XCTAssertEqual(app.slots.map(\.channel.name), ["V2", "V3", "V4"])
        XCTAssertTrue(vorher.allSatisfy { (Double($0) ?? 1) < 0.2 }, "vorher vier Bilder")
        // Seit B08 · BUG-02 (Build 2026-09-28): die Kacheln sind an ihren Slot gebunden – die nachrückenden zeigen ihr Bild
        XCTAssertTrue(nach.prefix(3).allSatisfy { (Double($0) ?? 1) < 0.2 }, "drei Bilder")
        app.layout = .focus
        await B08QA.spin(0.8)
    }

    // MARK: AK-06 · AK-07 ⚠ — ⊞ über die Oberfläche: ohne Zugangsdaten und derselbe Sender zweimal

    func testAK06_AK07_PlusOhneZugangsdatenUndDoppelterSender() async throws {
        let (mv, app) = try await resetAppSession()
        mv.performClose(nil)
        await B08QA.spin(0.8)
        XCTAssertTrue(B08App.multiviewWindows().isEmpty, "Multiview vor dem Klick geschlossen")
        let ctx = container.mainContext
        let x = try await importXtream(ctx, output: .mpegts, name: "QA Ohne Zugang")
        try XtreamCredentialStore.standard.delete(for: x.id)
        let lw = listWindow(x, session: app)
        await B08QA.spin(1.5)
        let first = x.channels.sorted { $0.name < $1.name }.first!.name
        let anfragenVorher = server.requests(containing: "/live/").count
        let fensterVorher = Set(NSApp.windows.filter(\.isVisible).map(ObjectIdentifier.init))
        let ok = await clickPlus(lw, first, session: app)
        _ = await B08QA.wait(4) { !B08App.multiviewWindows().isEmpty }
        await B08QA.spin(1)
        let mvw = B08App.multiviewWindows().first
        let neue = NSApp.windows.filter { $0.isVisible && !fensterVorher.contains(ObjectIdentifier($0)) }
        let sheets = NSApp.windows.compactMap(\.attachedSheet)
        let labels = mvw.map(B08UI.labels) ?? []
        if let mvw { B08UI.shot(mvw, "AK-07-plus-ohne-zugangsdaten-leeres-fenster") }
        B08QA.log("AK-07|⊞ ohne Zugangsdaten|klick=\(ok)|slots=\(app.slots.count)|multiview offen=\(mvw != nil)|neue Fenster=\(neue.map(\.title))|sheets=\(sheets.count)|labels=\(labels)|liveAnfragen +\(server.requests(containing: "/live/").count - anfragenVorher)|listentitel=\(lw.title)")
        XCTAssertTrue(ok)
        XCTAssertEqual(app.slots.count, 0, "kein Stream hinzugefügt")
        XCTAssertNotNil(mvw, "Ist: das Fenster öffnet sich trotzdem")
        XCTAssertTrue(labels.contains("Kein Stream im Multiview"), "Ist: Leerzustand")
        XCTAssertEqual(sheets.count, 0, "keine Meldung")
        XCTAssertNil(NSApp.modalWindow, "kein Hinweisfenster")
        XCTExpectFailure("BUG-09 · ⊞ ohne Zugangsdaten öffnet ein leeres Multiview ohne Meldung (wartet auf OF-02)") {
            XCTAssertTrue(labels.contains { $0.localizedCaseInsensitiveContains("Zugangsdaten") }, "erwartet: Hinweis auf fehlende Zugangsdaten")
        }

        // Derselbe M3U-Sender zweimal über ⊞
        let m = try playlist("QA Doppelt", [("Doppel TS", "/tslive/ak06ui.ts")])
        let lw2 = listWindow(m, session: app, origin: CGPoint(x: 600, y: 60))
        await B08QA.spin(1.5)
        await clickPlus(lw2, "Doppel TS", session: app)
        await clickPlus(lw2, "Doppel TS", session: app)
        await B08QA.spin(2)
        let mv2 = try XCTUnwrap(B08App.multiviewWindows().first)
        B08UI.shot(mv2, "AK-06-derselbe-sender-zweimal")
        let tooltip = card(lw2, "Doppel TS").map(B08UI.help) ?? "-"
        B08QA.log("AK-06|⊞ zweimal auf denselben Sender|slots=\(app.slots.map(\.channel.name))|ids verschieden=\(Set(app.slots.map(\.id)).count == app.slots.count)|verbindungen=\(server.openStreamConnections(containing: "ak06ui").count)|tooltip danach=\(tooltip)|labels=\(B08UI.labels(mv2).filter { $0.contains("Doppel") })")
        XCTAssertEqual(app.slots.map(\.channel.name), ["Doppel TS", "Doppel TS"])
        XCTAssertEqual(server.openStreamConnections(containing: "ak06ui").count, 2)
        XCTExpectFailure("BUG-08 · derselbe Sender kommt ohne Hinweis zweimal ins Multiview (wartet auf OF-01)") {
            XCTAssertEqual(app.slots.count, 1)
        }
    }

    // MARK: BF-101 / BF-97 — vier VLC-Kacheln abbauen und sofort neue erzeugen (nur mit B08_HAENGER=1)

    private static let fortschritt = Fortschritt()

    final class Fortschritt: @unchecked Sendable {
        private let lock = NSLock()
        private var wert = 0
        private var marke = ""
        func tick(_ m: String) { lock.lock(); wert += 1; marke = m; lock.unlock() }
        var stand: (Int, String) { lock.lock(); defer { lock.unlock() }; return (wert, marke) }
    }

    /// Wachhund: bei 60 s ohne Fortschritt Sample in den QA-Ordner schreiben und den Test-Host beenden (Exit 70).
    private func wachhund(sekunden: Double = 60) {
        let ziel = B08QA.qaFolder.appendingPathComponent("BF-101-haenger-sample.txt").path
        let fortschritt = Self.fortschritt
        Thread.detachNewThread {
            var letzter = fortschritt.stand.0
            var still = 0.0
            while true {
                Thread.sleep(forTimeInterval: 5)
                let (wert, marke) = fortschritt.stand
                if wert != letzter { letzter = wert; still = 0; continue }
                still += 5
                if still >= sekunden {
                    print("B08QA|WACHHUND|kein Fortschritt seit \(Int(still)) s bei '\(marke)' – Sample nach \(ziel)")
                    fflush(stdout)
                    let p = Process()
                    p.executableURL = URL(fileURLWithPath: "/usr/bin/sample")
                    p.arguments = ["\(getpid())", "3", "-file", ziel]
                    try? p.run()
                    p.waitUntilExit()
                    print("B08QA|WACHHUND|Sample geschrieben, Test-Host wird beendet (Exit 70)")
                    fflush(stdout)
                    exit(70)
                }
            }
        }
    }

    func testBF101_VierVLCKachelnAbbauenUndSofortNeu() async throws {
        guard ProcessInfo.processInfo.environment["B08_HAENGER"] == "1" else {
            throw XCTSkip("nur mit B08_HAENGER=1 – im Fehlerfall hängt der Test-Host (Wachhund beendet ihn nach 60 s)")
        }
        wachhund()
        let runden = Int(ProcessInfo.processInfo.environment["B08_HAENGER_RUNDEN"] ?? "16") ?? 16
        let spielzeit = Double(ProcessInfo.processInfo.environment["B08_HAENGER_SPIELZEIT"] ?? "1.5") ?? 1.5
        var (w, app) = try await resetAppSession()
        w.setFrame(NSRect(x: 320, y: 165, width: 1280, height: 720), display: true)
        B08QA.log("BF-101|Start: \(runden) Runden mit je 4 VLC-Kacheln, Spielzeit \(spielzeit) s im echten Multiview-Fenster (ungerade: Fenster schließen und sofort ⊞, gerade: alle X in Folge und sofort ⊞)")
        var maxVLC = 0
        for runde in 1...runden {
            Self.fortschritt.tick("Runde \(runde) erzeugen")
            if B08App.multiviewWindows().isEmpty {
                (w, app) = try await openRealMultiview()          // wie der nächste ⊞-Klick (öffnet das Fenster)
            }
            for i in 0..<4 { add(app, channel("H\(runde)-\(i)", "/tslive/bf101-\(runde)-\(i).ts")) }
            Self.fortschritt.tick("Runde \(runde) geladen")
            let t = await B08QA.wait(10) { app.slots.allSatisfy { $0.engine.state == .playing } }
            await B08QA.spin(spielzeit)
            let spielend = app.slots.filter { $0.engine.state == .playing }.count
            maxVLC = max(maxVLC, B08Registry.liveVLCPlayers.count)
            let t0 = Date()
            if runde % 2 == 1 {
                app.layout = .focus
                w.performClose(nil)                                 // onDisappear → clear() → vier Player zugleich frei
            } else {
                for id in app.slots.map(\.id) { app.remove(id) }    // alle X in Folge
            }
            if runde % 2 == 1 { _ = await B08QA.wait(3, step: 0.01) { app.slots.isEmpty } }   // onDisappear hat geleert
            Self.fortschritt.tick("Runde \(runde) abgebaut")
            // sofort neue Player erzeugen, während die alten abgebaut werden (Ereignis aus B06 BUG-07);
            // Reihenfolge wie der ⊞-Button: erst add, dann das Fenster öffnen
            for i in 0..<4 { add(app, channel("N\(runde)-\(i)", "/tslive/bf101n-\(runde)-\(i).ts")) }
            let erzeugt = Date().timeIntervalSince(t0)
            if B08App.multiviewWindows().isEmpty { (w, app) = try await openRealMultiview() }
            Self.fortschritt.tick("Runde \(runde) neu erzeugt")
            await B08QA.spin(1.0)
            let lebendVLC = B08Registry.liveVLCPlayers.count
            await safeClear(app)
            let frei = await B08QA.wait(8) { B08Registry.liveVLCPlayers.isEmpty && self.server.openStreamConnections(containing: "bf101").isEmpty }
            Self.fortschritt.tick("Runde \(runde) aufgeräumt")
            B08QA.log("BF-101|Runde \(runde) ok|\(runde % 2 == 1 ? "Schließen" : "X×4")|spielend=\(spielend)/4 nach \(t.map(B08QA.f1) ?? ">10")s|Abbau→4 neue Player in \(B08QA.f2(erzeugt)) s|lebende VLC-Player danach=\(lebendVLC)|alle frei + Verbindungen zu nach=\(frei.map(B08QA.f1) ?? ">8") s")
            XCTAssertNotNil(frei, "BF-97 im Multiview: alle VLC-Player frei, alle Verbindungen zu")
        }
        B08QA.log("BF-101|alle \(runden) Runden ohne Hänger (höchstens \(maxVLC) VLC-Player gleichzeitig am Leben)")
    }
}
