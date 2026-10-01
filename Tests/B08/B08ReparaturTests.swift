import XCTest
import SwiftUI
import SwiftData
import AppKit
@testable import MikaPlusPlayer

/// B08 · Multiview — Reparatur (Build 2026-09-28): Belege für BUG-01, BUG-02, BUG-03, BUG-04, BUG-06 und BUG-10 am echten
/// Fenster „Multiview" mit der Session der App. Kein Ton: Medien ohne Tonspur, jede Engine sofort auf Lautstärke 0, keine
/// Tasten. Nachweisbilder heißen `BUILD-…` (die Bilder der QA bleiben unberührt).
@MainActor
final class B08ReparaturTests: B08UITestCase {

    // MARK: Hilfen

    /// Zeichenfläche einer VLC-Engine (per Reflection, `fileprivate` in der Engine).
    private func drawable(_ e: any PlaybackEngine) -> NSView? { B08Engine.child(e, "drawableView") as? NSView }

    /// Rahmen der Zeichenfläche in Bildschirmkoordinaten, `nil`, wenn sie in keinem Fenster hängt.
    private func surfaceRect(_ e: any PlaybackEngine) -> NSRect? {
        guard let v = drawable(e), let win = v.window else { return nil }
        return win.convertToScreen(v.convert(v.bounds, to: nil))
    }

    private func near(_ a: NSRect?, _ b: NSRect, _ tol: CGFloat = 2) -> Bool {
        guard let a else { return false }
        return abs(a.minX - b.minX) <= tol && abs(a.maxX - b.maxX) <= tol && abs(a.minY - b.minY) <= tol && abs(a.maxY - b.maxY) <= tol
    }

    private func describeSurfaces(_ s: MultiviewSession) -> String {
        s.slots.map { "\($0.channel.name):\(surfaceRect($0.engine).map { "(\(Int($0.minX)),\(Int($0.minY)),\(Int($0.width))x\(Int($0.height)))" } ?? "kein Fenster")" }
            .joined(separator: " ")
    }

    /// Rechteck der großen Fläche (Inhalt unter der Titelleiste; die Videofläche reicht bis unter die Titelleiste).
    private func contentRect(_ w: NSWindow) -> NSRect { w.convertToScreen(w.contentLayoutRect) }

    private func smallTileRects(_ w: NSWindow, count: Int) -> [NSRect] {
        let c = contentRect(w)
        let size = MultiviewMetrics.smallTileSize
        return (0..<count).map { i in
            NSRect(x: c.maxX - MultiviewMetrics.smallTileTrailingInset - size.width,
                   y: c.maxY - MultiviewMetrics.smallTileTopInset - size.height - CGFloat(i) * (size.height + MultiviewMetrics.smallTileSpacing),
                   width: size.width, height: size.height)
        }
    }

    /// Bildschirmrechteck → Anteile des Fensterbilds (oben links), für `B08UI.blackRatio`.
    private func fraction(_ r: NSRect, in w: NSWindow) -> CGRect {
        let f = w.frame
        return CGRect(x: (r.minX - f.minX) / f.width, y: (f.maxY - r.maxY) / f.height, width: r.width / f.width, height: r.height / f.height)
    }

    /// Liegt die Zeichenfläche von `a` in der Ansichtshierarchie über der von `b` (später gezeichnet)? `nil`, wenn nicht ermittelbar.
    private func isDrawn(_ a: NSView, above b: NSView) -> Bool? {
        func chain(_ v: NSView) -> [NSView] { var c: [NSView] = []; var cur: NSView? = v; while let x = cur { c.append(x); cur = x.superview }; return c }
        let ca = chain(a), cb = chain(b)
        guard let common = ca.first(where: { x in cb.contains { $0 === x } }),
              let ia = ca.firstIndex(where: { $0 === common }), let ib = cb.firstIndex(where: { $0 === common }),
              ia > 0, ib > 0 else { return nil }
        let childA = ca[ia - 1], childB = cb[ib - 1]
        guard let pa = common.subviews.firstIndex(where: { $0 === childA }), let pb = common.subviews.firstIndex(where: { $0 === childB }) else { return nil }
        return pa > pb
    }

