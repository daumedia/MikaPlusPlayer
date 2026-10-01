import XCTest
import SwiftUI
import SwiftData
import AppKit
import AVFoundation
@testable import MikaPlusPlayer

/// B08 · Oberfläche mit dem echten Fenster „Multiview" und der Session der App. Kein Ton: Medien ohne Tonspur,
/// jede Engine sofort auf Lautstärke 0; Tasten nur mit Beep-Wächter.
@MainActor
final class B08OberflaecheTests: B08UITestCase {

    // MARK: AK-01 · AK-02 · AK-09 — ⊞ öffnet das Fenster und fügt hinzu; Menü „Window › Multiview"

    func testAK01_AK02_AK09_PlusFuegtHinzuUndOeffnetFensterMenueintrag() async throws {
        // AK-02 (erstes Öffnen) prüft `openRealMultiview` beim ersten Öffnen im Lauf.
        let (w0, app) = try await resetAppSession()
        XCTAssertEqual(w0.title, "Multiview")
        w0.performClose(nil)
        await B08QA.spin(0.8)
        XCTAssertTrue(B08App.multiviewWindows().isEmpty, "Ausgangslage: Fenster zu")
        let p = try playlist("QA Liste", [("Alpha HLS", "/livehls/ak01a/index.m3u8"), ("Beta TS", "/tslive/ak01b.ts"), ("Gamma", "/hang/ak01c.ts")])
        let list = listWindow(p, session: app)
        await B08QA.spin(1.2)
        let helpBefore = cards(list).map(B08UI.help)
        B08QA.log("AK-01|karten=\(cards(list).map(B08UI.label))|tooltips=\(helpBefore)")
        XCTAssertEqual(helpBefore, Array(repeating: "Zu Multiview hinzufügen", count: 3))
        B08UI.shot(list, "AK-01-senderliste-plus")
        let titleBefore = list.title
        await clickPlus(list, "Alpha HLS", session: app)
        _ = await B08QA.wait(4) { !B08App.multiviewWindows().isEmpty }
        let mv = try XCTUnwrap(realWindow(), "⊞ öffnet das Fenster „Multiview“")
        B08QA.log("AK-01|nach ⊞|slots=\(app.slots.map(\.channel.name))|fenster=\(mv.title) \(Int(mv.frame.width))x\(Int(mv.frame.height))|listentitel vorher/nachher=\(titleBefore)/\(list.title)")
        XCTAssertEqual(app.slots.map(\.channel.name), ["Alpha HLS"], "Sender ist im Multiview (Klickpunkt ⊞ kalibriert)")
        XCTAssertEqual(list.title, titleBefore, "Liste bleibt stehen, kein Player")
        XCTAssertEqual(mv.title, "Multiview")
        XCTAssertTrue(app.slots[0].engine.state == .loading || app.slots[0].engine.state == .playing, "Stream beginnt zu laden")
        // Fenster ist schon offen: zweiter ⊞ holt es nach vorn, kein zweites Fenster
        mv.orderBack(nil)
        await clickPlus(list, "Beta TS", session: app)
        await B08QA.spin(0.8)
        XCTAssertEqual(B08App.multiviewWindows().count, 1)
        let front = NSApp.orderedWindows.first { $0.isVisible }
        B08QA.log("AK-01|zweiter ⊞|slots=\(app.slots.count)|vorderstes Fenster=\(front?.title ?? "-")")
        XCTAssertEqual(app.slots.count, 2)
        // Favoriten-Tab
        let fav = try playlist("QA Favoriten", [("Favorit TS", "/tslive/ak01fav.ts")], favorites: true)
        _ = fav
        let favW = favoritesWindow(session: app)
        await B08QA.spin(1.2)
        B08QA.log("AK-01|favoriten|karten=\(cards(favW).map(B08UI.label))|tooltips=\(cards(favW).map(B08UI.help))")
        await clickPlus(favW, "Favorit TS", session: app)
        XCTAssertEqual(app.slots.map(\.channel.name), ["Alpha HLS", "Beta TS", "Favorit TS"], "⊞ im Favoriten-Tab")
        XCTAssertEqual(favW.title, "Favoriten", "Favoriten-Tab bleibt stehen")
        await B08QA.spin(1.5)
        B08UI.shot(mv, "AK-01-multiview-drei")
        B08UI.shot(favW, "AK-01-favoriten-plus")

        // AK-09: Menü „Window“
        let item = try XCTUnwrap(B08App.windowMenuItem())
        B08QA.log("AK-09|menue=\(B08App.windowMenuTitles())|kürzel='\(item.keyEquivalent)' modifier=\(item.keyEquivalentModifierMask.rawValue)")
        XCTAssertEqual(item.keyEquivalent, "", "ohne Tastenkürzel")
        // Schließen (Fokus) und über das Menü ohne Streams öffnen → Leerzustand; zweites Öffnen → weiter ein Fenster
        mv.performClose(nil)
        await B08QA.spin(1)
        XCTAssertTrue(app.isEmpty)
        XCTAssertTrue(B08App.openViaMenu())
        _ = await B08QA.wait(4) { !B08App.multiviewWindows().isEmpty }
        XCTAssertTrue(B08App.openViaMenu())
        await B08QA.spin(1)
        let mvs = B08App.multiviewWindows()
        let labels = mvs.first.map(B08UI.labels) ?? []
        B08QA.log("AK-09|nach 2× Menü|fenster=\(mvs.count)|labels=\(labels)")
        XCTAssertEqual(mvs.count, 1, "nie ein zweites Multiview-Fenster")
        XCTAssertTrue(labels.contains("Kein Stream im Multiview"))
    }

    // MARK: AK-04 · AK-05 · AK-21 · EC-06 — voll in allen Fenstern; Klick auf den grauen ⊞ bewirkt nichts (BUG-03 behoben)

