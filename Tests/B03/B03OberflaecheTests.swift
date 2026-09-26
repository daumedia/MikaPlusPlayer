import XCTest
import SwiftUI
import SwiftData
import AppKit
@testable import MikaPlusPlayer

/// B03 · Playlist-Verwaltung — Oberfläche im echten Fenster des macOS-Test-Hosts (QA Durchlauf 1, 2026-09-16).
/// Bedienung über synthetische Mausereignisse (Links-/Rechtsklick) und `NSMenu`, Zustand über AppKit-Accessibility,
/// Fensteraufnahmen nach `features/B03-playlist-verwaltung/qa/`. Keine Tastaturereignisse. Tonlos: Streams antworten
/// nie oder mit 404, die Multiview-Engine wird sofort stummgeschaltet.
final class B03OberflaecheTests: B03QATestCase {

    private var windows: [NSWindow] = []
    private var keep: [Any] = []

    override func tearDown() {
        MainActor.assumeIsolated {
            B03UI.closeStrayWindows()
            for w in windows {
                w.attachedSheet?.close()
                w.close()
            }
            windows = []
            keep = []
        }
        super.tearDown()
    }

    @MainActor private func overview(_ container: ModelContainer, size: CGSize = CGSize(width: 760, height: 560),
                                     origin: CGPoint = CGPoint(x: 80, y: 80)) async -> NSWindow {
        let w = B03UI.window(NavigationStack { PlaylistsView() }.environment(MultiviewSession()).modelContainer(container),
                             size: size, origin: origin)
        windows.append(w)
        await B03UI.spin(1.0)
        B03UI.wake(w)
        return w
    }

    @MainActor private func has(_ w: NSWindow, _ text: String) -> Bool {
        B03UI.labels(w).contains { $0.contains(text) }
    }

    // MARK: - AK-01 / AK-02

    @MainActor func testAK01_AK02_KopfzeileLeerzustandUndImportSheet() async throws {
        let (container, _) = try fileContainer("ak01")
        let w = await overview(container)
        let labels = B03UI.labels(w)
        B03QA.log("AK-01|fenstertitel=\(w.title)|texte=\(labels)")
        B03UI.shot(w, "AK-01-02-leerzustand")
        XCTAssertEqual(w.title, "Playlists")
        for t in ["MIKA+PLAYER · PLAYLISTS", "Playlists", "Keine Playlists",
                  "Importiere eine M3U/M3U8-Playlist per URL oder Datei, um loszulegen.", "Playlist importieren"] {
            XCTAssertTrue(labels.contains { $0.contains(t) }, t)
        }
        let plus = B03UI.element(w, "Add", role: "AXButton")
        XCTAssertNotNil(plus, "„+“-Button (AX „Add“)")

        let importButton = try XCTUnwrap(B03UI.element(w, "Playlist importieren", role: "AXButton"))
        B03UI.click(importButton, in: w)
        let sheet = try await waitFor("Sheet über „Playlist importieren“") { w.attachedSheet }
        await B03UI.spin(0.3)
        let sheetLabels = B03UI.labels(sheet)
        B03QA.log("AK-02|sheetNachButton=\(sheetLabels.prefix(6))")
        XCTAssertTrue(sheetLabels.contains { $0.contains("Playlist importieren") })
        B03UI.click(try XCTUnwrap(B03UI.element(sheet, "Abbrechen", role: "AXButton")), in: sheet)
        _ = try await waitFor("Sheet zu") { w.attachedSheet == nil ? true : nil }
        B03UI.click(try XCTUnwrap(B03UI.element(w, "Add", role: "AXButton")), in: w)
        let sheet2 = try await waitFor("Sheet über „+“") { w.attachedSheet }
        await B03UI.spin(0.3)
        XCTAssertTrue(B03UI.labels(sheet2).contains { $0.contains("Playlist importieren") })
        B03UI.click(try XCTUnwrap(B03UI.element(sheet2, "Abbrechen", role: "AXButton")), in: sheet2)
        _ = try await waitFor("Sheet zu") { w.attachedSheet == nil ? true : nil }
    }

    // MARK: - AK-03 / AK-05 / EC-10

