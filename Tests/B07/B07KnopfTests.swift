import XCTest
import SwiftUI
import SwiftData
import AVFoundation
import AVKit
import AppKit
@testable import MikaPlusPlayer

/// B07 · Knopf und Taste (AK-01 – AK-09, EC-01, EC-02, EC-04, EC-05) – echte `PlayerView` in Fenstern des
/// Test-Hosts, Knopf per Klick bzw. Bedienungshilfen-Aktion, Taste P als Tastaturereignis, Systemfenster über
/// CGWindowList. Medien ohne Tonspur, nur 127.0.0.1.
@MainActor
final class B07KnopfTests: B07TestCase {

    // MARK: Hilfen

    /// Wartet auf „spielt“ und darauf, dass PiP möglich ist; blendet danach die Steuerung ein.
    private func waitPlayingAndControls(_ w: NSWindow, _ tag: String) async throws -> AVKitPlaybackEngine {
        let ok = await B07Engine.wait(25) { self.lastEngine?.state == .playing }
        guard ok != nil, let e = lastEngine else {
            XCTFail("\(tag): Stream spielt nicht (\(lastEngine.map(B07Engine.detail) ?? "keine Engine"))")
            throw XCTSkip("kein Stream")
        }
        _ = await B07Engine.wait(15) { B07Engine.pipController(e)?.isPictureInPicturePossible == true }
        await showControls(w)
        B07QA.log("\(tag)|spielt|\(B07Engine.detail(e))|steuerung=\(controlsVisible(w))")
        return e
    }

    /// Betätigt den PiP-Knopf: echter Klick an seiner Position, sonst Bedienungshilfen-Aktion. Rückgabe: Weg.
    @discardableResult
    private func pressPiPButton(_ w: NSWindow, _ e: AVKitPlaybackEngine) async -> String {
        await showControls(w)
        guard let b = pipButton(w) else { return "kein Knopf" }
        let before = e.isPictureInPictureActive
        B07UI.click(b, in: w)
        if await B07Engine.wait(4, { e.isPictureInPictureActive != before }) != nil { return "Klick" }
        guard let b2 = pipButton(w) else { return "Klick (Knopf danach weg)" }
        let pressed = B07UI.press(b2)
        _ = await B07Engine.wait(6) { e.isPictureInPictureActive != before }
        return "AXPress(\(pressed))"
    }

    private func pipLabel(_ w: NSWindow) -> String { pipButton(w).map(B07UI.label) ?? "-" }

    // MARK: AK-01

    func testAK01_KnopfObenRechtsNebenVollbildMitTooltip() async throws {
        let c = channel("QA HLS", "/livehls/ak01/index.m3u8")
        let w = playerWindow(c)
        try await activate(w)
        let e = try await waitPlayingAndControls(w, "AK-01")
        B07UI.dump(w, "AK-01")
        let pip = pipButton(w)
        let full = fullscreenButton(w)
        XCTAssertNotNil(pip, "PiP-Knopf sichtbar")
        XCTAssertNotNil(full)
        guard let pip, let full else { return }
        let pf = B07UI.frame(pip), ff = B07UI.frame(full)
        let win = w.frame
        B07QA.log("AK-01|pip='\(B07UI.label(pip))' help='\(B07UI.help(pip))' frame=\(pf)|vollbild='\(B07UI.label(full))' frame=\(ff)|fenster=\(win)")
        B07QA.log("AK-01|supports=\(e.supportsPictureInPicture) systemSupported=\(AVPictureInPictureController.isPictureInPictureSupported())")
        XCTAssertLessThan(pf.maxX, ff.minX, "PiP-Knopf links neben dem Vollbild-Knopf")
        XCTAssertEqual(pf.midY, ff.midY, accuracy: 2, "gleiche Zeile")
        XCTAssertGreaterThan(pf.midY, win.midY, "obere Hälfte (Bildschirmkoordinaten, y nach oben)")
        XCTAssertGreaterThan(pf.midX, win.midX, "rechte Hälfte")
        XCTAssertEqual(B07UI.help(pip), "Bild-in-Bild", "Tooltip")
        B07QA.shot(w, "AK-01-knopf-mac")
    }