    private func xClick(_ w: NSWindow, _ frame: NSRect) async {
        await humanClick(w, screen: NSPoint(x: frame.midX, y: frame.midY))
    }

    // MARK: BUG-01 · Raster: Leeren und Entfernen bei jeder Anzahl ohne Absturz; mit einem Stream zurück zu „Fokus"

    /// Vorher stürzte `clear()` bei sichtbarem Raster mit 1–4 Streams ab (Gegenprüfung QA 1), ebenso das Entfernen von
    /// 3 auf 2 und von 1 auf 0. Hier ohne den Umweg über „Fokus" (den die übrigen Tests zum Schutz nehmen).
    func testBUG01_RasterLeerenUndEntfernenBeiJederAnzahlOhneAbsturz() async throws {
        let (w, s) = try await resetAppSession()
        w.setFrame(NSRect(x: 320, y: 165, width: 1280, height: 720), display: true)
        for n in 1...4 {
            for i in 1...n { add(s, channel("Raster \(n).\(i)", "/hang/bug01-\(n)-\(i).ts")) }
            s.layout = .grid
            await B08QA.spin(0.8)
            XCTAssertEqual(closeButtons(w).count, n, "\(n) Kacheln im Raster sichtbar")
            s.clear()                                            // direkt im Raster (Weg „Fenster schließen")
            await B08QA.spin(0.8)
            B08QA.log("BUG-01|clear() im Raster mit \(n)|slots=\(s.slots.count)|layout=\(s.layout.rawValue)|leerzustand=\(B08UI.labels(w).contains("Kein Stream im Multiview"))")
            XCTAssertTrue(s.isEmpty)
            XCTAssertTrue(B08UI.labels(w).contains("Kein Stream im Multiview"))
        }
        // Entfernen von vorn, von hinten und aus der Mitte, jeweils mit Zeichnen dazwischen: 4 → 3 → 2 → 1 → 0
        for order in ["vorn", "hinten", "mitte"] {
            for i in 1...4 { add(s, channel("\(order) \(i)", "/hang/bug01-\(order)-\(i).ts")) }
            s.layout = .grid
            await B08QA.spin(0.6)
            var counts: [Int] = []
            while !s.isEmpty {
                let index = order == "vorn" ? 0 : (order == "hinten" ? s.slots.count - 1 : s.slots.count / 2)
                s.remove(s.slots[index].id)
                await B08QA.spin(0.5)
                counts.append(closeButtons(w).count)
            }
            B08QA.log("BUG-01|Entfernen im Raster (\(order))|sichtbare Kacheln nach jedem Schritt=\(counts)")
            XCTAssertEqual(counts, [3, 2, 1, 0], "Raster schrumpft ohne Absturz (\(order))")
        }
        s.layout = .focus
    }