    func testAK04_AK05_AK21_EC06_VollInAllenFensternKlickAufGrauBewirktNichts() async throws {
        let (_, app) = try await resetAppSession()
        let chans = (1...4).map { ("Kanal \($0)", "/tslive/ak05-\($0).ts") } + [("Kanal 5 HLS", "/livehls/ak05-5/index.m3u8")]
        let p = try playlist("QA Voll", chans, favorites: true)
        _ = p
        let a = listWindow(p, session: app, origin: CGPoint(x: 40, y: 60))
        let b = favoritesWindow(session: app, origin: CGPoint(x: 600, y: 60))
        await B08QA.spin(1.5)
        let contrastEnabled = plusContrast(a, "Kanal 5 HLS")
        for i in 1...4 {
            await clickPlus(a, "Kanal \(i)", session: app)
            B08QA.log("EC-06|nach \(i)|fenster B tooltip=\(cards(b).first.map(B08UI.help) ?? "-")")
        }
        await B08QA.spin(1.5)
        silenceAll(app)
        XCTAssertEqual(app.slots.count, 4)
        let helpA = Set(cards(a).map(B08UI.help)), helpB = Set(cards(b).map(B08UI.help))
        let contrastDisabled = plusContrast(a, "Kanal 5 HLS")
        B08QA.log("AK-04|tooltips A=\(helpA) B=\(helpB)|⊞-Kontrast aktiv/abgeblendet=\(B08QA.f2(contrastEnabled))/\(B08QA.f2(contrastDisabled)) (Verhältnis \(B08QA.f2(contrastDisabled / max(contrastEnabled, 0.01))))")
        XCTAssertEqual(helpA, ["Multiview voll (max. 4)"])
        XCTAssertEqual(helpB, ["Multiview voll (max. 4)"], "AK-21/EC-06: auch im anderen Fenster, ohne Neuladen")
        XCTAssertLessThan(contrastDisabled, contrastEnabled * 0.6, "⊞ sichtbar abgeblendet")
        B08UI.shot(a, "AK-04-liste-voll")
        B08UI.shot(b, "AK-04-favoriten-voll")
        if let mv = realWindow() { B08UI.shot(mv, "AK-04-multiview-vier") }
        let focusedEngine = app.slots[app.focusedIndex].engine
        let before5 = server.requests(containing: "ak05-5").count
        let tsOpen = server.openStreamConnections(containing: "ak05-").count
        let avBefore = B08Registry.liveAVPlayers.count
        let titleBefore = a.title

        // AK-05: Klick auf den abgeblendeten ⊞ von Kanal 5
        await clickPlus(a, "Kanal 5 HLS", session: app)
        await B08QA.spin(3)
        let newPlayers = B08Registry.liveAVPlayers.dropFirst(avBefore)
        let playerMuted = newPlayers.map(\.isMuted)
        let req5 = server.requests(containing: "ak05-5").count - before5
        B08QA.log("AK-05|klick auf grauen ⊞|fenstertitel \(titleBefore) → \(a.title)|slots=\(app.slots.count)|neue AVPlayer=\(newPlayers.count) isMuted=\(playerMuted) volume=\(newPlayers.map(\.volume))|anfragen Kanal 5=\(req5)|TS-Verbindungen=\(tsOpen)|multiview fokussiert muted=\(focusedEngine.isMuted)")
        B08UI.shot(a, "BUILD-AK-05-klick-auf-grauen-plus-bewirkt-nichts")
        XCTAssertEqual(app.slots.count, 4, "kein fünfter im Multiview")
        XCTAssertFalse(focusedEngine.isMuted, "im Multiview hat der fokussierte Stream weiter Ton")
        // Seit B08 · BUG-03 (Build 2026-09-28): voll heißt, der Klick bewirkt nichts – kein Player, keine fünfte Verbindung.
        XCTAssertEqual(a.title, titleBefore, "kein Player – die Liste bleibt stehen")
        XCTAssertEqual(req5, 0, "keine fünfte Verbindung zum Anbieter")
        XCTAssertEqual(playerMuted, [], "kein weiterer Player (mit Ton)")
        B08UI.close(a)
        await B08QA.spin(0.5)
    }

    // MARK: AK-08 · AK-19 (UI) — Leerzustand, Fenster bleibt nach dem letzten X offen

    func testAK08_AK19_LeerzustandUndLetztesXLaesstFensterOffen() async throws {
        let (w, app) = try await resetAppSession()
        let labels0 = B08UI.labels(w)
        B08UI.shot(w, "AK-08-leerzustand")
        B08QA.log("AK-08|leer|labels=\(labels0)")
        XCTAssertTrue(labels0.contains("Kein Stream im Multiview"))
        XCTAssertTrue(labels0.contains("Füge in der Senderliste mit dem ⊞-Button Sender hinzu, um sie hier gleichzeitig zu sehen."))
        let img = try XCTUnwrap(B08UI.image(w))
        let black = B08UI.blackRatio(img, rect: CGRect(x: 0.02, y: 0.15, width: 0.3, height: 0.8))
        XCTAssertGreaterThan(black, 0.95, "schwarzer Grund")
        add(app, channel("Einzeln", "/tslive/ak08.ts"))
        let weak = B08Weak(app.slots[0].engine, "Einzeln")
        await B08QA.spin(2)
        // Keine Accessibility-Elemente über das Entfernen hinaus halten: Ihre Knoten halten die Aktion des Buttons
        // (und damit den Slot samt Engine) fest – ein Artefakt der Messung, kein Verhalten der App.
        var xPoint = NSPoint.zero
        do {
            let xs = closeButtons(w)
            XCTAssertEqual(xs.count, 1)
            B08QA.log("AK-19|X|help=\(xs.first.map(B08UI.help) ?? "-")|label=\(xs.first.map(B08UI.label) ?? "-")")
            XCTAssertEqual(xs.first.map(B08UI.help), "Stream entfernen")
            if let x = xs.first { xPoint = NSPoint(x: B08UI.frame(x).midX, y: B08UI.frame(x).midY) }
        }
        let removedAt = Date()
        await humanClick(w, screen: xPoint)
        let freedAfter = await B08QA.wait(10) { !weak.alive }
        let freedT = Date().timeIntervalSince(removedAt)
        let closed = await B08QA.wait(10) { self.server.openStreamConnections(containing: "ak08").isEmpty }
        let closedT = Date().timeIntervalSince(removedAt)
        B08QA.log("AK-08|nach X|slots=\(app.slots.count)|engine frei=\(freedAfter != nil) nach \(B08QA.f1(freedT)) s ab Klickbeginn|verbindung zu=\(closed != nil) nach \(B08QA.f1(closedT)) s|fenster sichtbar=\(w.isVisible)|labels=\(B08UI.labels(w).prefix(2))")
        XCTAssertTrue(app.isEmpty, "X entfernt die Kachel (Mausklick)")
        XCTAssertNotNil(freedAfter, "Engine freigegeben")
        XCTAssertNotNil(closed, "Verbindung zu")
        XCTAssertLessThanOrEqual(closedT, 3.0, "Verbindungsende binnen ~2 s nach dem Klick")
        XCTAssertTrue(w.isVisible, "Fenster schließt sich nicht von selbst")
        XCTAssertTrue(B08UI.labels(w).contains("Kein Stream im Multiview"))
    }