    // MARK: AK-02

    func testAK02_KeinKnopfBeimLadenFehlerUndAusgeblendet() async throws {
        // a) lädt noch (Playlist 8 s verzögert)
        let cLoad = channel("QA lädt", "/delay/8/livehls/ak02a/index.m3u8")
        let w1 = playerWindow(cLoad)
        await B07QA.spin(1.5)
        let buttonsLoading = B07UI.buttons(w1)
        let busy = B07UI.elements(w1).contains { B07UI.role($0) == "AXBusyIndicator" || B07UI.role($0) == "AXProgressIndicator" }
        B07QA.log("AK-02a|lädt|engine=\(lastEngine.map(B07Engine.detail) ?? "-")|knöpfe=\(buttonsLoading)|ladekreis=\(busy)")
        XCTAssertNil(pipButton(w1), "kein PiP-Knopf beim Laden")
        B07QA.shot(w1, "AK-02-laedt-kein-knopf")
        B07UI.close(w1); windows.removeAll()

        // b) Fehleransicht (404)
        let cFail = channel("QA 404", "/404/ak02b.m3u8")
        let w2 = playerWindow(cFail)
        let failed = await B07Engine.wait(15) { if case .failed = self.lastEngine?.state { return true } else { return false } }
        let failedButtons = B07UI.buttons(w2)
        B07QA.log("AK-02b|fehler nach \(failed.map(B07QA.f1) ?? "-")s|knöpfe=\(failedButtons)")
        XCTAssertNotNil(failed)
        XCTAssertNil(pipButton(w2), "kein PiP-Knopf in der Fehleransicht")
        XCTAssertNotNil(B07UI.find(w2, "Wiedergabe fehlgeschlagen"))
        B07QA.shot(w2, "AK-02-fehler-kein-knopf")
        B07UI.close(w2); windows.removeAll()

        // c) ausgeblendet nach 3,5 s, Klick aufs Bild blendet wieder ein
        let c = channel("QA HLS", "/livehls/ak02c/index.m3u8")
        let w3 = playerWindow(c)
        try await activate(w3)
        _ = try await waitPlayingAndControls(w3, "AK-02c")
        XCTAssertNotNil(pipButton(w3))
        let t0 = Date()
        let hidden = await B07Engine.wait(8) { self.pipButton(w3) == nil }
        B07QA.log("AK-02c|ausgeblendet nach \(hidden.map(B07QA.f1) ?? "-")s (ab sichtbar)|knöpfe=\(B07UI.buttons(w3))")
        XCTAssertNotNil(hidden)
        XCTAssertGreaterThan(Date().timeIntervalSince(t0), 2.0)
        try? await activate(w3)
        B07UI.click(w3, at: NSPoint(x: w3.frame.width / 2, y: w3.frame.height / 2 - 40))
        let back = await B07Engine.wait(3) { self.pipButton(w3) != nil }
        B07QA.log("AK-02c|nach Klick aufs Bild sichtbar nach \(back.map(B07QA.f1) ?? "-")s")
        XCTAssertNotNil(back, "Klick aufs Bild blendet den Knopf wieder ein")
    }

    // MARK: AK-03 / AK-04 / AK-19 (Platzhalter) / AK-20 (Fenster)