    func testBUG01_EinStreamImRasterZurueckZuFokus() async throws {
        let (w, s) = try await resetAppSession()
        w.setFrame(NSRect(x: 320, y: 165, width: 1280, height: 720), display: true)
        add(s, channel("Bleibt", "/tslive/bug01-a.ts")); add(s, channel("Geht", "/tslive/bug01-b.ts"))
        await B08QA.spin(0.5)
        await clickSegment(w, 1)
        if s.layout != .grid { s.layout = .grid }
        await B08QA.spin(0.5)
        // X der rechten Kachel per Mausklick: 2 → 1 im Raster
        let right = try XCTUnwrap(closeButtons(w).map(B08UI.frame).max { $0.midX < $1.midX })
        await xClick(w, right)
        XCTAssertEqual(s.slots.map(\.channel.name), ["Bleibt"])
        XCTAssertEqual(s.layout, .grid)
        let stateGrid = pickerState(w)
        XCTAssertEqual(picker(w)?.isEnabled, true, "mit einem Stream im Raster: Umschalter frei für den Weg zurück")
        B08UI.shot(w, "BUILD-BUG-01-raster-ein-stream-umschalter-frei")
        await clickSegment(w, 0)
        if s.layout != .focus, let pk = picker(w) {            // Mausereignis in der Titelleiste nicht zugestellt: Aktion des Umschalters
            pk.selectedSegment = 0
            _ = pk.sendAction(pk.action, to: pk.target)
            await B08QA.spin(0.5)
        }
        let stateFocus = pickerState(w)
        B08QA.log("BUG-01|ein Stream|Raster: \(stateGrid)|nach Klick auf „Fokus“: \(stateFocus)|layout=\(s.layout.rawValue)")
        XCTAssertEqual(s.layout, .focus, "zurück zu „Fokus“")
        XCTAssertEqual(picker(w)?.isEnabled, false, "im Fokus mit einem Stream wie bisher gesperrt")
        // Das letzte X und das Schließen des Fensters bleiben ohne Absturz
        let last = try XCTUnwrap(closeButtons(w).first.map(B08UI.frame))
        await xClick(w, last)
        XCTAssertTrue(s.isEmpty)
    }

    // MARK: BUG-02 · Die Zeichenfläche bleibt bei ihrem Stream (Fokuswechsel, Raster nach dem Entfernen, Layoutwechsel)