    @MainActor func testAK03_AK05_EC10_KartenReihenfolgeSymboleUndTexte() async throws {
        let (container, url) = try fileContainer("ak03")
        let ctx = container.mainContext
        let longName = "QA Sehr langer Name " + String(repeating: "Überlänge ", count: 30)
        let longM3U = try await importM3U(ctx, name: longName)
        try await Task.sleep(nanoseconds: 30_000_000)
        let file = url.deletingLastPathComponent().appendingPathComponent("QA Datei.m3u")
        try B03QA.m3u(B03QA.v1).write(to: file)
        _ = try await PlaylistImporter(modelContext: ctx).importFromFile(file)
        try await Task.sleep(nanoseconds: 30_000_000)
        _ = try await importM3U(ctx, name: "QA Adresse")
        try await Task.sleep(nanoseconds: 30_000_000)
        let x = try await importXtream(ctx, pass: "qa-pass-b03-ak03", name: "QA Zugang")
        try await refresh(x, ctx)   // lastRefreshed gesetzt
        _ = longM3U
        let w = await overview(container, size: CGSize(width: 760, height: 640))
        await B03UI.spin(0.5)
        B03UI.shot(w, "AK-03-vier-playlists")
        guard let content = w.contentView else { return XCTFail("kein Inhalt") }
        B03UI.wake(w)
        let elements = B03UI.all(content)
        let described = elements.map { "\(B03UI.role($0)):\(B03UI.label($0).prefix(60))" }.filter { !$0.hasSuffix(":") }
        B03QA.log("AK-03|elemente=\(described)")

        func top(_ text: String) -> CGFloat? {
            elements.first { B03UI.label($0).hasPrefix(text) }.map { B03UI.frame($0).maxY }
        }
        let tops = ["QA Zugang", "QA Adresse", "QA Datei", "QA Sehr langer"].map { top($0) }
        B03QA.log("AK-03|obereKanten=\(tops)")
        let ys = tops.compactMap { $0 }
        XCTAssertEqual(ys.count, 4, "alle vier Karten gefunden")
        XCTAssertEqual(ys, ys.sorted(by: >), "neueste zuerst (Bildschirmkoordinaten: oben = größeres y)")

        // Karten-Texte
        let cards = elements.map(B03UI.label).filter { $0.contains(" Sender") }
        B03QA.log("AK-05|kartentexte=\(cards.map { $0.count > 80 ? String($0.prefix(40)) + "…" : $0 })")
        XCTAssertTrue(cards.contains { $0.contains("QA Zugang") && $0.contains("4 Sender") })
        XCTAssertTrue(cards.contains { $0.contains("QA Adresse") && $0.contains("7 Sender") })
        XCTAssertTrue(cards.contains { $0.contains("QA Datei") && $0.contains("7 Sender") })
        let all = B03UI.labels(w).joined(separator: "\n")
        for forbidden in ["127.0.0.1", "qa-user", "player_api", "list.m3u", "HLS", "MPEG", "Xtream", "M3U", "2026", "Aktualisiert", "zuletzt"] {
            XCTAssertFalse(all.contains(forbidden), "AK-05: Übersicht zeigt kein „\(forbidden)“")
        }
        // Symbole (Globus/Dokument), Einzeiligkeit und Kürzung: Die Karten legen Bilder nicht in die Accessibility,
        // Beleg ist die Fensteraufnahme AK-03-vier-playlists.png. EC-10 zusätzlich über die Kartenhöhen.
        let cardFrames = elements.filter { B03UI.role($0) == "AXButton" && B03UI.label($0).contains(" Sender") }
            .map { (String(B03UI.label($0).prefix(14)), B03UI.frame($0).height) }
        B03QA.log("EC-10|kartenhoehen=\(cardFrames)")
        let heights = cardFrames.map(\.1)
        XCTAssertEqual(heights.count, 4)
        if let minH = heights.min(), let maxH = heights.max() {
            XCTAssertEqual(maxH, minH, accuracy: 0.5, "Karte mit langem Namen so hoch wie die anderen (einzeilig)")
        }
        XCTAssertTrue(cards.contains { $0.hasPrefix(longName) }, "voller Name in der Accessibility, Kürzung nur in der Darstellung")
    }

    // MARK: - AK-04

    @MainActor func testAK04_KarteOeffnetSenderliste() async throws {
        let (container, _) = try fileContainer("ak04")
        _ = try await importM3U(container.mainContext, name: "QA Öffnen")
        let w = await overview(container)
        let card = try XCTUnwrap(B03UI.element(w, "QA Öffnen"))
        B03UI.click(card, in: w)
        _ = try await waitFor("Senderliste") { self.has(w, "MIKA+PLAYER · 7 SENDER") ? true : nil }
        await B03UI.spin(0.5)
        B03QA.log("AK-04|fenstertitel=\(w.title)|texte=\(B03UI.labels(w).prefix(12))")
        B03UI.shot(w, "AK-04-senderliste")
        XCTAssertEqual(w.title, "QA Öffnen")
        XCTAssertTrue(has(w, "Alpha"))
        XCTAssertEqual(windows.count, 1, "im selben Fenster")
    }

    // MARK: - AK-06

    @MainActor private func destructive(_ item: NSMenuItem) -> Bool? {
        let sel = NSSelectorFromString("isDestructive")
        guard item.responds(to: sel), let imp = item.method(for: sel) else { return nil }
        typealias F = @convention(c) (AnyObject, Selector) -> Bool
        return unsafeBitCast(imp, to: F.self)(item, sel)
    }