    func testAK03_AK04_KnopfOeffnetUndSchliesstSystemfenster() async throws {
        let c = channel("QA Sender Geheim", "/livehls/ak03/index.m3u8")
        let w = playerWindow(c)
        try await activate(w)
        let e = try await waitPlayingAndControls(w, "AK-03")
        let beforeWins = B07PiPWindows.current()
        let labelBefore = pipLabel(w)
        let way = await pressPiPButton(w, e)
        let started = await B07Engine.wait(10) { e.isPictureInPictureActive && !B07PiPWindows.current().isEmpty }
        let pipWins = B07PiPWindows.current()
        B07QA.log("AK-03|weg=\(way)|aktiv nach \(started.map(B07QA.f1) ?? "-")s|vorher=\(beforeWins)|fenster=\(pipWins)")
        XCTAssertTrue(beforeWins.isEmpty)
        XCTAssertNotNil(started, "Systemfenster erscheint")
        await B07QA.spin(2)
        let player = B07Engine.avPlayer(e)
        B07QA.log("AK-03|nach 2 s|\(B07Engine.detail(e))|knopf vorher='\(labelBefore)' nachher='\(pipLabel(w))'")
        XCTAssertEqual(player?.rate ?? 0, 1.0, accuracy: 0.01, "spielt weiter")
        if let pw = pipWins.first {
            XCTAssertGreaterThan(pw.layer, 0, "schwebt über normalen Fenstern (Ebene > 0)")
            XCTAssertTrue(pw.name.isEmpty || !pw.name.contains("QA Sender Geheim"))
            await B07QA.requestWindowShot(pw.id, "AK-03-pip-fenster-mac")
        }
        // Platzhalter im App-Fenster; Steuerung einblenden, damit der Knopf im Bild ist
        await showControls(w)
        let exitLabel = pipLabel(w)
        B07QA.shot(w, "AK-03-platzhalter-app-mac")
        let texts = B07UI.elements(w).map { B07UI.label($0) }.filter { !$0.isEmpty }
        B07QA.log("AK-03|knopf jetzt='\(exitLabel)'|ax-texte=\(texts)")
        XCTAssertNotEqual(exitLabel, labelBefore, "Knopf zeigt jetzt „Bild-in-Bild schließen“")

        // AK-04: erneut betätigen → Fenster weg, Video zurück, läuft weiter
        let way2 = await pressPiPButton(w, e)
        let stopped = await B07Engine.wait(10) { !e.isPictureInPictureActive && B07PiPWindows.current().isEmpty }
        await B07QA.spin(2)
        B07QA.log("AK-04|weg=\(way2)|beendet nach \(stopped.map(B07QA.f1) ?? "-")s|\(B07Engine.detail(e))|pipfenster=\(B07PiPWindows.current())")
        XCTAssertNotNil(stopped)
        XCTAssertEqual(player?.rate ?? 0, 1.0, accuracy: 0.01, "Wiedergabe läuft nach dem Schließen weiter")
        XCTAssertFalse(e.isPaused)
        await showControls(w)
        B07QA.log("AK-04|knopf wieder='\(pipLabel(w))'")
        XCTAssertEqual(pipLabel(w), labelBefore)
        B07QA.shot(w, "AK-04-nach-schliessen-app-mac")
    }

    // MARK: AK-05