    func testBUG02_VLCZeichenflaecheFolgtIhremStream() async throws {
        let (w, s) = try await resetAppSession()
        w.setFrame(NSRect(x: 320, y: 165, width: 1280, height: 720), display: true)
        for i in 1...3 { add(s, channel("V\(i)", "/tslive/bug02-\(i).ts")) }
        _ = await B08QA.wait(12) { s.slots.allSatisfy { $0.engine.state == .playing } }
        await B08QA.spin(2)
        let content = contentRect(w)
        let region = CGRect(x: 0.04, y: 0.35, width: 0.5, height: 0.6)    // großes Bild ohne kleine Kacheln und Etikett
        var protokoll: [String] = []
        // Fokus-Layout: jede Kachel einmal nach vorn (1, 2, 0)
        for target in [1, 2, 0] {
            s.setFocus(target)
            await B08QA.spin(2)
            let focused = s.slots[target]
            let others = s.slots.enumerated().filter { $0.offset != target }.map(\.element)
            let small = smallTileRects(w, count: others.count)
            let img = B08UI.shot(w, "BUILD-BUG-02-fokus-\(focused.channel.name)")
            let black = img.map { B08UI.blackRatio($0, rect: region) } ?? -1
            // Kleine Kacheln unterhalb der Leiste: Bild sichtbar (nicht schwarz) und über dem großen Stream gezeichnet
            let smallBlack = small.map { r in img.map { B08UI.blackRatio($0, rect: fraction(NSRect(x: r.minX + 20, y: r.minY + 10, width: r.width - 40, height: r.height - 55), in: w)) } ?? -1 }
            let above = others.map { o -> Bool? in
                guard let a = drawable(o.engine), let b = drawable(focused.engine) else { return nil }
                return isDrawn(a, above: b)
            }
            let line = "Fokus auf \(focused.channel.name)|flächen \(describeSurfaces(s))|schwarz groß=\(B08QA.f2(black)) klein=\(smallBlack.map(B08QA.f2))|klein über groß=\(above)"
            protokoll.append(line)
            B08QA.log("BUG-02|\(line)")
            let big = surfaceRect(focused.engine)
            XCTAssertNotNil(big, "die Fläche des fokussierten Streams hängt im Fenster")
            XCTAssertGreaterThanOrEqual(big?.width ?? 0, content.width - 2, "… und füllt das große Bild")
            XCTAssertGreaterThanOrEqual(big?.height ?? 0, content.height - 2)
            for (i, o) in others.enumerated() {
                XCTAssertTrue(near(surfaceRect(o.engine), small[i]), "\(o.channel.name) als kleine Kachel \(i + 1): \(String(describing: surfaceRect(o.engine))) statt \(small[i])")
            }
            XCTAssertLessThan(black, 0.2, "großes Bild zeigt den fokussierten VLC-Stream")
            XCTAssertTrue(smallBlack.allSatisfy { $0 >= 0 && $0 < 0.5 }, "kleine Kacheln zeigen ein Bild: \(smallBlack)")
            XCTAssertTrue(above.allSatisfy { $0 == true }, "kleine Kacheln liegen über dem großen Stream: \(above)")
        }
        // Layoutwechsel Raster ↔ Fokus
        s.layout = .grid
        await B08QA.spin(1.5)
        s.layout = .focus
        await B08QA.spin(1.5)
        XCTAssertTrue(s.slots.allSatisfy { surfaceRect($0.engine) != nil }, "nach Raster ↔ Fokus alle Flächen im Fenster")
        // Raster: vorderste Kachel entfernen – die nachrückenden zeigen ihr eigenes Bild an ihrer neuen Stelle
        add(s, channel("V4", "/tslive/bug02-4.ts"))
        _ = await B08QA.wait(12) { s.slots.allSatisfy { $0.engine.state == .playing } }
        s.layout = .grid
        await B08QA.spin(2)
        s.remove(s.slots[0].id)
        await B08QA.spin(2.5)
        let zellen = [CGRect(x: 0.03, y: 0.20, width: 0.44, height: 0.30), CGRect(x: 0.53, y: 0.20, width: 0.44, height: 0.30),
                      CGRect(x: 0.03, y: 0.64, width: 0.44, height: 0.30)]
        let img = B08UI.shot(w, "BUILD-BUG-02-raster-nach-x-vorne")
        let schwarz = zellen.map { r in img.map { B08UI.blackRatio($0, rect: r) } ?? -1 }
        let tileW = (content.width - 4) / 2, tileH = (content.height - 4) / 2
        let cells = [NSRect(x: content.minX, y: content.maxY - tileH, width: tileW, height: tileH),
                     NSRect(x: content.maxX - tileW, y: content.maxY - tileH, width: tileW, height: tileH),
                     NSRect(x: content.minX, y: content.minY, width: tileW, height: tileH)]
        B08QA.log("BUG-02|Raster nach Entfernen der ersten|slots=\(s.slots.map(\.channel.name))|flächen \(describeSurfaces(s))|schwarz je Zelle=\(schwarz.map(B08QA.f2))")
        XCTAssertEqual(s.slots.map(\.channel.name), ["V2", "V3", "V4"])
        for (i, slot) in s.slots.enumerated() {
            // Oben liegt die Fläche unter der Titelleiste (ignoresSafeArea): nur Unterkante, Seiten und Mindesthöhe prüfen.
            let r = surfaceRect(slot.engine)
            XCTAssertNotNil(r, "\(slot.channel.name) hängt im Fenster")
            XCTAssertEqual(r?.minX ?? -1, cells[i].minX, accuracy: 2, "\(slot.channel.name) in Zelle \(i + 1)")
            XCTAssertEqual(r?.maxX ?? -1, cells[i].maxX, accuracy: 2)
            XCTAssertEqual(r?.minY ?? -1, cells[i].minY, accuracy: 2)
            XCTAssertGreaterThanOrEqual(r?.height ?? 0, tileH - 2)
        }
        XCTAssertTrue(schwarz.allSatisfy { $0 >= 0 && $0 < 0.2 }, "drei Bilder: \(schwarz)")
        s.layout = .focus
        _ = protokoll
    }

    // MARK: BUG-04 · Das X des großen Streams liegt frei und entfernt ihn