    // MARK: AK-10 — Fokus-Layout: Geometrie, Rahmen, Etiketten

    func testAK10_FokusLayoutGeometrieUndEtiketten() async throws {
        let (w, app) = try await resetAppSession()
        w.setFrame(NSRect(x: 320, y: 165, width: 1280, height: 720), display: true)
        for (n, path) in [("Eins HLS", "/livehls/ak10a/index.m3u8"), ("Zwei TS", "/tslive/ak10b.ts"), ("Drei HLS", "/livehls/ak10c/index.m3u8"), ("Vier TS", "/tslive/ak10d.ts")] {
            add(app, channel(n, path))
        }
        _ = await B08QA.wait(10) { app.slots.allSatisfy { $0.engine.state == .playing } }
        await B08QA.spin(1.5)
        B08UI.shot(w, "AK-10-fokus-vier")
        // EC-12: HLS-Kacheln legen je einen Bild-in-Bild-Controller an, der nie benutzt wird
        let pip = app.slots.map { B08Engine.isVLC($0.engine) ? "VLC:-" : "AVKit:\(B08Engine.child($0.engine, "pipController").map { "\($0)" }.map { $0 == "nil" ? "nil" : "angelegt" } ?? "?")" }
        // EC-13: Last bei vier gleichzeitig dekodierten Streams (Ist-Wert, Test-Host, Debug)
        var cpu: [String] = []
        for _ in 0..<3 {
            cpu.append(((try? B08QA.run("/bin/ps", ["-o", "%cpu=,rss=", "-p", "\(getpid())"])) ?? "-").trimmingCharacters(in: .whitespacesAndNewlines))
            await B08QA.spin(1)
        }
        B08QA.log("EC-12|Bild-in-Bild-Controller je Kachel=\(pip)|EC-13|CPU% und RSS(KB) des Test-Hosts mit 4 Streams (3 Proben)=\(cpu)|\(B08Engine.describe(app))")
        let content = w.convertToScreen(w.contentLayoutRect)
        let xs = closeButtons(w).map(B08UI.frame).sorted { $0.midX > $1.midX }
        XCTAssertEqual(xs.count, 4)
        let big = xs[0]
        let small = xs.dropFirst().sorted { $0.midY > $1.midY }
        let tiles = small.map { tileRect(fromX: $0, size: CGSize(width: 240, height: 135)) }
        B08QA.log("AK-10|inhalt=\(content)|großes X=\(big)|kleine Kacheln=\(tiles)")
        XCTAssertEqual(big.maxX, content.maxX - 8, accuracy: 1.5, "großes X oben rechts im Hauptbild (8 pt)")
        for t in tiles {
            XCTAssertEqual(t.maxX, content.maxX - 16, accuracy: 1.5, "16 pt vom rechten Rand")
        }
        // Seit B08 · BUG-04 (Build 2026-09-28): die kleinen Kacheln beginnen unterhalb der Leiste des großen Streams
        // (8 pt Innenabstand + 30 pt X + 8 pt), damit dessen X frei liegt – vorher 16 pt vom oberen Rand.
        XCTAssertEqual(tiles[0].maxY, content.maxY - MultiviewMetrics.smallTileTopInset, accuracy: 1.5, "unterhalb der Leiste des großen Streams")
        XCTAssertEqual(MultiviewMetrics.smallTileTopInset, 46)
        XCTAssertLessThan(tiles[0].maxY, big.minY, "erste kleine Kachel unterhalb des großen X")
        XCTAssertEqual(tiles[0].minY - tiles[1].maxY, 8, accuracy: 1.5, "8 pt Abstand")
        XCTAssertEqual(tiles[1].minY - tiles[2].maxY, 8, accuracy: 1.5)
        // Etiketten: Reihenfolge des Hinzufügens, Lautsprecher-Symbol
        let texts = B08UI.elements(w) { B08UI.role($0) == "AXStaticText" }.sorted { B08UI.frame($0).midY > B08UI.frame($1).midY }
        let names = texts.map(B08UI.label).filter { $0.contains("HLS") || $0.contains("TS") }
        let icons = B08UI.elements(w) { B08UI.role($0) == "AXImage" }.map(B08UI.label)
        B08QA.log("AK-10|etiketten oben→unten=\(names)|symbole=\(icons)")
        XCTAssertEqual(Array(names.prefix(4)), ["Eins HLS", "Zwei TS", "Drei HLS", "Vier TS"], "großes Etikett, dann die kleinen in Reihenfolge des Hinzufügens")
        XCTAssertEqual(icons.filter { $0 == "Volume High" }.count, 1, "genau ein Lautsprecher-Symbol (fokussiert)")
        XCTAssertEqual(icons.filter { $0 == "Mute" }.count, 3)
        // Akzentrahmen: Pixel am Rand des Hauptbilds in Akzentfarbe (Rot)
        if let img = B08UI.image(w) {
            let red = redRatio(img, x: 0.001, y: 0.5)
            B08QA.log("AK-10|akzentrahmen links (Rotanteil am Rand)=\(B08QA.f2(red))")
            XCTAssertGreaterThan(red, 0.5, "2-pt-Rahmen in Akzentfarbe")
        }
    }