    func testAK05_TasteP_KleinUndGross_BlendetSteuerungEin_KeinHUD_KeinBeep() async throws {
        let c = channel("QA HLS", "/livehls/ak05/index.m3u8")
        let w = playerWindow(c)
        try await activate(w)
        let e = try await waitPlayingAndControls(w, "AK-05")
        // Steuerung ausblenden lassen
        let hidden = await B07Engine.wait(8) { !self.controlsVisible(w) }
        XCTAssertNotNil(hidden)
        let imagesBefore = B07UI.elements(w).filter { B07UI.role($0) == "AXImage" }.count

        // p (klein) bei ausgeblendeter Steuerung → Start
        let beep1 = await press(w, .char("p"))
        XCTAssertEqual(beep1, [], "p behandelt, kein Systembeep")
        let on = await B07Engine.wait(10) { e.isPictureInPictureActive }
        let controlsAfterP = controlsVisible(w)
        let images = B07UI.elements(w).filter { B07UI.role($0) == "AXImage" }.map(B07UI.label)
        B07QA.log("AK-05|p klein → aktiv nach \(on.map(B07QA.f1) ?? "-")s|steuerung=\(controlsAfterP)|bilder vorher=\(imagesBefore) nachher=\(images)|pipfenster=\(B07PiPWindows.current().count)")
        XCTAssertNotNil(on, "p startet Bild-in-Bild auch bei ausgeblendeter Steuerung")
        XCTAssertTrue(controlsAfterP, "Steuerung blendet sich ein")
        // Kein HUD: B06-HUD zeigt ein Bild (play/pause/speaker) als AXImage – hier keins
        XCTAssertFalse(images.contains { $0.contains("play") || $0.contains("pause") || $0.contains("speaker") }, "kein HUD")
        // Steuerung bleibt ~3,5 s
        let t0 = Date()
        let gone = await B07Engine.wait(8) { !self.controlsVisible(w) }
        let visibleFor = Date().timeIntervalSince(t0)
        B07QA.log("AK-05|steuerung wieder weg nach \(B07QA.f1(visibleFor))s (gone=\(gone != nil))")
        XCTAssertNotNil(gone)
        XCTAssertGreaterThan(visibleFor, 2.5)
        XCTAssertLessThan(visibleFor, 6.0)

        // P (groß, mit Umschalttaste) → Ende
        let beep2 = await press(w, .char("P"), flags: [.shift])
        XCTAssertEqual(beep2, [], "P behandelt, kein Systembeep")
        let off = await B07Engine.wait(10) { !e.isPictureInPictureActive }
        await B07QA.spin(1.5)
        B07QA.log("AK-05|P groß → beendet nach \(off.map(B07QA.f1) ?? "-")s|\(B07Engine.detail(e))|pipfenster=\(B07PiPWindows.current().count)|beep=\(beep1 + beep2)")
        XCTAssertNotNil(off, "P (groß) beendet Bild-in-Bild")
        XCTAssertEqual(B07Engine.avPlayer(e)?.rate ?? 0, 1.0, accuracy: 0.01)
    }

    // MARK: AK-06

    func testAK06_PWaehrendDesLadens_KeinFensterAuchSpaeterNicht_KeineMeldung() async throws {
        let c = channel("QA lädt", "/delay/5/livehls/ak06/index.m3u8")
        let w = playerWindow(c)
        try await activate(w)
        await B07QA.spin(0.8)
        let stateAtP = lastEngine.map { B07Engine.name($0.state) } ?? "-"
        let beep = await press(w, .char("p"))
        XCTAssertEqual(beep, [])
        B07QA.log("AK-06|P bei state=\(stateAtP)|possible=\(lastEngine.flatMap { B07Engine.pipController($0)?.isPictureInPicturePossible }.map { "\($0)" } ?? "-")")
        XCTAssertEqual(stateAtP, "loading")
        let playing = await B07Engine.wait(25) { self.lastEngine?.state == .playing }
        XCTAssertNotNil(playing)
        await B07QA.spin(4)
        let e = lastEngine
        let wins = B07PiPWindows.current()
        let texts = B07UI.elements(w).map(B07UI.label).filter { !$0.isEmpty }
        B07QA.log("AK-06|spielt nach \(playing.map(B07QA.f1) ?? "-")s, +4 s: \(e.map(B07Engine.detail) ?? "-")|pipfenster=\(wins)|texte=\(texts)|fenster=\(NSApp.windows.filter { $0.isVisible }.map { $0.title })")
        XCTAssertFalse(e?.isPictureInPictureActive ?? true, "kein Bild-in-Bild, auch nicht später")
        XCTAssertTrue(wins.isEmpty)
        XCTAssertFalse(texts.contains { $0.localizedCaseInsensitiveContains("bild-in-bild") }, "keine Meldung")
        XCTAssertEqual(NSApp.windows.filter { $0.isVisible && $0.isSheet }.count, 0)
    }

    // MARK: AK-07