    func testBUG04_GrossesXEntferntDenFokussiertenStream() async throws {
        let (w, s) = try await resetAppSession()
        w.setFrame(NSRect(x: 320, y: 165, width: 1280, height: 720), display: true)
        for i in 1...4 { add(s, channel("S\(i)", "/hang/bug04-\(i).ts")) }
        await B08QA.spin(1)
        var verlauf: [String] = []
        while s.slots.count > 1 {
            let xs = closeButtons(w).map(B08UI.frame).sorted { $0.midX > $1.midX }
            let bigX = xs[0]
            let tiles = xs.dropFirst().map { tileRect(fromX: $0, size: MultiviewMetrics.smallTileSize) }
            let covered = tiles.contains { $0.intersects(bigX) }
            if s.slots.count == 4 { B08UI.shot(w, "BUILD-BUG-04-grosses-x-frei") }
            let focusedName = s.slots[s.focusedIndex].channel.name
            await xClick(w, bigX)
            verlauf.append("\(focusedName) entfernt=\(!s.slots.contains { $0.channel.name == focusedName }) übrig=\(s.slots.map(\.channel.name))")
            XCTAssertFalse(covered, "großes X \(bigX) von keiner kleinen Kachel verdeckt: \(tiles)")
            XCTAssertFalse(s.slots.contains { $0.channel.name == focusedName }, "Klick auf das große X entfernt den großen Stream")
            XCTAssertEqual(s.slots.filter { !$0.engine.isMuted }.count, 1, "genau einer mit Ton")
        }
        B08QA.log("BUG-04|Klicks auf das große X|\(verlauf)")
        XCTAssertEqual(s.slots.count, 1)
        // Geometrie: kleine Kacheln beginnen unterhalb der Leiste des großen Streams
        let content = contentRect(w)
        XCTAssertEqual(MultiviewMetrics.smallTileTopInset, MultiviewMetrics.chromePadding + MultiviewMetrics.closeButtonSize + 8)
        let bigX = try XCTUnwrap(closeButtons(w).first.map(B08UI.frame))
        XCTAssertEqual(content.maxY - bigX.minY, MultiviewMetrics.chromePadding + MultiviewMetrics.closeButtonSize, accuracy: 1.5,
                       "X-Knopf 30 pt, 8 pt vom oberen Rand")
    }

    // MARK: BUG-03 · Klick auf den abgeblendeten ⊞ bewirkt nichts – Senderliste und Favoriten-Tab

    func testBUG03_GrauerPlusImFavoritenTabOeffnetKeinenPlayer() async throws {
        let (_, app) = try await resetAppSession()
        let p = try playlist("QA Voll Fav", (1...5).map { ("Fav \($0) HLS", "/livehls/bug03-\($0)/index.m3u8") }, favorites: true)
        _ = p
        let fav = favoritesWindow(session: app)
        await B08QA.spin(1.5)
        for i in 1...4 { await clickPlus(fav, "Fav \(i) HLS", session: app) }
        await B08QA.spin(1)
        silenceAll(app)
        XCTAssertEqual(app.slots.count, 4)
        let titleBefore = fav.title
        let avBefore = B08Registry.liveAVPlayers.count
        let before5 = server.requests(containing: "bug03-5").count
        await clickPlus(fav, "Fav 5 HLS", session: app)
        await B08QA.spin(2)
        let req5 = server.requests(containing: "bug03-5").count - before5
        B08UI.shot(fav, "BUILD-BUG-03-favoriten-grauer-plus")
        B08QA.log("BUG-03|Favoriten-Tab|Klick auf grauen ⊞|titel \(titleBefore) → \(fav.title)|neue AVPlayer=\(B08Registry.liveAVPlayers.count - avBefore)|anfragen Fav 5=\(req5)|slots=\(app.slots.count)")
        XCTAssertEqual(fav.title, titleBefore, "kein Player")
        XCTAssertEqual(req5, 0, "keine fünfte Verbindung")
        XCTAssertEqual(B08Registry.liveAVPlayers.count, avBefore, "kein neuer Player")
        XCTAssertEqual(app.slots.count, 4)
    }