    /// Anteil rötlicher Pixel in einer 1-px-Spalte bei x (Anteil der Breite) über die Höhe y ± 0,3.
    private func redRatio(_ img: CGImage, x: Double, y: Double) -> Double {
        let col = Int(x * Double(img.width)) + 1
        guard let crop = img.cropping(to: CGRect(x: col, y: Int(Double(img.height) * (y - 0.3)), width: 2, height: Int(Double(img.height) * 0.6))) else { return -1 }
        let w = 2, h = crop.height
        guard let ctx = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w * 4,
                                  space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return -1 }
        ctx.draw(crop, in: CGRect(x: 0, y: 0, width: w, height: h))
        guard let d = ctx.data else { return -1 }
        let px = d.bindMemory(to: UInt8.self, capacity: w * h * 4)
        var red = 0
        for i in 0..<(w * h) where px[i * 4] > 180 && px[i * 4 + 1] < 140 && px[i * 4 + 2] < 140 { red += 1 }
        return Double(red) / Double(w * h)
    }

    // MARK: AK-11 · AK-12 · AK-13 — Raster-Geometrie, Umschalter, Raster mit einem Stream (BUG-01 behoben)

    func testAK11_AK12_AK13_RasterUmschalterUndEinzelnerStreamImRaster() async throws {
        let (w, app) = try await resetAppSession()
        w.setFrame(NSRect(x: 320, y: 165, width: 1280, height: 720), display: true)
        await B08QA.spin(0.5)
        var pickerLog: [String] = ["0: \(pickerState(w))"]
        XCTAssertEqual(picker(w)?.isEnabled, false)
        let specs = [("R1 TS", "/tslive/ak11a.ts"), ("R2 HLS", "/livehls/ak11b/index.m3u8"), ("R3 TS", "/tslive/ak11c.ts"), ("R4 HLS", "/livehls/ak11d/index.m3u8")]
        add(app, channel(specs[0].0, specs[0].1))
        await B08QA.spin(0.5)
        pickerLog.append("1: \(pickerState(w))")
        XCTAssertEqual(picker(w)?.isEnabled, false, "deaktiviert bei einem Stream")
        add(app, channel(specs[1].0, specs[1].1))
        await B08QA.spin(0.5)
        pickerLog.append("2: \(pickerState(w))")
        XCTAssertEqual(picker(w)?.isEnabled, true, "aktiv ab zwei")
        // Umschalten per Klick auf „Raster"
        await clickSegment(w, 1)
        var viaClick = app.layout == .grid
        if !viaClick, let pk = picker(w) {
            pk.selectedSegment = 1
            _ = pk.sendAction(pk.action, to: pk.target)
            await B08QA.spin(0.5)
        }
        B08QA.log("AK-12|Klick auf „Raster“ wirkt=\(viaClick)|layout=\(app.layout.rawValue)")
        XCTAssertEqual(app.layout, .grid)
        let content = w.convertToScreen(w.contentLayoutRect)
        var geo: [String] = []
        func measure(_ n: Int) {
            let xs = closeButtons(w).map(B08UI.frame).sorted { ($0.maxY, -$0.midX) > ($1.maxY, -$1.midX) }
            geo.append("\(n): X=\(xs.map { "(\(Int($0.maxX - content.minX)),\(Int(content.maxY - $0.maxY)))" })")
        }
        measure(2)
        let x2 = closeButtons(w).map(B08UI.frame).sorted { $0.midX < $1.midX }
        let tileW = (content.width - 4) / 2
        XCTAssertEqual(x2[0].maxX + 8, content.minX + tileW, accuracy: 1.5, "zwei nebeneinander, 4 pt Abstand, gleich breit")
        XCTAssertEqual(x2[1].maxX + 8, content.maxX, accuracy: 1.5)
        XCTAssertEqual(x2[0].maxY, x2[1].maxY, accuracy: 1.5)
        add(app, channel(specs[2].0, specs[2].1)); await B08QA.spin(0.6)
        pickerLog.append("3: \(pickerState(w))"); measure(3)
        let x3 = closeButtons(w).map(B08UI.frame)
        let rows3 = Set(x3.map { Int($0.maxY.rounded()) })
        XCTAssertEqual(rows3.count, 2, "drei: 2 × 2 mit leerem Feld")
        add(app, channel(specs[3].0, specs[3].1)); await B08QA.spin(0.6)
        pickerLog.append("4: \(pickerState(w))"); measure(4)
        _ = await B08QA.wait(10) { app.slots.allSatisfy { $0.engine.state == .playing } }
        await B08QA.spin(1.5)
        B08UI.shot(w, "AK-11-raster-vier")
        let x4 = closeButtons(w).map(B08UI.frame)
        let tileH = (content.height - 4) / 2
        let top = x4.filter { abs($0.maxY + 8 - content.maxY) < 2 }, bottom = x4.filter { abs($0.maxY + 8 - (content.minY + tileH)) < 2 }
        B08QA.log("AK-11|geometrie=\(geo)|kachel=\(Int(tileW))x\(Int(tileH))|oben=\(top.count) unten=\(bottom.count)")
        XCTAssertEqual(top.count, 2); XCTAssertEqual(bottom.count, 2, "vier: 2 × 2, gleich groß, 4 pt Abstand")
        // Fokus im Raster: Klick auf eine andere Kachel. Tipp-Gesten reagieren im Test-Host nur bei aktiver App (hier nicht
        // aktivierbar, vorn läuft eine fremde App) – der Versuch wird protokolliert, der Zustand über dieselbe Aktion geprüft,
        // die die Kachel auslöst (`onFocus` → `session.setFocus(index)`).
        let targetX = x4.min { ($0.minY, $0.minX) < ($1.minY, $1.minX) }!   // unten links → Index 2
        await humanClick(w, screen: NSPoint(x: targetX.maxX + 8 - 150, y: targetX.maxY + 8 - 150))
        B08QA.log("AK-14|Raster|Mausklick auf Kachel unten links (App aktiv=\(NSApp.isActive)) → focusedIndex=\(app.focusedIndex)")
        app.setFocus(2)
        await B08QA.spin(1)
        B08UI.shot(w, "AK-14-raster-fokus-unten-links")
        let icons = B08UI.elements(w) { B08UI.role($0) == "AXImage" && B08UI.label($0) == "Volume High" }.map(B08UI.frame)
        B08QA.log("AK-14|Raster|setFocus(2)|\(B08Engine.describe(app))|Lautsprecher-Symbol bei=\(icons)")
        XCTAssertEqual(app.slots.map(\.engine.isMuted), [true, true, false, true])
        XCTAssertEqual(icons.count, 1)
        XCTAssertLessThan(icons.first?.midY ?? 9999, content.minY + tileH, "Lautsprecher-Etikett wandert zur Kachel unten links")
        XCTAssertLessThan(icons.first?.midX ?? 9999, content.minX + tileW)

        // AK-13 / BUG-01 (Build 2026-09-28): im Raster per X auf einen Stream reduzieren – jeder Schritt ohne Absturz,
        // auch 3 → 2 (vorher Absturz „Index out of range“); jeweils das X der Kachel oben links.
        var counts: [Int] = []
        for _ in 0..<3 {
            if let x = closeButtons(w).map({ ($0, B08UI.frame($0)) }).min(by: { ($0.1.minY, $0.1.minX) < ($1.1.minY, $1.1.minX) }) {
                await humanClick(w, screen: NSPoint(x: x.1.midX, y: x.1.midY))
            }
            await B08QA.spin(0.8)
            counts.append(app.slots.count)
        }
        XCTAssertEqual(counts, [3, 2, 1], "4 → 3 → 2 → 1 im Raster per X")
        pickerLog.append("Raster mit 1: \(pickerState(w))")
        B08UI.shot(w, "BUILD-AK-13-raster-ein-stream-umschalter-frei")
        XCTAssertEqual(app.layout, .grid, "Raster bleibt eingestellt")
        XCTAssertEqual(picker(w)?.selectedSegment, 1)
        XCTAssertEqual(picker(w)?.isEnabled, true, "BUG-01: mit einem Stream im Raster führt der Umschalter zurück zu „Fokus“")
        await clickSegment(w, 0)
        if app.layout != .focus, let pk = picker(w) {
            pk.selectedSegment = 0
            _ = pk.sendAction(pk.action, to: pk.target)
            await B08QA.spin(0.5)
        }
        pickerLog.append("nach „Fokus“: \(pickerState(w))")
        B08QA.log("AK-12|umschalter=\(pickerLog)|AK-13|slots=\(app.slots.count) layout=\(app.layout.rawValue)|X-Schritte=\(counts)")
        XCTAssertEqual(app.layout, .focus, "zurück zu „Fokus“")
        XCTAssertEqual(picker(w)?.isEnabled, false, "im Fokus-Layout mit einem Stream gesperrt (AK-12)")
        _ = viaClick
        viaClick = true
    }

    // MARK: AK-12 — Layout bleibt über Schließen/Öffnen (nur ohne Streams erreichbar, sonst AK-23)

    func testAK12_LayoutBleibtUeberSchliessenUndOeffnen() async throws {
        let (w, app) = try await resetAppSession()
        app.layout = .grid   // Raster ohne Streams: einziger Zustand, in dem Schließen im Raster nicht abstürzt
        w.performClose(nil)
        await B08QA.spin(1)
        XCTAssertTrue(B08App.openViaMenu())
        _ = await B08QA.wait(4) { !B08App.multiviewWindows().isEmpty }
        let w2 = try XCTUnwrap(realWindow())
        await B08QA.spin(0.5)
        B08QA.log("AK-12|nach Schließen/Öffnen|layout=\(app.layout.rawValue)|umschalter=\(pickerState(w2))")
        XCTAssertEqual(app.layout, .grid)
        XCTAssertEqual(picker(w2)?.selectedSegment, 1)
        app.layout = .focus
    }

    // MARK: AK-14 · AK-15 — Fokuswechsel per Klick; großes Bild bei VLC und HLS (BUG-02 behoben)

    func testAK14_AK15_FokuswechselVLCUndHLSHauptbildSichtbar() async throws {
        let (w, app) = try await resetAppSession()
        w.setFrame(NSRect(x: 320, y: 165, width: 1280, height: 720), display: true)
        let region = CGRect(x: 0.04, y: 0.35, width: 0.5, height: 0.6)   // Hauptbild ohne Kacheln oben rechts und ohne Etikett
        var results: [String: [Double]] = [:]
        for kind in ["VLC", "HLS"] {
            await safeClear(app)
            await B08QA.spin(0.5)
            let paths = kind == "VLC" ? ["/tslive/ak15v1.ts", "/tslive/ak15v2.ts"] : ["/livehls/ak15h1/index.m3u8", "/livehls/ak15h2/index.m3u8"]
            add(app, channel("\(kind) Eins", paths[0])); add(app, channel("\(kind) Zwei", paths[1]))
            _ = await B08QA.wait(12) { app.slots.allSatisfy { $0.engine.state == .playing } }
            await B08QA.spin(3)
            let before = B08UI.shot(w, "AK-15-\(kind.lowercased())-vor-fokuswechsel").map { B08UI.blackRatio($0, rect: region) } ?? -1
            // Klick auf die kleine Kachel
            let small = closeButtons(w).map(B08UI.frame).sorted { $0.midX > $1.midX }.dropFirst().first!
            let tile = tileRect(fromX: small, size: CGSize(width: 240, height: 135))
            await humanClick(w, screen: NSPoint(x: tile.midX, y: tile.midY - 20))
            let clicked = app.focusedIndex == 1
            if !clicked { app.setFocus(1) }   // gleiche Aktion wie der Tipp auf die Kachel (onFocus → setFocus)
            B08QA.log("AK-14|\(kind)|Mausklick auf kleine Kachel wirkt=\(clicked) (App aktiv=\(NSApp.isActive))|\(B08Engine.describe(app))")
            XCTAssertEqual(app.slots.map(\.engine.isMuted), [true, false], "Ton wandert mit")
            var series: [Double] = [before]
            for (i, t) in [1.0, 5.0, 10.0, 15.0].enumerated() {
                await B08QA.spin(i == 0 ? 1 : (t - [1.0, 5.0, 10.0, 15.0][i - 1]))
                let img = B08UI.shot(w, "AK-15-\(kind.lowercased())-nach-fokuswechsel-\(Int(t))s")
                series.append(img.map { B08UI.blackRatio($0, rect: region) } ?? -1)
            }
            // Fenstergröße ändern
            w.setFrame(NSRect(x: 320, y: 165, width: 1100, height: 640), display: true)
            await B08QA.spin(2)
            series.append(B08UI.shot(w, "AK-15-\(kind.lowercased())-nach-groessenaenderung").map { B08UI.blackRatio($0, rect: region) } ?? -1)
            w.setFrame(NSRect(x: 320, y: 165, width: 1280, height: 720), display: true)
            // Raster und zurück
            app.layout = .grid; await B08QA.spin(1.5)
            app.layout = .focus; await B08QA.spin(2.5)
            series.append(B08UI.shot(w, "AK-15-\(kind.lowercased())-nach-raster-und-zurueck").map { B08UI.blackRatio($0, rect: region) } ?? -1)
            results[kind] = series
            let labels = B08UI.labels(w).filter { $0.contains(kind) || $0 == "Volume High" || $0 == "Mute" }
            B08QA.log("AK-15|\(kind)|Schwarzanteil Hauptbild vorher, 1 s, 5 s, 10 s, 15 s, nach Größenänderung, nach Raster↔Fokus=\(series.map(B08QA.f2))|etiketten=\(labels)")
        }
        let vlc = results["VLC"]!, hls = results["HLS"]!
        XCTAssertLessThan(vlc[0], 0.2, "VLC: vor dem Wechsel Bild da")
        XCTAssertLessThan(hls.dropFirst().prefix(4).max() ?? 1, 0.2, "HLS: nach dem Wechsel Bild da")
        XCTAssertLessThan(vlc.last ?? 1, 0.2, "VLC: nach Raster und zurück Bild")
        // Seit B08 · BUG-02 (Build 2026-09-28): das große Bild zeigt nach dem Fokuswechsel den neuen VLC-Stream
        XCTAssertLessThan(vlc[1...5].max() ?? 1, 0.2, "VLC-Hauptbild nach dem Fokuswechsel sichtbar (1–15 s, nach Größenänderung)")
    }

    // MARK: AK-16 — X des großen Streams liegt frei (BUG-04 behoben)

    func testAK16_XDesGrossenStreamsErreichbar() async throws {
        let (w, app) = try await resetAppSession()
        w.setFrame(NSRect(x: 320, y: 165, width: 1280, height: 720), display: true)
        add(app, channel("Groß", "/tslive/ak16a.ts")); add(app, channel("Klein", "/tslive/ak16b.ts"))
        await B08QA.spin(3)
        let xs = closeButtons(w).map { ($0, B08UI.frame($0)) }.sorted { $0.1.midX > $1.1.midX }
        let bigX = xs[0], smallX = xs[1]
        let smallTile = tileRect(fromX: smallX.1, size: CGSize(width: 240, height: 135))
        let covered = smallTile.intersects(bigX.1)
        B08QA.log("AK-16|großes X=\(bigX.1)|erste kleine Kachel=\(smallTile)|X von der Kachel verdeckt=\(covered)")
        // Seit B08 · BUG-04 (Build 2026-09-28): die kleinen Kacheln beginnen unterhalb der Leiste – das X liegt frei.
        XCTAssertFalse(covered, "großes X von keiner kleinen Kachel verdeckt")
        let focusedBefore = app.focusedIndex
        await humanClick(w, screen: NSPoint(x: bigX.1.midX, y: bigX.1.midY))
        B08UI.shot(w, "BUILD-AK-16-grosses-x-entfernt")
        B08QA.log("AK-16|Mausklick auf das große X|fokus vorher=\(focusedBefore)|slots=\(app.slots.map(\.channel.name))|hit=\(B08UI.hitView(w, at: w.convertPoint(fromScreen: NSPoint(x: bigX.1.midX, y: bigX.1.midY))))")
        XCTAssertEqual(app.slots.map(\.channel.name), ["Klein"], "ein Mausklick auf das große X entfernt den großen Stream")
        XCTAssertFalse(app.slots[0].engine.isMuted, "der nachrückende Stream hat Ton (AK-17)")
    }

    // MARK: AK-18 — Player im Hauptfenster und Multiview haben beide Ton (OF-05)

    func testAK18_PlayerUndMultiviewHabenBeideTon() async throws {
        let (_, app) = try await resetAppSession()
        add(app, channel("Multiview TS", "/tslive/ak18mv.ts"))
        let p = try playlist("QA Player", [("Player HLS", "/livehls/ak18p/index.m3u8")])
        let c = try XCTUnwrap(p.channels.first)
        let avBefore = B08Registry.liveAVPlayers.count
        let pw = track(B08UI.window(NavigationStack { PlayerView(channel: c) }.modelContainer(container), size: CGSize(width: 640, height: 400),
                                    origin: CGPoint(x: 40, y: 500)))
        _ = await B08QA.wait(10) { app.slots[0].engine.state == .playing && B08Registry.liveAVPlayers.count > avBefore }
        await B08QA.spin(2)
        let player = B08Registry.liveAVPlayers.dropFirst(avBefore).first
        B08QA.log("AK-18|player isMuted=\(String(describing: player?.isMuted)) volume=\(String(describing: player?.volume))|multiview \(B08Engine.describe(app))|titel=\(pw.title)")
        XCTAssertEqual(player?.isMuted, false, "Player mit Ton (Zustand)")
        XCTAssertEqual(app.slots[0].engine.isMuted, false, "Multiview-Fokus mit Ton")
        XCTAssertEqual(B08Engine.innerMuted(app.slots[0].engine), false)
        XCTAssertEqual(player?.volume, 0, "Tonschutz der QA: Lautstärke 0")
        B08UI.shot(pw, "AK-18-player-neben-multiview")
    }

    // MARK: AK-20 · AK-21 — Schließen über den roten Knopf leert für alle Fenster

    func testAK20_AK21_SchliessenLeertFuerAlleFenster() async throws {
        let (w, app) = try await resetAppSession()
        let p = try playlist("QA Schließen", (1...5).map { ("S\($0)", "/tslive/ak20ui-\($0).ts") }, favorites: true)
        let a = listWindow(p, session: app, origin: CGPoint(x: 40, y: 60))
        let b = favoritesWindow(session: app, origin: CGPoint(x: 600, y: 60))
        await B08QA.spin(1.5)
        for i in 1...4 { await clickPlus(i % 2 == 0 ? b : a, "S\(i)", session: app) }
        _ = await B08QA.wait(10) { app.slots.count == 4 && app.slots.allSatisfy { $0.engine.state == .playing } }
        let weaks = app.slots.map { B08Weak($0.engine, $0.channel.name) }
        XCTAssertEqual(app.slots.count, 4, "hinzugefügt aus zwei Fenstern")
        XCTAssertEqual(Set(cards(a).map(B08UI.help)), ["Multiview voll (max. 4)"])
        let mv = try XCTUnwrap(realWindow() ?? Optional(w))
        mv.standardWindowButton(.closeButton)?.performClick(nil)       // roter Knopf
        await B08QA.spin(0.3)
        let freed = weaks.filter { !$0.alive }.count
        let closed = await B08QA.wait(5) { self.server.openStreamConnections(containing: "ak20ui").isEmpty }
        await B08QA.spin(0.5)
        B08QA.log("AK-20|roter Knopf|slots=\(app.slots.count)|engines frei=\(freed)/4|verbindungen zu nach \(closed.map(B08QA.f1) ?? "offen") s|tooltips A=\(Set(cards(a).map(B08UI.help))) B=\(Set(cards(b).map(B08UI.help)))")
        XCTAssertTrue(app.isEmpty)
        XCTAssertEqual(freed, 4, "alle Engines sofort freigegeben")
        XCTAssertLessThanOrEqual(closed ?? 99, 3.0)
        XCTAssertEqual(Set(cards(a).map(B08UI.help)), ["Zu Multiview hinzufügen"])
        XCTAssertEqual(Set(cards(b).map(B08UI.help)), ["Zu Multiview hinzufügen"], "AK-21: für alle Fenster leer")
        await clickPlus(b, "S5", session: app)
        _ = await B08QA.wait(4) { !B08App.multiviewWindows().isEmpty }
        B08QA.log("AK-20|nächster ⊞|fenster offen=\(!B08App.multiviewWindows().isEmpty)|slots=\(app.slots.map(\.channel.name))")
        XCTAssertEqual(app.slots.map(\.channel.name), ["S5"])
        XCTAssertFalse(B08App.multiviewWindows().isEmpty)
    }

    // MARK: AK-22 · EC-07 — minimiert und ohne Hauptfenster laufen die Streams weiter

    func testAK22_EC07_MinimiertUndOhneListenfensterLaeuftWeiter() async throws {
        let (w, app) = try await resetAppSession()
        let p = try playlist("QA Minimieren", [("M1", "/tslive/ak22a.ts"), ("M2", "/tslive/ak22b.ts"), ("M3", "/tslive/ak22c.ts")])
        let list = listWindow(p, session: app)
        await B08QA.spin(1.2)
        await clickPlus(list, "M1", session: app); await clickPlus(list, "M2", session: app)
        _ = await B08QA.wait(8) { app.slots.count == 2 && app.slots.allSatisfy { $0.engine.state == .playing } }
        w.miniaturize(nil)
        _ = await B08QA.wait(3) { w.isMiniaturized }
        let b0 = server.openStreamConnections(containing: "ak22").map(\.bytesSent).reduce(0, +)
        await B08QA.spin(3)
        let b1 = server.openStreamConnections(containing: "ak22").map(\.bytesSent).reduce(0, +)
        B08QA.log("AK-22|minimiert=\(w.isMiniaturized)|slots=\(app.slots.count)|\(B08Engine.describe(app))|bytes +\(b1 - b0) in 3 s")
        XCTAssertTrue(w.isMiniaturized)
        XCTAssertEqual(app.slots.count, 2)
        XCTAssertGreaterThan(b1, b0, "Streams laufen minimiert weiter")
        // EC-07: ⊞ bei minimiertem Fenster
        await clickPlus(list, "M3", session: app)
        await B08QA.spin(1.5)
        B08QA.log("EC-07|⊞ bei minimiertem Fenster|slots=\(app.slots.count)|minimiert=\(w.isMiniaturized)|sichtbar=\(w.isVisible)")
        XCTAssertEqual(app.slots.count, 3)
        // alle Listenfenster zu
        B08UI.close(list); windows.removeAll { $0 === list }
        await B08QA.spin(0.5)
        let c0 = server.openStreamConnections(containing: "ak22").map(\.bytesSent).reduce(0, +)
        await B08QA.spin(3)
        let c1 = server.openStreamConnections(containing: "ak22").map(\.bytesSent).reduce(0, +)
        B08QA.log("AK-22|ohne Listenfenster|slots=\(app.slots.count)|offen=\(server.openStreamConnections(containing: "ak22").count)|bytes +\(c1 - c0) in 3 s")
        XCTAssertGreaterThan(c1, c0)
        if w.isMiniaturized { w.deminiaturize(nil); await B08QA.spin(1) }
    }

    // MARK: AK-29 — keine Tastatur, jede Taste endet ohne Empfänger (Warnton abgefangen)

    /// Sendet Tasten, die ohne Empfänger zum Systembeep führen. Der Beep-Wächter ersetzt `noResponderFor:`; ob ein
    /// anderer Pfad `NSBeep` ruft, ist nicht ausgeschlossen. Deshalb **nur mit `B08_TASTEN=1`** (Anweisung „alles ohne Ton").
    /// Ergebnis des einzigen Laufs (abgebrochener Teil, 2026-09-26 16:34): Zustand unverändert, 7 von 9 Tasten erreichten
    /// das Ende der Responder-Kette (AppDelegate `keyDown:`), `firstResponder` = `VLCVideoLayerView`.
    func testAK29_KeineTastatursteuerungWarntonAbgefangen() async throws {
        guard ProcessInfo.processInfo.environment["B08_TASTEN"] == "1" else {
            throw XCTSkip("nur mit B08_TASTEN=1 – unbehandelte Tasten würden ohne Wächter den Systembeep auslösen")
        }
        XCTAssertTrue(B08BeepGuard.install(), "Beep-Wächter aktiv")
        B08BeepGuard.reset()
        let (w, app) = try await resetAppSession()
        add(app, channel("K1", "/tslive/ak29a.ts")); add(app, channel("K2", "/tslive/ak29b.ts"))
        _ = await B08QA.wait(8) { app.slots.allSatisfy { $0.engine.state == .playing } }
        let snap = { "\(app.focusedIndex)|\(app.layout.rawValue)|\(app.slots.map(\.engine.isMuted))|\(app.slots.map(\.engine.isPaused))|\(w.styleMask.contains(.fullScreen))" }
        let before = snap()
        let keys: [(String, UInt16, String)] = [(" ", 49, "Leertaste"), ("m", 46, "M"), ("f", 3, "F"), ("p", 35, "P"),
                                                ("\u{F700}", 126, "↑"), ("\u{F701}", 125, "↓"), ("\u{1B}", 53, "Esc"), ("1", 18, "1"), ("\t", 48, "Tab")]
        var proTaste: [String] = []
        for (c, code, name) in keys {
            let n0 = B08BeepGuard.hits.count
            key(c, keyCode: code, in: w)
            await B08QA.spin(0.15)
            proTaste.append("\(name)=\(B08BeepGuard.hits.count > n0 ? "ohne Empfänger" : "verarbeitet")")
        }
        await B08QA.spin(0.5)
        let after = snap()
        B08QA.log("AK-29|zustand vorher=\(before) nachher=\(after)|je Taste=\(proTaste)|abgefangene Warntöne=\(B08BeepGuard.hits.count)|firstResponder=\(String(describing: w.firstResponder.map { type(of: $0) }))")
        XCTAssertEqual(before, after, "keine Taste bewirkt etwas")
        XCTAssertGreaterThan(B08BeepGuard.hits.count, 0, "Tasten erreichen das Ende der Responder-Kette (sonst Warnton)")
        XCTAssertEqual(B08App.windowMenuItem()?.keyEquivalent, "", "kein Tastenkürzel für Multiview")
    }

    // MARK: AK-25 · AK-26 · AK-31 · AK-32 (UI) — Fehler je Kachel, keine Adresse, Ladeanzeigen über dem Limit

    func testAK25_AK26_AK32_FehlerKachelnZeigenKeineAdresse() async throws {
        let (w, app) = try await resetAppSession()
        w.setFrame(NSRect(x: 320, y: 165, width: 1280, height: 720), display: true)
        let x = try await importXtream(container.mainContext, output: .mpegts, name: "QA Xtream")
        let xc = x.channels.sorted { $0.name < $1.name }
        add(app, channel("404 HLS", "/404/ak32/index.m3u8"))
        add(app, Channel(name: "Port zu HLS", streamURL: URL(string: "http://127.0.0.1:9/ak32/index.m3u8")!))
        add(app, channel("404 TS", "/404/ak32.ts"))
        add(app, xc[0])
        app.layout = .grid
        await B08QA.spin(8)
        let labels = B08UI.labels(w)
        let busy = B08UI.elements(w) { B08UI.role($0).contains("BusyIndicator") || B08UI.role($0).contains("ProgressIndicator") }.count
        B08UI.shot(w, "AK-25-26-fehler-je-kachel")
        let forbidden = ["127.0.0.1", "\(server.port)", B08QA.user, B08QA.pass, "/live/", "ak32", ":9"]
        let leaks = labels.filter { l in forbidden.contains { l.contains($0) } }
        B08QA.log("AK-32|labels=\(labels)|ladeanzeigen=\(busy)|lecks=\(leaks)|\(B08Engine.describe(app))")
        XCTAssertTrue(labels.contains("Wiedergabe fehlgeschlagen"))
        XCTAssertTrue(labels.contains("The requested URL was not found on this server."))
        XCTAssertTrue(labels.contains("Could not connect to the server."))
        XCTAssertEqual(leaks, [], "weder Adresse noch Benutzername oder Passwort")
        // Seit B06 · BUG-01 (Build 2026-09-27): die VLC-Kachel mit 404 zeigt die Fehleransicht statt der Ladeanzeige
        XCTAssertTrue(labels.contains(VLCPlaybackEngine.Failure.cannotOpen.message), "404 TS: Meldung")
        XCTAssertEqual(busy, 0, "404 TS: keine Ladeanzeige mehr")
        await safeClear(app)
        // AK-31: Anbieterlimit 1 – eine Kachel spielt, drei zeigen die Ladeanzeige (erst, wenn die alte Verbindung zu ist)
        _ = await B08QA.wait(5) { self.server.openStreamConnections(containing: "/live/").isEmpty }
        server.configure(connectionLimit: 1)
        for c in xc { add(app, c) }
        app.layout = .grid
        await B08QA.spin(10)
        let busy31 = B08UI.elements(w) { B08UI.role($0).contains("BusyIndicator") || B08UI.role($0).contains("ProgressIndicator") }.count
        let labels31 = B08UI.labels(w)
        B08UI.shot(w, "AK-31-anbieterlimit-eine-verbindung")
        B08QA.log("AK-31|UI|ladeanzeigen=\(busy31)|fehlermeldungen=\(labels31.filter { $0.contains("fehlgeschlagen") }.count)|\(B08Engine.describe(app))")
        XCTAssertEqual(app.slots.first?.engine.state, .playing, "die erste Kachel spielt")
        // Seit B06 · BUG-01: die drei abgelehnten Kacheln melden sich (403 → „… der Zugang wurde abgelehnt.“)
        XCTAssertEqual(busy31, 0, "keine Ladeanzeige ohne Ende")
        XCTAssertEqual(labels31.filter { $0.contains("fehlgeschlagen") }.count, 3, "drei Meldungen")
        // Seit B08 · BUG-06 (Build 2026-09-28): die abgelehnten Kacheln erklären das Verbindungslimit auf Deutsch
        XCTAssertEqual(labels31.filter { $0 == MultiviewTile.connectionLimitHint }.count, 3, "Hinweis auf das Verbindungslimit")
        app.layout = .focus
    }

    // MARK: EC-10 · EC-11 — kleinstes Fenster (BUG-10 behoben), langer Name

    func testEC10_EC11_KleinstesFensterUndLangerName() async throws {
        let (w, app) = try await resetAppSession()
        add(app, channel(String(repeating: "Sehr langer Sendername ", count: 20), "/hang/ec11a.ts"))
        for i in 2...4 { add(app, channel("Kachel \(i)", "/hang/ec10-\(i).ts")) }
        await B08QA.spin(1)
        let minSize = w.minSize, contentMin = w.contentMinSize
        // wie ein Nutzer, der das Fenster auf die kleinste zulässige Größe zieht
        w.setFrame(w.constrainFrameRect(NSRect(x: 320, y: 300, width: max(minSize.width, 1), height: max(minSize.height, 1)), to: w.screen), display: true)
        await B08QA.spin(1.5)
        B08QA.log("EC-10|minSize=\(minSize)|contentMinSize=\(contentMin)")
        let content = w.convertToScreen(w.contentLayoutRect)
        let tiles = closeButtons(w).map(B08UI.frame).sorted { $0.midX > $1.midX }.dropFirst()
            .map { tileRect(fromX: $0, size: CGSize(width: 240, height: 135)) }
        let lowest = tiles.map(\.minY).min() ?? 0
        B08UI.shot(w, "EC-10-kleinstes-fenster")
        let labels = B08UI.labels(w).map { $0.count > 60 ? "\($0.prefix(30))…(\($0.count) Zeichen)" : $0 }
        B08QA.log("EC-10|angefordert 300x200 → fenster \(Int(w.frame.width))x\(Int(w.frame.height)) inhalt \(Int(content.width))x\(Int(content.height))|unterste kleine Kachel endet \(Int(lowest - content.minY)) pt über dem Fensterboden|EC-11 etiketten=\(labels)")
        XCTAssertTrue(app.slots.count == 4)
        // Seit B08 · BUG-10 (Build 2026-09-28): Mindestgröße, in die alle kleinen Kacheln samt Rand passen
        XCTAssertGreaterThanOrEqual(content.height, MultiviewScreen.minimumContentSize.height - 1, "Inhalt nicht kleiner als die Mindesthöhe")
        XCTAssertGreaterThanOrEqual(content.width, MultiviewScreen.minimumContentSize.width - 1)
        XCTAssertGreaterThanOrEqual(lowest, content.minY, "die unterste kleine Kachel endet im Fenster")
        XCTAssertEqual(tiles.count, 3)
        XCTAssertNotNil(picker(w), "Umschalter sichtbar")
        w.setFrame(NSRect(x: 320, y: 165, width: 1280, height: 720), display: true)
    }
}