    func testAK07_PNachFehlschlag_NichtsFehleransichtBleibt() async throws {
        let c = channel("QA 404", "/404/ak07.m3u8")
        let w = playerWindow(c)
        try await activate(w)
        let failed = await B07Engine.wait(15) { if case .failed = self.lastEngine?.state { return true } else { return false } }
        XCTAssertNotNil(failed)
        let beep = await press(w, .char("p"))
        XCTAssertEqual(beep, [])
        await B07QA.spin(3)
        let e = lastEngine
        B07QA.log("AK-07|nach P: \(e.map(B07Engine.detail) ?? "-")|pipfenster=\(B07PiPWindows.current())|fehleransicht=\(B07UI.find(w, "Wiedergabe fehlgeschlagen") != nil)")
        XCTAssertFalse(e?.isPictureInPictureActive ?? true)
        XCTAssertTrue(B07PiPWindows.current().isEmpty)
        XCTAssertNotNil(B07UI.find(w, "Wiedergabe fehlgeschlagen"), "Fehleransicht bleibt")
        B07QA.shot(w, "AK-07-fehler-nach-p")
    }

    // MARK: AK-09 (macOS-Teil)

    func testAK09_TSUeberVLC_KeinKnopf_PZeigtHinweisNurHLS() async throws {
        let c = channel("QA TS", "/tslive/ak09.ts")
        let w = playerWindow(c)
        try await activate(w)
        // VLC: Steuerung erscheint nur bei .playing – warten, bis der Vollbild-Knopf da ist
        var shown: TimeInterval? = await B07Engine.wait(12) { self.controlsVisible(w) }
        if shown == nil, await showControls(w) { shown = 0 }
        let buttons = B07UI.buttons(w)
        B07QA.log("AK-09|steuerung sichtbar=\(shown != nil)|knöpfe=\(buttons)|pip-delegates=\(B07Registry.liveDelegates.count)")
        XCTAssertNotNil(shown, "VLC spielt, Steuerung sichtbar")
        XCTAssertNil(pipButton(w), "kein Bild-in-Bild-Knopf")
        XCTAssertEqual(B07Registry.liveControllers.count, 0, "VLC legt keinen PiP-Controller an")
        B07QA.shot(w, "AK-09-ts-vlc-ohne-knopf-mac")
        // Steuerung ausblenden lassen, dann P
        _ = await B07Engine.wait(8) { !self.controlsVisible(w) }
        let hiddenBefore = !controlsVisible(w)
        let beep = await press(w, .char("p"))
        let flashed = await B07Engine.wait(2) { self.controlsVisible(w) }
        let texts = B07UI.elements(w).map(B07UI.label).filter { !$0.isEmpty }
        B07QA.shot(w, "BUILD-BUG-04-ts-vlc-p-hinweis-mac")
        await B07QA.spin(2)
        B07QA.log("AK-09|P: vorher ausgeblendet=\(hiddenBefore) → eingeblendet=\(flashed != nil)|pipfenster=\(B07PiPWindows.current())|texte=\(texts)|beep=\(beep)")
        XCTAssertEqual(beep, [], "P wird behandelt (kein Beep)")
        XCTAssertTrue(hiddenBefore)
        XCTAssertNotNil(flashed, "P blendet die Steuerung ein")
        XCTAssertTrue(B07PiPWindows.current().isEmpty, "weiterhin kein Bild-in-Bild bei VLC")
        // Behoben (BUG-04, 2026-09-27): P erklärt kurz, dass es Bild-in-Bild nur mit HLS gibt.
        XCTAssertTrue(texts.contains { $0.contains("Bild-in-Bild gibt es nur mit HLS, nicht mit MPEG-TS.") },
                      "App erklärt, warum Bild-in-Bild fehlt")
        let hintGone = await B07Engine.wait(4) {
            !B07UI.elements(w).map(B07UI.label).contains { $0.contains("Bild-in-Bild gibt es nur mit HLS") }
        }
        XCTAssertNotNil(hintGone, "der Hinweis verschwindet nach wenigen Sekunden")
    }