    // MARK: BUG-06 · Verständliche Meldung, wenn der Anbieter eine weitere Verbindung ablehnt

    func testBUG06_AnbieterlimitHinweisInDenAbgelehntenKacheln() async throws {
        let (w, app) = try await resetAppSession()
        w.setFrame(NSRect(x: 320, y: 165, width: 1280, height: 720), display: true)
        // Ohne laufenden Stream desselben Anbieters: kein Hinweis (die Kachel scheitert aus anderem Grund)
        add(app, channel("Allein 404", "/404/bug06-allein.ts"))
        _ = await B08QA.wait(8) { if case .failed = app.slots[0].engine.state { return true } else { return false } }
        await B08QA.spin(0.5)
        XCTAssertFalse(B08UI.labels(w).contains(MultiviewTile.connectionLimitHint), "kein Hinweis ohne laufenden Stream des Anbieters")
        await safeClear(app)
        _ = await B08QA.wait(5) { self.server.openStreamConnections(containing: "/live/").isEmpty }
        // Abo mit einer Verbindung: vier Xtream-Sender (MPEG-TS)
        let x = try await importXtream(container.mainContext, output: .mpegts, name: "QA Limit")
        server.configure(connectionLimit: 1)
        for c in x.channels.sorted(by: { $0.name < $1.name }) { add(app, c) }
        app.layout = .grid
        _ = await B08QA.wait(12) {
            app.slots.first?.engine.state == .playing && app.slots.dropFirst().allSatisfy { if case .failed = $0.engine.state { return true } else { return false } }
        }
        await B08QA.spin(1)
        let labels = B08UI.labels(w)
        let hints = labels.filter { $0 == MultiviewTile.connectionLimitHint }.count
        B08UI.shot(w, "BUILD-BUG-06-anbieterlimit-hinweis")
        B08QA.log("BUG-06|limit 1|\(B08Engine.describe(app))|hinweise=\(hints)|labels=\(labels.filter { !$0.contains("Volume") && !$0.contains("Mute") })")
        XCTAssertEqual(app.slots.first?.engine.state, .playing)
        XCTAssertEqual(hints, 3, "die drei abgelehnten Kacheln erklären das Verbindungslimit")
        XCTAssertEqual(labels.filter { $0.contains("fehlgeschlagen") }.count, 3)
        for l in labels { XCTAssertFalse(l.contains(B08QA.pass) || l.contains(B08QA.user) || l.contains("127.0.0.1"), "keine Adresse/Zugangsdaten: \(l)") }
        app.layout = .focus
    }

    // MARK: BUG-07 · HLS-Kachel, deren Segmente ausbleiben, meldet sich nach der Standardfrist (30 s); gesunde spielt weiter