    @MainActor func testAK06_KontextmenueEintraegeUndKeineAnderenWege() async throws {
        let (container, url) = try fileContainer("ak06")
        let ctx = container.mainContext
        let file = url.deletingLastPathComponent().appendingPathComponent("QA Lokal.m3u")
        try B03QA.m3u(B03QA.v1).write(to: file)
        _ = try await PlaylistImporter(modelContext: ctx).importFromFile(file)
        _ = try await importM3U(ctx, name: "QA Entfernt")
        _ = try await importXtream(ctx, name: "QA Panel")
        let w = await overview(container)
        let local = await B03UI.contextMenu(w, row: "QA Lokal")
        let remote = await B03UI.contextMenu(w, row: "QA Entfernt")
        let xtream = await B03UI.contextMenu(w, row: "QA Panel")
        func describe(_ box: B03MenuBox) -> [String] {
            box.items.map { item in
                var color = "-"
                if let at = item.attributedTitle, at.length > 0,
                   let c = at.attribute(.foregroundColor, at: 0, effectiveRange: nil) as? NSColor {
                    color = c.usingColorSpace(.sRGB).map { String(format: "r%.2f g%.2f b%.2f", $0.redComponent, $0.greenComponent, $0.blueComponent) } ?? "\(c)"
                }
                return "\(item.title)[enabled=\(item.isEnabled) destruktiv=\(destructive(item).map(String.init) ?? "-") farbe=\(color) bild=\(item.image != nil)]"
            }
        }
        B03QA.log("AK-06|lokal=\(describe(local))|m3u=\(describe(remote))|xtream=\(describe(xtream))")
        XCTAssertEqual(local.titles, ["Löschen"])
        XCTAssertEqual(remote.titles, ["Aktualisieren", "Löschen"])
        XCTAssertEqual(xtream.titles, ["Aktualisieren", "Löschen"])
        // Destruktive Kennzeichnung (`NSMenuItem.isDestructive`, macOS 26); das Menü erscheint im Test-Host nicht als
        // aufnehmbares Fenster
        func imageInfo(_ item: NSMenuItem) -> String {
            guard let img = item.image else { return "kein Bild" }
            var rect = NSRect(origin: .zero, size: img.size)
            guard let cg = img.cgImage(forProposedRect: &rect, context: nil, hints: nil) else { return "template=\(img.isTemplate)" }
            let rep = NSBitmapImageRep(cgImage: cg)
            var r = 0.0, g = 0.0, b = 0.0, n = 0.0
            for x in 0..<rep.pixelsWide { for y in 0..<rep.pixelsHigh {
                if let c = rep.colorAt(x: x, y: y)?.usingColorSpace(.sRGB), c.alphaComponent > 0.5 { r += c.redComponent; g += c.greenComponent; b += c.blueComponent; n += 1 }
            } }
            return "template=\(img.isTemplate) mittel=r\(String(format: "%.2f", r / max(n, 1))) g\(String(format: "%.2f", g / max(n, 1))) b\(String(format: "%.2f", b / max(n, 1)))"
        }
        let marking = remote.items.map { "\($0.title): isDestructive=\(destructive($0).map(String.init) ?? "-") bild=\(imageInfo($0))" }
        B03QA.log("AK-06|kennzeichnung=\(marking)")

        // Keine anderen Wege: Hauptmenü, Bearbeiten › Löschen (delete:) an das Fenster
        func titles(_ menu: NSMenu?, _ prefix: String = "") -> [String] {
            guard let menu else { return [] }
            return menu.items.flatMap { [prefix + $0.title] + titles($0.submenu, prefix + $0.title + " › ") }
        }
        let main = titles(NSApp.mainMenu)
        let refreshItems = main.filter { $0.localizedCaseInsensitiveContains("aktualis") || $0.localizedCaseInsensitiveContains("refresh") || $0.localizedCaseInsensitiveContains("reload") }
        w.makeKeyAndOrderFront(nil)
        let handledDelete = NSApp.sendAction(#selector(NSText.delete(_:)), to: nil, from: w)
        await B03UI.spin(0.5)
        let count = try ctx.fetchCount(FetchDescriptor<Playlist>())
        B03QA.log("AK-06|hauptmenue=\(main)|aktualisierenImMenue=\(refreshItems)|delete:behandelt=\(handledDelete)|playlists=\(count)")
        XCTAssertEqual(refreshItems, [])
        XCTAssertEqual(count, 3, "Bearbeiten › Löschen entfernt keine Playlist")
    }

    // MARK: - AK-12 / AK-13 ⚠ / EC-09

    @MainActor func testAK12_AK13_EC09_LadeindikatorBeiEinerUndZweiAktualisierungen() async throws {
        let (container, _) = try fileContainer("ak12")
        let ctx = container.mainContext
        let m = try await importM3U(ctx, name: "QA Eins")
        let x = try await importXtream(ctx, pass: "qa-pass-b03-ak12", name: "QA Zwei")
        let a = await overview(container, size: CGSize(width: 700, height: 420), origin: CGPoint(x: 60, y: 420))
        let b = await overview(container, size: CGSize(width: 700, height: 420), origin: CGPoint(x: 800, y: 420))
        let m0 = m.lastRefreshed, x0 = x.lastRefreshed
        var cfg = B03QAPanel()
        cfg.m3u = B03QA.m3u(B03QA.v1 + [("Delta", nil, nil, "\(B03QA.dead)/d.m3u8"), ("Epsilon", nil, nil, "\(B03QA.dead)/e.m3u8")])
        cfg.m3uDelay = 25
        cfg.streamsDelay = 50
        mock.handler = cfg.handler()

        XCTAssertEqual(B03UI.busyCount(a), 0)
        let tStart = Date()
        await B03UI.contextMenu(a, row: "QA Eins", perform: "Aktualisieren")
        await B03UI.spin(0.8)
        let oneA = B03UI.busyCount(a), oneB = B03UI.busyCount(b)
        B03UI.shot(a, "AK-12-ladeindikator-eine-karte")
        // Bedienbarkeit während des Wartens auf den Anbieter: Main-Thread-Lücke über 2 s ohne eigene Eingriffe,
        // danach Kontextmenü einer anderen Karte
        let wd = B03QAWatchdog(); wd.start()
        await B03UI.spin(2.0)
        let gapWhileWaiting = wd.stop()
        let menuWhileWaiting = await B03UI.contextMenu(a, row: "QA Zwei")
        B03QA.log("AK-12|laufend|seitStart=\(B03QA.f2(Date().timeIntervalSince(tStart)))s|indikatorA=\(oneA)|indikatorB=\(oneB)|menueAndereKarte=\(menuWhileWaiting.titles)|mainThreadLuecke=\(B03QA.f2(gapWhileWaiting))s|alert=\(a.attachedSheet != nil)")
        XCTAssertEqual(oneA, 1, "AK-12: Indikator in der Karte")
        XCTAssertEqual(oneB, 0, "EC-09: anderes Fenster ohne Indikator")
        XCTAssertEqual(menuWhileWaiting.titles, ["Aktualisieren", "Löschen"], "Übersicht bleibt bedienbar")
        XCTAssertLessThan(gapWhileWaiting, 0.5)
        XCTAssertEqual(m.lastRefreshed, m0, "M3U läuft noch")

        await B03UI.contextMenu(a, row: "QA Zwei", perform: "Aktualisieren")
        await B03UI.spin(0.8)
        let both = B03UI.busyCount(a)
        let bothRunning = m.lastRefreshed == m0 && x.lastRefreshed == x0
        B03UI.shot(a, "AK-13-zwei-laufen-ein-indikator")
        B03QA.log("AK-13|beideGestartet|seitStart=\(B03QA.f2(Date().timeIntervalSince(tStart)))s|beideLaufen=\(bothRunning)|indikator=\(both)")
        XCTAssertTrue(bothRunning, "Messpunkt liegt, während beide laufen")
        _ = try await waitFor("M3U fertig", timeout: 40) { m.lastRefreshed != m0 ? true : nil }
        await B03UI.spin(0.6)
        let afterFirst = B03UI.busyCount(a)
        let xStillRunning = x.lastRefreshed == x0
        B03UI.shot(a, "AK-13-m3u-fertig-xtream-laeuft-kein-indikator")
        let countB = B03UI.labels(b).filter { $0.contains("QA Eins") }
        B03QA.log("AK-13|beideLaufen=\(both)|m3uFertig=\(afterFirst)|xtreamLaeuftNoch=\(xStillRunning)|fensterB=\(countB)")
        _ = try await waitFor("Xtream fertig", timeout: 70) { x.lastRefreshed != x0 ? true : nil }
        await B03UI.spin(0.6)
        let done = B03UI.busyCount(a)
        let labelsA = B03UI.labels(a)
        B03QA.log("AK-12|fertig|indikator=\(done)|alert=\(a.attachedSheet != nil)|texte=\(labelsA.filter { $0.contains("Sender") })")
        XCTAssertEqual(both, 1, "Ist: nur die zuletzt gestartete Karte")
        XCTAssertTrue(xStillRunning)
        XCTAssertEqual(afterFirst, 0, "Ist: Indikator weg, obwohl Xtream noch läuft")
        XCTAssertEqual(done, 0)
        XCTAssertNil(a.attachedSheet, "keine Erfolgsmeldung")
        XCTAssertTrue(labelsA.contains { $0.contains("9 Sender") }, "neue Anzahl in der Karte")
        XCTAssertTrue(countB.contains { $0.contains("9 Sender") }, "EC-09: Fenster B zeigt die neue Anzahl")
        XCTExpectFailure("BUG-03 · Ladeindikator nur für eine Playlist (FB-03)") {
            XCTAssertEqual(both, 2, "beide laufenden Aktualisierungen zeigen einen Indikator")
            XCTAssertEqual(afterFirst, 1, "die noch laufende zeigt ihn weiter")
        }
    }

    // MARK: - AK-14 ⚠ / Angriff 3

    @MainActor func testAK14_Angriff3_AktualisierenBleibtWaehrendDesLaufsWaehlbar() async throws {
        let (container, url) = try fileContainer("ak14ui")
        let ctx = container.mainContext
        let m = try await importM3U(ctx, name: "QA Mehrfach")
        m.channels.first { $0.name == "Alpha" }?.isFavorite = true
        let x = try await importXtream(ctx, pass: "qa-pass-b03-ak14", name: "QA Zehnmal")
        try ctx.save()
        let w = await overview(container)
        var cfg = B03QAPanel(); cfg.m3u = B03QA.m3u(B03QA.v1); cfg.m3uDelay = 15; cfg.streamsDelay = 2
        mock.handler = cfg.handler()
        mock.resetLog()
        var enabledWhileRunning: [Bool] = []
        var deleteEnabledWhileRunning: [Bool] = []
        for _ in 0..<3 {
            let box = await B03UI.contextMenu(w, row: "QA Mehrfach", perform: "Aktualisieren")
            enabledWhileRunning.append(box.items.first { $0.title == "Aktualisieren" }?.isEnabled ?? false)
            deleteEnabledWhileRunning.append(box.items.first { $0.title == "Löschen" }?.isEnabled ?? false)
        }
        XCTAssertEqual(deleteEnabledWhileRunning, [true, true, true], "EC-07: „Löschen“ während des Laufs wählbar")
        let m0 = Date()
        let overlapping = mock.requests.filter { $0.path.hasSuffix(".m3u") }.count
        _ = try await waitFor("drei Abrufe fertig", timeout: 40) {
            (Date().timeIntervalSince(m0) > 3 && B03UI.busyCount(w) == 0) ? true : nil
        }
        B03QA.log("AK-14|abrufeWaehrendErsterNochLief=\(overlapping)|keinerFertigBeimDrittenMenue=\(m.lastRefreshed.map { $0 < m0 } ?? true)")
        let m3uFetches = mock.requests.filter { $0.path.hasSuffix(".m3u") }.count
        let m3uRows = B03QA.int(url.path, "select count(*) from ZCHANNEL c join ZPLAYLIST p on c.ZPLAYLIST = p.Z_PK where p.ZNAME = 'QA Mehrfach'")
        mock.resetLog()
        let t0 = Date()
        for _ in 0..<10 { await B03UI.contextMenu(w, row: "QA Zehnmal", perform: "Aktualisieren") }
        let menuTime = Date().timeIntervalSince(t0)
        _ = try await waitFor("zehn Abrufe fertig", timeout: 40) { mock.requests.filter { $0.action == "get_live_streams" }.count >= 10 ? true : nil }
        await B03UI.spin(1.0)
        let xtreamRequests = mock.requests.filter { $0.path == "/player_api.php" }
        let withPassword = xtreamRequests.filter { $0.password == "qa-pass-b03-ak14" }.count
        B03QA.log("AK-14|m3u 3× gewählt: eintragAktiv=\(enabledWhileRunning)|abrufe=\(m3uFetches)|zeilen=\(m3uRows)|favoriten=\(favorites(m))|xtream 10× in \(B03QA.f2(menuTime))s: anfragen=\(xtreamRequests.count) mitPasswort=\(withPassword)|sender=\(x.channelCount)|alert=\(w.attachedSheet != nil)")
        XCTAssertEqual(enabledWhileRunning, [true, true, true], "Ist: Eintrag bleibt wählbar")
        XCTAssertEqual(m3uFetches, 3)
        XCTAssertEqual(m3uRows, 7, "Ergebnis richtig: keine doppelten Sender")
        XCTAssertEqual(favorites(m), ["Alpha"])
        XCTAssertEqual(withPassword, 30, "Angriff 3: zehnmal Zugangsdaten an den Anbieter, ungebremst")
        XCTExpectFailure("BUG-04 · Keine Sperre gegen mehrfaches Aktualisieren derselben Playlist (FB-04)") {
            XCTAssertEqual(Array(enabledWhileRunning.dropFirst()), [false, false], "Eintrag während des Laufs gesperrt")
            XCTAssertEqual(m3uFetches, 1)
            XCTAssertEqual(withPassword, 3)
        }
    }

    // MARK: - AK-18 / EC-04

    @MainActor func testAK18_EC04_FehlerAlertUndZweiFehlerKurzNacheinander() async throws {
        let (container, _) = try fileContainer("ak18ui")
        let ctx = container.mainContext
        let m = try await importM3U(ctx, name: "QA Fehler")
        let other = try await importM3U(ctx, name: "QA Anderer")
        _ = other
        let ids = Set(m.channels.map(\.id))
        let w = await overview(container)
        mock.handler = B03QAPanel().handler()   // 404
        await B03UI.contextMenu(w, row: "QA Fehler", perform: "Aktualisieren")
        let alert = try await waitFor("Alert", timeout: 8) { w.attachedSheet }
        await B03UI.spin(0.4)
        let texts = B03UI.sheetTexts(alert)
        B03UI.shot(w, "AK-18-fehler-alert")
        B03QA.log("AK-18|alert=\(texts)")
        XCTAssertTrue(texts.contains("Fehler"))
        XCTAssertTrue(texts.contains("Netzwerkfehler: HTTP 404"))
        XCTAssertTrue(texts.contains("OK"))
        XCTAssertTrue(B03UI.pressButton(alert, "OK"))
        _ = try await waitFor("Alert zu") { w.attachedSheet == nil ? true : nil }
        XCTAssertEqual(Set(m.channels.map(\.id)), ids, "alte Liste bleibt")
        XCTAssertTrue(has(w, "7 Sender"))

        // EC-04: zwei Fehler kurz nacheinander (404 nach 0,5 s, 500 nach 1,5 s)
        let counter = B03QACounter()
        mock.handler = { req in
            guard req.path.hasSuffix(".m3u") else { return .raw(status: 404, contentType: "text/plain", body: Data()) }
            return counter.next() == 1 ? .delayed(9, .raw(status: 404, contentType: "text/plain", body: Data()))
                                       : .delayed(8, .raw(status: 500, contentType: "text/plain", body: Data()))
        }
        await B03UI.contextMenu(w, row: "QA Fehler", perform: "Aktualisieren")
        await B03UI.contextMenu(w, row: "QA Anderer", perform: "Aktualisieren")
        _ = try await waitFor("erster Alert", timeout: 20) { w.attachedSheet }
        await B03UI.spin(6.0)
        let second = B03UI.sheetTexts(w.attachedSheet)
        let sheets = NSApp.windows.filter { $0.isVisible && $0.sheetParent == w }.count
        B03UI.shot(w, "EC-04-zwei-fehler")
        _ = B03UI.pressButton(w.attachedSheet, "OK")
        await B03UI.spin(1.0)
        let afterOK = w.attachedSheet != nil
        B03QA.log("EC-04|alertTexte=\(second)|sichtbareSheets=\(sheets)|nachOKweitererAlert=\(afterOK)")
        XCTAssertEqual(sheets, 1, "nur eine Fehlermeldung")
        XCTAssertTrue(second.contains("Netzwerkfehler: HTTP 500"), "die spätere ersetzt die frühere")
        XCTAssertFalse(afterOK)
    }

    // MARK: - AK-22 ⚠ / AK-24 über das Menü

    @MainActor func testAK22_AK24_LoeschenUeberMenueSofortOhneRueckfrageOhneRueckgaengig() async throws {
        let (container, url) = try fileContainer("ak22ui")
        let ctx = container.mainContext
        let x = try await importXtream(ctx, pass: "qa-pass-b03-ak22", name: "QA Weg")
        for ch in x.channels.prefix(2) { ch.isFavorite = true }
        try ctx.save()
        let xid = x.id
        let w = await overview(container)
        B03UI.shot(w, "AK-22-vor-loeschen")
        let windowsBefore = NSApp.windows.filter(\.isVisible).count
        await B03UI.contextMenu(w, row: "QA Weg", perform: "Löschen")
        let immediately = B03QA.dbSummary(url)
        let sheet = w.attachedSheet
        let windowsAfter = NSApp.windows.filter(\.isVisible).count
        let secret = try XtreamCredentialStore.standard.load(for: xid)
        await B03UI.spin(0.8)
        B03UI.shot(w, "AK-22-nach-loeschen")
        w.makeKeyAndOrderFront(nil)
        let undoHandled = NSApp.sendAction(Selector(("undo:")), to: nil, from: w)
        await B03UI.spin(0.5)
        let afterUndo = B03QA.dbSummary(url)
        B03QA.log("AK-22|sofort=\(immediately)|sheet=\(sheet != nil)|fenster vorher/nachher=\(windowsBefore)/\(windowsAfter)|texte=\(B03UI.labels(w).prefix(6))|undo:behandelt=\(undoHandled)|nachUndo=\(afterUndo)|undoManager=\(String(describing: ctx.undoManager))|AK-24 schluesselbund=\(secret != nil)")
        XCTAssertEqual(immediately, "ZPLAYLIST=0|ZCHANNEL=0|ohnePlaylist=0|favoriten=0", "sofort aus der Datenbank")
        XCTAssertNil(sheet, "keine Rückfrage")
        XCTAssertEqual(windowsAfter, windowsBefore)
        XCTAssertTrue(has(w, "Keine Playlists"))
        XCTAssertFalse(undoHandled, "⌘Z (undo:) behandelt niemand")
        XCTAssertEqual(afterUndo, immediately)
        XCTAssertNil(secret, "AK-24 über das Kontextmenü")
        XCTExpectFailure("BUG-10 · Löschen ohne Rückfrage und ohne Rückgängig (OF-01)") {
            XCTAssertTrue(sheet != nil || undoHandled, "Rückfrage oder Rückgängig")
        }
    }

    // MARK: - AK-27 ⚠ / EC-05

    @MainActor func testAK27_EC05_OffeneSenderlisteBeimAktualisierenUndLoeschen() async throws {
        let (container, _) = try fileContainer("ak27")
        let ctx = container.mainContext
        let m = try await importM3U(ctx, name: "QA Offen")
        let w = B03UI.window(NavigationStack { ChannelListView(playlist: m) }.environment(MultiviewSession()).modelContainer(container),
                             size: CGSize(width: 760, height: 560))
        windows.append(w)
        await B03UI.spin(1.5)
        let before = B03UI.labels(w)
        B03UI.shot(w, "EC-05-senderliste-vorher")

        // EC-05: Aktualisieren mit neuer Gruppe „Neu“
        var cfg = B03QAPanel()
        cfg.m3u = B03QA.m3u(B03QA.v1 + [("Delta", nil, "Neu", "\(B03QA.dead)/d.m3u8"), ("Epsilon", nil, "Neu", "\(B03QA.dead)/e.m3u8")])
        mock.handler = cfg.handler()
        try await refresh(m, ctx)
        await B03UI.spin(1.5)
        let afterRefresh = B03UI.labels(w)
        B03UI.shot(w, "EC-05-senderliste-nach-aktualisieren")
        B03QA.log("EC-05|vorher=\(before.prefix(14))|nachher=\(afterRefresh.prefix(16))")
        XCTAssertTrue(afterRefresh.contains { $0.contains("MIKA+PLAYER · 9 SENDER") }, "Kopfzeile aktualisiert")
        XCTAssertTrue(afterRefresh.contains { $0.contains("Delta") }, "Liste aktualisiert")
        XCTAssertFalse(afterRefresh.contains { $0 == "Neu" }, "Gruppen-Chips nicht aktualisiert (B04)")

        // AK-27: Löschen bei offener Liste
        try PlaylistImporter(modelContext: ctx).delete(m)
        await B03UI.spin(1.5)
        let afterDelete = B03UI.labels(w)
        B03UI.shot(w, "AK-27-senderliste-nach-loeschen")
        B03QA.log("AK-27|fenstertitel=\(w.title)|texte=\(afterDelete.prefix(16))")
        XCTAssertEqual(w.title, "QA Offen")
        XCTAssertTrue(afterDelete.contains { $0.contains("MIKA+PLAYER · 9 SENDER") }, "Ist: alte Senderzahl")
        XCTAssertTrue(afterDelete.contains { $0 == "News" || $0.contains("News") }, "Ist: Gruppen-Chips bleiben")
        XCTAssertTrue(afterDelete.contains { $0.contains("Keine Sender") })
        XCTAssertTrue(afterDelete.contains { $0.contains("Diese Playlist enthält keine Sender.") })
        XCTExpectFailure("BUG-05 · Offene Senderliste behauptet nach dem Löschen eine leere Playlist mit alter Senderzahl (FB-05)") {
            XCTAssertFalse(afterDelete.contains { $0.contains("9 SENDER") })
        }
    }

    // MARK: - AK-28 ⚠ · Player und Multiview nach Löschen

    @MainActor func testAK28_PlayerUndMultiviewLaufenNachDemLoeschenWeiter() async throws {
        let (container, _) = try fileContainer("ak28")
        let ctx = container.mainContext
        let pass = "qa-pass-b03-ak28"
        mock.handler = B03QAPanel().handler()   // /live/ antwortet nie → stumm
        let x = try await importXtream(ctx, pass: pass, output: .hls, name: "QA Läuft")
        mock.handler = B03QAPanel().handler()
        let playerChannel = try XCTUnwrap(x.channels.first { $0.name == "Kanal String" })
        let mvChannel = try XCTUnwrap(x.channels.first { $0.name == "Kanal Int" })

        // Player
        let pw = B03UI.window(NavigationStack { PlayerView(channel: playerChannel) }.modelContainer(container), size: CGSize(width: 640, height: 400))
        windows.append(pw)
        // Multiview (sofort stumm)
        let session = MultiviewSession()
        keep.append(session)
        session.add(mvChannel)
        let engine = try XCTUnwrap(session.slots.first?.engine)
        engine.setMuted(true)
        let mw = B03UI.window(MultiviewScreen().environment(session).modelContainer(container), size: CGSize(width: 640, height: 400),
                              origin: CGPoint(x: 760, y: 80))
        windows.append(mw)
        await B03UI.spin(2.5)
        let liveBefore = mock.requests.filter { $0.path.hasPrefix("/live/") }.map { $0.path.replacingOccurrences(of: pass, with: "<pass>") }
        let connBefore = B03QA.establishedConnections(toPort: mock.port)
        B03UI.shot(pw, "AK-28-player-vor-loeschen")
        B03UI.shot(mw, "AK-28-multiview-vor-loeschen")

        try PlaylistImporter(modelContext: ctx).delete(x)
        await B03UI.spin(2.5)
        let connAfter = B03QA.establishedConnections(toPort: mock.port)
        let playerTitle = pw.title
        let slots = session.slots.map { $0.channel.name }
        B03UI.shot(pw, "AK-28-player-nach-loeschen")
        B03UI.shot(mw, "AK-28-multiview-nach-loeschen")
        B03QA.log("AK-28|liveAnfragen=\(liveBefore)|verbindungen vorher/nachher=\(connBefore)/\(connAfter)|playerTitel=\(playerTitle)|multiviewSlots=\(slots)|engineZustand=\(engine.state)|pausiert=\(engine.isPaused)|db=\(try ctx.fetchCount(FetchDescriptor<Playlist>()))")
        XCTAssertTrue(liveBefore.contains("/live/qa-user/<pass>/102.m3u8"), "Player-Verbindung mit Zugangsdaten im Pfad")
        XCTAssertTrue(liveBefore.contains("/live/qa-user/<pass>/101.m3u8"), "Multiview-Verbindung mit Zugangsdaten im Pfad")
        XCTAssertGreaterThan(connBefore, 0)
        XCTAssertEqual(connAfter, connBefore, "Ist: Verbindungen bleiben nach dem Löschen offen")
        XCTAssertEqual(playerTitle, "Kanal String")
        XCTAssertEqual(slots, ["Kanal Int"])
        XCTAssertFalse(engine.isPaused)
        XCTExpectFailure("BUG-05 · Wiedergabe und Multiview laufen nach dem Löschen der Playlist mit Zugangsdaten weiter (FB-05)") {
            XCTAssertEqual(connAfter, 0)
            XCTAssertTrue(session.slots.isEmpty)
        }
        // Schließen beendet: Multiview-Fenster (Fokus-Layout) und Player
        mw.contentView = nil   // wie das Schließen der Szene: onDisappear der Ansicht
        pw.contentView = nil
        mw.close()
        pw.close()
        await B03UI.spin(2.0)
        B03QA.log("AK-28|nachSchliessen|slots=\(session.slots.count)|pausiert=\(engine.isPaused)|verbindungen=\(B03QA.establishedConnections(toPort: mock.port))")
        XCTAssertTrue(session.slots.isEmpty, "Schließen des Multiview-Fensters leert die Session")
        XCTAssertTrue(engine.isPaused)
    }

    // MARK: - AK-28 / AK-29 ⚠ · „Erneut versuchen“

    /// „Erneut versuchen“ im Player: nach dem Löschen (Xtream und M3U) und nach dem Aktualisieren (Xtream).
    /// Streams antworten mit 404 → Fehleransicht mit Knopf; kein Ton.
    @MainActor func testAK28_AK29_ErneutVersuchenNachLoeschenUndAktualisieren() async throws {
        let (container, _) = try fileContainer("ak29ui")
        let ctx = container.mainContext
        let pass = "qa-pass-b03-ak29ui"
        var cfg = B03QAPanel(); cfg.liveStatus = 404
        cfg.m3u = B03QA.m3u([("QA M3U Sender", nil, nil, "http://127.0.0.1:0/live/m3u-sender.m3u8")])
        mock.handler = cfg.handler()
        let x = try await PlaylistImporter(modelContext: ctx, loginThrottle: XtreamLoginThrottle()).importFromXtream(
            XtreamCredentials(host: mock.hostPort, username: "qa-user", password: pass), output: .hls, name: "QA Retry X")
        let m3uEntries: [B03QA.M3UEntry] = [("QA M3U Sender", nil, nil, "http://\(mock.hostPort)/live/m3u-sender.m3u8")]
        cfg.m3u = B03QA.m3u(m3uEntries)
        mock.handler = cfg.handler()
        let m = try await PlaylistImporter(modelContext: ctx).importFromURL(m3uAddress, name: "QA Retry M")
        let x2 = try await PlaylistImporter(modelContext: ctx, loginThrottle: XtreamLoginThrottle()).importFromXtream(
            XtreamCredentials(host: mock.hostPort, username: "qa-user", password: pass), output: .hls, name: "QA Retry X2")

        func player(_ ch: Channel, _ origin: CGPoint) async throws -> NSWindow {
            let w = B03UI.window(NavigationStack { PlayerView(channel: ch) }.modelContainer(container), size: CGSize(width: 560, height: 380), origin: origin)
            windows.append(w)
            _ = try await waitFor("Fehleransicht", timeout: 15) { B03UI.element(w, "Erneut versuchen", role: "AXButton") }
            return w
        }
        func liveRequests(_ id: String) -> [String] {
            mock.requests.filter { $0.path.hasPrefix("/live/") && $0.path.contains(id) }.map { $0.path.replacingOccurrences(of: pass, with: "<pass>") }
        }

        // (1) Xtream: löschen, dann „Erneut versuchen“
        let wx = try await player(try XCTUnwrap(x.channels.first { $0.name == "Kanal Int" }), CGPoint(x: 60, y: 80))
        let textsBefore = B03UI.labels(wx)
        try PlaylistImporter(modelContext: ctx).delete(x)
        let beforeRetryX = liveRequests("101").count
        B03UI.click(try XCTUnwrap(B03UI.element(wx, "Erneut versuchen", role: "AXButton")), in: wx)
        await B03UI.spin(2.0)
        let textsX = B03UI.labels(wx)
        B03UI.shot(wx, "AK-28-erneut-versuchen-xtream-nach-loeschen")
        let afterRetryX = liveRequests("101")

        // (2) M3U: löschen, dann „Erneut versuchen“
        let wm = try await player(try XCTUnwrap(m.channels.first), CGPoint(x: 640, y: 80))
        try PlaylistImporter(modelContext: ctx).delete(m)
        let beforeRetryM = liveRequests("m3u-sender").count
        B03UI.click(try XCTUnwrap(B03UI.element(wm, "Erneut versuchen", role: "AXButton")), in: wm)
        await B03UI.spin(2.0)
        let afterRetryM = liveRequests("m3u-sender").count

        // (3) Xtream: aktualisieren, dann „Erneut versuchen“
        let w2 = try await player(try XCTUnwrap(x2.channels.first { $0.name == "Kanal String" }), CGPoint(x: 60, y: 520))
        mock.handler = cfg.handler()
        try await refresh(x2, ctx)
        let beforeRetry2 = liveRequests("102")
        B03UI.click(try XCTUnwrap(B03UI.element(w2, "Erneut versuchen", role: "AXButton")), in: w2)
        await B03UI.spin(2.0)
        let afterRetry2 = liveRequests("102")
        B03UI.shot(w2, "AK-29-erneut-versuchen-nach-aktualisieren")

        B03QA.log("AK-28|retry|xtream|texteVorher=\(textsBefore.prefix(4))|texteNachKlick=\(textsX.prefix(4))|liveAnfragen vor/nach Klick=\(beforeRetryX)/\(afterRetryX)")
        B03QA.log("AK-28|retry|m3u|liveAnfragen vor/nach Klick=\(beforeRetryM)/\(afterRetryM)")
        B03QA.log("AK-29|retry|xtream nach Aktualisieren|vorher=\(beforeRetry2)|nachher=\(afterRetry2)")
        let missing = "Die Zugangsdaten dieser Xtream-Playlist fehlen auf diesem Gerät. Bitte die Playlist löschen und neu importieren."
        let showsMissing = textsX.contains { $0.contains(missing) }
        let newX = Array(afterRetryX.dropFirst(beforeRetryX))
        B03QA.log("AK-28|retry|xtream|neueAbrufe=\(newX)|meldungZugangsdatenFehlenSichtbar=\(showsMissing)")
        XCTAssertFalse(showsMissing, "Ist (weicht von der Spec ab): keine Meldung „Zugangsdaten fehlen“")
        // Ist nicht stabil: je nach Lauf lädt der Knopf bei Xtream nichts (gelöschte Playlist noch erreichbar → Zugangsdaten
        // fehlen, Meldung bleibt unsichtbar) oder die Adresse ohne Zugangsdaten (Beziehung schon nil). Nie mit Zugangsdaten.
        XCTAssertTrue(newX.allSatisfy { $0 == "/live/101.m3u8" }, "Ist: kein neuer Abruf mit Benutzername und Passwort")
        XCTAssertGreaterThan(afterRetryM, beforeRetryM, "M3U nach Löschen: alte Adresse erneut geladen")
        XCTAssertEqual(afterRetry2.last, "/live/102.m3u8", "Ist: nach dem Aktualisieren ohne Benutzername und Passwort")
        XCTExpectFailure("BUG-05 · „Erneut versuchen“ nach Löschen/Aktualisieren ruft den Anbieter erneut – ohne Zugangsdaten bzw. mit alter Adresse (FB-05)") {
            XCTAssertTrue(newX.isEmpty, "nach dem Löschen kein neuer Abruf")
            XCTAssertEqual(afterRetryM, beforeRetryM, "M3U nach dem Löschen kein neuer Abruf")
            XCTAssertNotEqual(afterRetry2.last, "/live/102.m3u8", "nach dem Aktualisieren mit gültiger Adresse")
        }
    }
}