    /// AK-09, zweiter Satz: Xtream im Standardformat → `.ts` → VLC → kein PiP.
    func testAK09_XtreamStandardformatLandetBeiVLC() async throws {
        let panel = MockXtreamServer()
        try panel.start()
        defer { panel.stop(); B01.removeCachedResponses(for: panel) }
        let ctx = container.mainContext
        let result = await B01.importXtream(host: "http://\(panel.hostPort)", pass: B07QA.pass, context: ctx)
        guard case .success(let pl) = result else { return XCTFail("Import: \(String(describing: B01.message(result)))") }
        let chans = pl.channels
        XCTAssertFalse(chans.isEmpty)
        var lines: [String] = []
        for ch in chans {
            let url = try StreamURLResolver.playableURL(for: ch)
            let e = PlaybackEngineFactory.engine(for: url)
            lines.append("\(ch.name)|gespeichert=\(ch.streamURL.lastPathComponent)|typ=\(type(of: e))|supportsPiP=\(e.supportsPictureInPicture)")
            XCTAssertEqual(url.pathExtension, "ts")
            XCTAssertFalse(e.supportsPictureInPicture)
            XCTAssertTrue(String(describing: type(of: e)).contains("VLC"))
        }
        B07QA.log("AK-09|Xtream-Import mit Format .mpegts (Standard des Import-Sheets, siehe B07ImportHinweisTests)|\(lines)")
        try? XtreamCredentialStore.standard.deleteAll()
    }

    // MARK: EC-01 / EC-02

    func testEC01_OhneEndung_AVKit_RohesTSScheitert_KeinKnopf() async throws {
        let c = channel("QA ohne Endung", "/live/\(B07QA.user)/\(B07QA.pass)/101")
        XCTAssertTrue(PlaybackEngineFactory.engine(for: c.streamURL) is AVKitPlaybackEngine)
        let w = playerWindow(c)
        let settled = await B07Engine.wait(25) {
            guard let s = self.lastEngine?.state else { return false }
            if case .failed = s { return true }
            return s == .playing
        }
        await B07QA.spin(1)
        let e = lastEngine
        B07QA.log("EC-01|nach \(settled.map(B07QA.f1) ?? "-")s: \(e.map(B07Engine.detail) ?? "-")|knöpfe=\(B07UI.buttons(w))")
        B07QA.shot(w, "EC-01-ohne-endung")
        if case .failed = e?.state {
            XCTAssertNil(pipButton(w), "kein Knopf nach Fehlschlag")
        }
    }

    func testEC02_M3UEndung_AVKit_PiPWieM3U8() async throws {
        let c = channel("QA m3u", "/livehls/ec02/index.m3u")
        XCTAssertTrue(PlaybackEngineFactory.engine(for: c.streamURL) is AVKitPlaybackEngine)
        let w = playerWindow(c)
        try await activate(w)
        let e = try await waitPlayingAndControls(w, "EC-02")
        XCTAssertNotNil(pipButton(w))
        let way = await pressPiPButton(w, e)
        let on = await B07Engine.wait(10) { e.isPictureInPictureActive && !B07PiPWindows.current().isEmpty }
        B07QA.log("EC-02|weg=\(way)|aktiv nach \(on.map(B07QA.f1) ?? "-")s|\(B07Engine.detail(e))")
        XCTAssertNotNil(on)
        e.stopPictureInPicture()
        _ = await B07Engine.wait(8) { !e.isPictureInPictureActive }
    }

    // MARK: EC-04 / EC-05