    func testBUG07_HLSOhneSegmenteMeldetSichNachDerFrist() async throws {
        XCTAssertEqual(MultiviewSession.stallLimitForNewTiles, 30, "Standardfrist")
        let s = session()
        add(s, channel("Segmente 404 HLS", "/seg404/6/bug07seg/index.m3u8"))
        add(s, channel("Gesund HLS", "/livehls/bug07ok/index.m3u8"))
        let t0 = Date()
        var failedAt: TimeInterval?
        var lastTime = -1.0, stuckSince: TimeInterval?
        while Date().timeIntervalSince(t0) < 55 {
            await B08QA.spin(0.5)
            let t = Date().timeIntervalSince(t0)
            let playTime = B08Engine.avPlayer(s.slots[0].engine)?.currentItem?.currentTime().seconds ?? lastTime
            if playTime != lastTime { lastTime = playTime; stuckSince = nil } else if stuckSince == nil { stuckSince = t }
            if failedAt == nil, case .failed = s.slots[0].engine.state { failedAt = t; break }
        }
        let requestsAtFail = server.requests(containing: "bug07seg").count
        await B08QA.spin(4)
        let requestsLater = server.requests(containing: "bug07seg").count - requestsAtFail
        let seg404 = server.requests(containing: "bug07seg").filter { $0.status == 404 }.count
        B08QA.log("BUG-07|HLS Segmente 404 ab 6 s|meldung nach \(failedAt.map(B08QA.f1) ?? "-") s|stillstand ab \(stuckSince.map(B08QA.f1) ?? "-") s|\(B08Engine.describe(s))|404=\(seg404)|anfragen in 4 s nach der Meldung=\(requestsLater)")
        XCTAssertEqual(s.slots[0].engine.state, .failed(AVKitPlaybackEngine.interruptedMessage), "Kachel meldet sich statt Standbild")
        if let failedAt, let stuckSince {
            XCTAssertGreaterThanOrEqual(failedAt - stuckSince, 28, "nicht vor der Frist")
            XCTAssertLessThanOrEqual(failedAt - stuckSince, 34, "kurz nach der Frist")
        }
        XCTAssertEqual(requestsLater, 0, "nach der Meldung kein Nachladen mehr")
        XCTAssertEqual(s.slots[1].engine.state, .playing, "die gesunde HLS-Kachel spielt weiter (kein Fehlalarm)")
        // Der Player (B06) bekommt keine eigene Frist: `stallLimit` nur für Kacheln
        XCTAssertNil(B08Engine.child(AVKitPlaybackEngine(), "stallLimit") as? TimeInterval, "Player ohne eigene Frist")
        s.clear()
    }

    // MARK: BUG-10 · Mindestgröße: alle Kacheln, X und Umschalter bleiben im Fenster

    func testBUG10_KleinstesFensterZeigtAlleKacheln() async throws {
        let (w, app) = try await resetAppSession()
        for i in 1...4 { add(app, channel("Klein \(i)", "/hang/bug10-\(i).ts")) }
        await B08QA.spin(1)
        w.setFrame(w.constrainFrameRect(NSRect(x: 320, y: 300, width: max(w.minSize.width, 1), height: max(w.minSize.height, 1)), to: w.screen), display: true)
        await B08QA.spin(1.5)
        let content = contentRect(w)
        let xs = closeButtons(w).map(B08UI.frame).sorted { $0.midX > $1.midX }
        let tiles = xs.dropFirst().map { tileRect(fromX: $0, size: MultiviewMetrics.smallTileSize) }
        let lowest = tiles.map(\.minY).min() ?? 0
        B08UI.shot(w, "BUILD-BUG-10-kleinstes-fenster")
        B08QA.log("BUG-10|minSize=\(w.minSize)|contentMinSize=\(w.contentMinSize)|fenster \(Int(w.frame.width))x\(Int(w.frame.height))|inhalt \(Int(content.width))x\(Int(content.height))|unterste kleine Kachel \(Int(lowest - content.minY)) pt über dem Boden|umschalter=\(pickerState(w))")
        XCTAssertEqual(xs.count, 4)
        XCTAssertGreaterThanOrEqual(content.width, MultiviewScreen.minimumContentSize.width - 1)
        XCTAssertGreaterThanOrEqual(content.height, MultiviewScreen.minimumContentSize.height - 1)
        XCTAssertGreaterThanOrEqual(lowest, content.minY + MultiviewMetrics.smallTileTrailingInset - 1.5, "unterste kleine Kachel mit Rand im Fenster")
        for x in xs { XCTAssertTrue(content.insetBy(dx: -1, dy: -1).contains(x), "X im Fenster: \(x)") }
        XCTAssertNotNil(picker(w), "Umschalter in der Titelleiste")
        w.setFrame(NSRect(x: 320, y: 165, width: 1280, height: 720), display: true)
    }
}