    func testEC04_EC05_AbbruchWaehrendPiP_FehleransichtFensterBleibt_PBeendet_ErneutVersuchen() async throws {
        // Ab 14 s nach der ersten Anfrage liefert der Anbieter 15 s lang nur 404, danach wieder Daten.
        let c = channel("QA Abbruch", "/abort/14/livehls/ec04/index.m3u8")
        let w = playerWindow(c)
        try await activate(w)
        let e = try await waitPlayingAndControls(w, "EC-04")
        _ = await pressPiPButton(w, e)
        let on = await B07Engine.wait(10) { e.isPictureInPictureActive }
        XCTAssertNotNil(on)
        let failed = await B07Engine.wait(75) { if case .failed = e.state { return true } else { return false } }
        await B07QA.spin(1)
        let winsAtFail = B07PiPWindows.current()
        B07QA.log("EC-04|fehler nach \(failed.map(B07QA.f1) ?? "-")s|\(B07Engine.detail(e))|pipfenster=\(winsAtFail)|knöpfe=\(B07UI.buttons(w))")
        B07QA.shot(w, "EC-04-abbruch-waehrend-pip-app")
        if let pw = winsAtFail.first { await B07QA.requestWindowShot(pw.id, "EC-04-abbruch-waehrend-pip-fenster") }
        guard failed != nil else { return XCTFail("Stream brach nicht ab: \(B07Engine.detail(e))") }
        XCTAssertNil(pipButton(w), "Knopf verschwindet mit der Fehleransicht")
        let pipStillActive = e.isPictureInPictureActive
        // EC-05: „Erneut versuchen“ bei (evtl.) aktivem Bild-in-Bild – nach der Störung
        // Störung dauert 45 s ab Sekunde 14 nach der ersten Anfrage – bis dahin warten
        let first = mock.requests(containing: "ec04").first?.time ?? Date()
        let until = first.addingTimeInterval(61)
        B07QA.log("EC-05|warte bis Störungsende (\(B07QA.f1(until.timeIntervalSinceNow)) s)")
        await B07QA.spin(max(0, until.timeIntervalSinceNow))
        let enginesBefore = B07Registry.engines.count
        if let retry = B07UI.find(w, role: "AXButton", "Erneut versuchen") { B07UI.press(retry) }
        let replay = await B07Engine.wait(20) { e.state == .playing }
        B07QA.log("EC-05|pip vor Erneut=\(pipStillActive)|spielt wieder nach \(replay.map(B07QA.f1) ?? "-")s|engines vorher=\(enginesBefore) nachher=\(B07Registry.engines.count)|gleiche Engine=\(B07Registry.engines.last === e)|\(B07Engine.detail(e))|pipfenster=\(B07PiPWindows.current().count)")
        // EC-04 zweiter Teil: P beendet weiterhin
        if e.isPictureInPictureActive {
            await press(w, .char("p"))
            let off = await B07Engine.wait(10) { !e.isPictureInPictureActive }
            B07QA.log("EC-04|P beendet nach \(off.map(B07QA.f1) ?? "-")s")
            XCTAssertNotNil(off)
        }
        XCTAssertEqual(B07Registry.engines.count, enginesBefore, "Erneut versuchen lädt in derselben Engine")
    }
}

/// AK-09: Das Import-Sheet schlägt für Xtream MPEG-TS vor und erklärt nur „benötigt VLCKit“ – kein Wort zu Bild-in-Bild.
@MainActor
final class B07ImportHinweisTests: XCTestCase {
    func testAK09_ImportSheetStandardMPEGTS_MitHinweisBildInBildNurHLS() async throws {
        let container = try B07QA.inMemoryContainer()
        let w = B07UI.window(ImportPlaylistView().modelContainer(container), size: CGSize(width: 520, height: 640), title: "B07-Import")
        defer { B07UI.close(w) }
        await B07QA.spin(1.5)
        let texts = B07UI.elements(w).map(B07UI.label).filter { !$0.isEmpty }
        B07QA.log("AK-09|Import-Sheet Texte=\(texts)")
        B07QA.shot(w, "AK-09-import-standard-mpegts")
        B07QA.shot(w, "BUILD-BUG-04-import-standard-mpegts-hinweis")
        XCTAssertTrue(texts.contains { $0.contains(XtreamOutput.mpegts.hint) }, "Standard ist MPEG-TS (Hinweistext des gewählten Formats)")
        // Behoben (BUG-04, 2026-09-27): Der Hinweis zum Standardformat nennt die Einschränkung.
        XCTAssertTrue(texts.contains { $0.contains("Bild-in-Bild gibt es nur mit HLS.") },
                      "Hinweis, dass MPEG-TS kein Bild-in-Bild kann")
        XCTAssertFalse(XtreamOutput.hls.hint.contains("Bild-in-Bild gibt es nur"), "der HLS-Hinweis bleibt unverändert")
        B07QA.log("AK-09|Hinweise: mpegts='\(XtreamOutput.mpegts.hint)' hls='\(XtreamOutput.hls.hint)'")
    }
}
