import XCTest
import SwiftUI
import SwiftData
import AVFoundation
import AVKit
import AppKit
@testable import MikaPlusPlayer

/// B07 · Knöpfe des **echten** Bild-in-Bild-Systemfensters (macOS) und App-Wechsel am Mac.
///
/// Das schwebende Fenster gehört dem Systemprozess `PIPAgent`. Seine Knöpfe (`close`, `restore`, `pause`) bedient
/// der Helfer außerhalb des Test-Hosts (`bridge2.sh`, Auftrag `pipax`) per Bedienungshilfen-Aktion – nur, wenn das
/// Fenster nachweislich `PIPAgent` gehört. Kein Mauszeiger, keine anderen Apps. Ohne Helfer werden die Tests
/// übersprungen (nicht bestanden). Medien ohne Tonspur, nur 127.0.0.1.
///
/// Deckt: AK-16 (Pause im Fenster, echt), EC-07 (Schließen), EC-08 (Zurück zur App, offener Player),
/// AK-15 / EC-08 nach „Zurück“ (Schließen bzw. Zurück zur App am verwaisten Fenster), AK-10 (macOS ohne Auto-Start).
@MainActor
final class B07SystemfensterTests: B07TestCase {

    // MARK: Hilfen

    private func waitPlaying(_ probe: @escaping () -> AVKitPlaybackEngine?) async -> AVKitPlaybackEngine? {
        guard await B07Engine.wait(25, { probe()?.state == .playing }) != nil, let e = probe() else { return nil }
        _ = await B07Engine.wait(15) { B07Engine.pipController(e)?.isPictureInPicturePossible == true }
        return e
    }

    private func startPiP(_ w: NSWindow, _ e: AVKitPlaybackEngine) async -> B07PiPWindows.Info? {
        await showControls(w)
        if let b = pipButton(w) { B07UI.click(b, in: w) }
        if await B07Engine.wait(4, { e.isPictureInPictureActive }) == nil, let b = pipButton(w) { B07UI.press(b) }
        guard await B07Engine.wait(10, { e.isPictureInPictureActive && !B07PiPWindows.current().isEmpty }) != nil else { return nil }
        await B07QA.spin(1)
        return B07PiPWindows.current().first
    }

    /// Knopf des Systemfensters per Helfer; überspringt den Test, wenn kein Helfer läuft.
    @discardableResult
    private func pipAX(_ win: B07PiPWindows.Info, _ action: String, _ id: String = "") async throws -> String {
        guard ProcessInfo.processInfo.environment["B07_BRIDGE"] != nil else { throw XCTSkip("kein Helfer für das Systemfenster (B07_BRIDGE fehlt)") }
        let out = await B07QA.bridge("pipax \(win.id) \(action) \(id)", timeout: 20) ?? "Zeitablauf"
        if out.hasPrefix("abgelehnt") || out == "Zeitablauf" { throw XCTSkip("Helfer: \(out)") }
        return out
    }

    private func playPauseLabel(_ w: NSWindow) -> String {
        B07UI.elements(w).first { B07UI.role($0) == "AXButton" && (B07UI.label($0).contains("pause.fill") || B07UI.label($0).contains("play.fill")) }
            .map(B07UI.label) ?? "-"
    }

    private func pipLabel(_ w: NSWindow) -> String { pipButton(w).map(B07UI.label) ?? "-" }

    // MARK: AK-16 · Pause-Knopf des echten Systemfensters

    func testAK16_PauseKnopfDesSystemfensters_AppZeigtWeiterLaeuft() async throws {
        let c = channel("QA Pause echt", "/livehls/p16/index.m3u8")
        let w = playerWindow(c)
        try await activate(w)
        guard let e = await waitPlaying({ self.lastEngine }) else { return XCTFail("spielt nicht") }
        guard let win = await startPiP(w, e) else { return XCTFail("PiP startet nicht") }
        let list = try await pipAX(win, "list")
        B07QA.log("AK-16e|Systemfenster \(win)|Bedienungshilfen:\n\(list)")
        XCTAssertTrue(list.contains("id='pause'") && list.contains("id='close'") && list.contains("id='restore'"),
                      "Systemfenster bietet Pause, Schließen, Zurück zur App")
        await B07QA.requestWindowShot(win.id, "AK-16-systemfenster-vor-pause")
        let player = B07Engine.avPlayer(e)
        let pressed = try await pipAX(win, "press", "pause")
        let paused = await B07Engine.wait(4) { (player?.rate ?? 1) == 0 }
        await B07QA.spin(1)
        await showControls(w)
        let label0 = playPauseLabel(w)
        let listAfter = try await pipAX(win, "list")
        B07QA.log("AK-16e|\(pressed)|rate=\(player?.rate ?? -1) nach \(paused.map(B07QA.f1) ?? "-")s|isPaused(App)=\(e.isPaused)|knopf App='\(label0)'|pip aktiv=\(e.isPictureInPictureActive)|Fensterknöpfe danach: \(listAfter.replacingOccurrences(of: "\n", with: " / "))")
        await B07QA.requestWindowShot(win.id, "AK-16-systemfenster-nach-pause")
        B07QA.shot(w, "AK-16-app-nach-pause-im-systemfenster")
        XCTAssertNotNil(paused, "Pause-Knopf des Systemfensters hält den Stream an")
        // Leertaste im Player (Fenster des Players nach vorn)
        let b1 = await press(w, .space)
        await B07QA.spin(1.2)
        let r1 = player?.rate ?? -1
        let l1 = playPauseLabel(w)
        let b2 = await press(w, .space)
        await B07QA.spin(1.5)
        let r2 = player?.rate ?? -1
        B07QA.log("AK-16e|Leertaste 1 → rate=\(r1) knopf='\(l1)' | Leertaste 2 → rate=\(r2) knopf='\(playPauseLabel(w))'|beep=\(b1 + b2)")
        XCTAssertEqual(b1 + b2, [])
        e.stopPictureInPicture()
        _ = await B07Engine.wait(8) { !e.isPictureInPictureActive }
        XCTExpectFailure("BUG-03 · Pause im Bild-in-Bild-Fenster: App zeigt weiter „läuft“, erster Druck verpufft") {
            XCTAssertTrue(e.isPaused || label0.contains("play.fill"), "App-Zustand folgt der Pause im Systemfenster")
            XCTAssertEqual(r1, 1, accuracy: 0.01, "erster Druck setzt fort")
        }
    }

    // MARK: EC-07 · Schließen-Knopf des Systemfensters

    func testEC07_SchliessenKnopfDesSystemfensters_AppMerktEsPlayerSpieltImPlayer() async throws {
        let c = channel("QA Schließen", "/livehls/c07/index.m3u8")
        let w = playerWindow(c)
        try await activate(w)
        guard let e = await waitPlaying({ self.lastEngine }) else { return XCTFail("spielt nicht") }
        guard let win = await startPiP(w, e) else { return XCTFail("PiP startet nicht") }
        let before = pipLabel(w)
        let out = try await pipAX(win, "press", "close")
        let ended = await B07Engine.wait(6) { !e.isPictureInPictureActive }
        await B07QA.spin(2)
        await showControls(w)
        let rate = B07Engine.avPlayer(e)?.rate ?? -1
        B07QA.log("EC-07|\(out)|beendet nach \(ended.map(B07QA.f1) ?? "-")s|\(B07Engine.detail(e))|knopf vorher='\(before)' nachher='\(pipLabel(w))' play/pause='\(playPauseLabel(w))'|pipfenster=\(B07PiPWindows.current().count)")
        B07QA.shot(w, "EC-07-nach-schliessen-im-systemfenster")
        XCTAssertNotNil(ended, "App merkt das Ende (Delegate)")
        XCTAssertTrue(B07PiPWindows.current().isEmpty)
        XCTAssertTrue(pipLabel(w).contains("pip.enter"), "Knopf wieder „Bild-in-Bild öffnen“")
        // Ob das System beim Schließen pausiert, steht offen (Spec EC-07) – festgehalten wird der Ist-Wert;
        // bei Pause muss die App es anzeigen (sonst AK-16/BUG-03).
        if rate == 0 {
            XCTExpectFailure("BUG-03 · System pausiert beim Schließen, App zeigt weiter „läuft“") {
                XCTAssertTrue(e.isPaused, "App-Zustand folgt der Pause durch das System")
            }
        }
    }

    // MARK: EC-08 · „Zurück zur App“ bei offenem Player

    func testEC08_ZurueckZurAppKnopf_BeiOffenemPlayer_BildKehrtZurueck() async throws {
        let c = channel("QA Restore", "/livehls/r08/index.m3u8")
        let w = playerWindow(c)
        try await activate(w)
        guard let e = await waitPlaying({ self.lastEngine }) else { return XCTFail("spielt nicht") }
        guard let win = await startPiP(w, e) else { return XCTFail("PiP startet nicht") }
        let out = try await pipAX(win, "press", "restore")
        let ended = await B07Engine.wait(6) { !e.isPictureInPictureActive }
        await B07QA.spin(2)
        await showControls(w)
        let rate = B07Engine.avPlayer(e)?.rate ?? -1
        B07QA.log("EC-08|\(out)|beendet nach \(ended.map(B07QA.f1) ?? "-")s|\(B07Engine.detail(e))|knopf='\(pipLabel(w))'|pipfenster=\(B07PiPWindows.current().count)|keyWindow=\(NSApp.keyWindow === w)")
        B07QA.shot(w, "EC-08-mac-zurueck-zur-app")
        XCTAssertNotNil(ended)
        XCTAssertTrue(B07PiPWindows.current().isEmpty)
        XCTAssertEqual(rate, 1, accuracy: 0.01, "Bild zurück im Player, Wiedergabe läuft")
    }

    // MARK: AK-15 / EC-08 · Knöpfe des verwaisten Fensters nach „Zurück“

    /// Nach „Zurück“ ist das Systemfenster die einzige Steuerung (AK-15). Was bewirken „Schließen“ und
    /// „Zurück zur App“ dort? Beobachtet werden die Rate des verwaisten Players und die Segmentabrufe.
    private func orphan(_ tag: String, id: String, button: String) async throws {
        let nav = B07Nav()
        let w = stackWindow(nav)
        let ch = channel("QA Verwaist", "/livehls/\(id)/index.m3u8")
        nav.path = [ch]
        try await activate(w)
        guard let e = await waitPlaying({ self.lastEngine }) else { return XCTFail("spielt nicht") }
        weak let weakE: AVKitPlaybackEngine? = e
        weak let weakP: AVPlayer? = B07Engine.avPlayer(e)
        guard let win = await startPiP(w, e) else { return XCTFail("PiP startet nicht") }
        nav.path = []
        _ = await B07Engine.wait(3) { nav.path.isEmpty }
        await B07QA.spin(3)
        let segBefore = mock.segments(id, from: Date().addingTimeInterval(-3))
        B07QA.log("\(tag)|nach Zurück: engine=\(weakE != nil) rate=\(weakP?.rate ?? -1) pipfenster=\(B07PiPWindows.current().count) segmente(3s)=\(segBefore)")
        let out = try await pipAX(win, "press", button)
        let t0 = Date()
        await B07QA.spin(2)
        let winsAfter = B07PiPWindows.current().count
        let from = Date()
        await B07QA.spin(8)
        let segAfter = mock.segments(id, from: from)
        let rateAfter = weakP?.rate ?? -1
        let open = mock.openConnections(containing: "/livehls/\(id)/").count
        B07QA.log("\(tag)|\(button): \(out.prefix(80))|2 s danach pipfenster=\(winsAfter)|10 s danach: engine=\(weakE != nil) aktiv=\(weakE?.isPictureInPictureActive ?? false) rate=\(rateAfter) segmente(8s)=\(segAfter) offeneVerbindungen=\(open) keyWindow='\(NSApp.keyWindow?.title ?? "-")' pfad=\(nav.path.count)|t=\(B07QA.f1(Date().timeIntervalSince(t0)))")
        B07QA.shot(w, "\(tag)-nach-\(button)-app")
        // Länger beobachten: Wie lange lebt die Wiedergabe ohne Fenster? Endet sie mit der nächsten Navigation?
        var lastRate = rateAfter
        var segLong = 0
        for i in 1...(longObserve / 5) {
            let f = Date()
            await B07QA.spin(5)
            let s = mock.segments(id, from: f)
            segLong += s
            lastRate = weakP?.rate ?? -1
            B07QA.log("\(tag)|+\(10 + i * 5) s nach \(button): engine=\(weakE != nil) rate=\(lastRate) segmente(5s)=\(s) pipfenster=\(B07PiPWindows.current().count)")
        }
        if longObserve > 0 {
            let chB = channel("QA Danach", "/livehls/\(id)b/index.m3u8")
            nav.path = [chB]
            _ = await B07Engine.wait(25) { B07Registry.engines.last(where: { $0 !== weakE })?.state == .playing }
            var f = Date()
            await B07QA.spin(6)
            B07QA.log("\(tag)|anderer Sender offen 6 s: alt engine=\(weakE != nil) rate=\(weakP?.rate ?? -1) segmente alt=\(mock.segments(id, from: f)) neu=\(mock.segments(id + "b", from: f))")
            nav.path = []
            _ = await B07Engine.wait(3) { nav.path.isEmpty }
            f = Date()
            await B07QA.spin(6)
            B07QA.log("\(tag)|wieder in der Liste 6 s: alt engine=\(weakE != nil) rate=\(weakP?.rate ?? -1) segmente alt=\(mock.segments(id, from: f)) neu=\(mock.segments(id + "b", from: f))")
            B07QA.log("\(tag)|Ergebnis: nach \(button) \(10 + longObserve) s ohne Fenster, rate zuletzt=\(lastRate), Segmente in \(longObserve) s=\(segLong)")
        }
        weakP?.pause(); weakE?.stopPictureInPicture()
        XCTExpectFailure("BUG-01 · Nach „Zurück“ bleibt eine Wiedergabe ohne Player (Systemfenster als einzige Steuerung)") {
            XCTAssertEqual(segAfter, 0, "nach \(button) lädt der verwaiste Stream nicht weiter")
            XCTAssertFalse(rateAfter > 0.5 && winsAfter == 0, "keine unsichtbar weiterlaufende Wiedergabe")
        }
    }

    private var longObserve = 0

    func testAK15d_NachZurueck_SchliessenImSystemfenster() async throws {
        longObserve = 20
        try await orphan("AK-15d", id: "o15c", button: "close")
    }

    func testAK15e_EC08_NachZurueck_ZurueckZurAppImSystemfenster() async throws {
        longObserve = 40
        try await orphan("AK-15e", id: "o15r", button: "restore")
    }

    // MARK: EC-09 · Bild-in-Bild im Vollbild des Players

    func testEC09_PiPImVollbild_PlatzhalterFuelltVollbild_VollbildBleibt() async throws {
        let c = channel("QA Vollbild", "/livehls/v09/index.m3u8")
        let w = playerWindow(c)
        try await activate(w)
        guard let e = await waitPlaying({ self.lastEngine }) else { return XCTFail("spielt nicht") }
        let bF = await press(w, .char("f"))
        let full = await B07Engine.wait(8) { w.styleMask.contains(.fullScreen) }
        await B07QA.spin(1.5)
        let bP = await press(w, .char("p"))
        let on = await B07Engine.wait(10) { e.isPictureInPictureActive && !B07PiPWindows.current().isEmpty }
        await B07QA.spin(2)
        let stillFull = w.styleMask.contains(.fullScreen)
        let frame = w.frame, screen = w.screen?.frame ?? .zero
        B07QA.log("EC-09|vollbild=\(full != nil)|pip aktiv=\(on != nil)|fenster weiter im Vollbild=\(stillFull) \(Int(frame.width))x\(Int(frame.height)) von \(Int(screen.width))x\(Int(screen.height))|pipfenster=\(B07PiPWindows.current())|beep=\(bF + bP)")
        B07QA.shot(w, "EC-09-pip-im-vollbild-platzhalter")
        _ = await press(w, .char("p"))
        let off = await B07Engine.wait(10) { !e.isPictureInPictureActive }
        await B07QA.spin(1)
        let fullAfter = w.styleMask.contains(.fullScreen)
        _ = await press(w, .char("f"))
        _ = await B07Engine.wait(8) { !w.styleMask.contains(.fullScreen) }
        B07QA.log("EC-09|P beendet=\(off != nil)|danach weiter Vollbild=\(fullAfter)|nach F: Vollbild=\(w.styleMask.contains(.fullScreen)) rate=\(B07Engine.avPlayer(e)?.rate ?? -1)")
        XCTAssertEqual(bF + bP, [])
        XCTAssertNotNil(full, "F schaltet ins Vollbild")
        XCTAssertNotNil(on, "Bild-in-Bild startet im Vollbild")
        XCTAssertTrue(stillFull, "am Vollbild ändert sich nichts")
        XCTAssertNotNil(off)
    }

    // MARK: AK-10 (macOS-Teil) · kein automatischer Start beim App-Wechsel

    func testAK10_Mac_KeinAutoStartBeimAppWechsel() async throws {
        let c = channel("QA App-Wechsel", "/livehls/m10/index.m3u8")
        let w = playerWindow(c)
        try await activate(w)
        guard let e = await waitPlaying({ self.lastEngine }) else { return XCTFail("spielt nicht") }
        let possible = B07Engine.pipController(e)?.isPictureInPicturePossible ?? false
        // App-Wechsel: Test-Host ausblenden (⌘H-gleich) – keine andere App wird aktiviert
        NSApp.hide(nil)
        let hidden = await B07Engine.wait(3) { NSApp.isHidden }
        await B07QA.spin(5)
        let wins = B07PiPWindows.current()
        let rate = B07Engine.avPlayer(e)?.rate ?? -1
        let from = Date().addingTimeInterval(-5)
        let segs = mock.segments("m10", from: from)
        B07QA.log("AK-10m|possible=\(possible)|ausgeblendet=\(hidden != nil) isActive=\(NSApp.isActive)|5 s danach: pip aktiv=\(e.isPictureInPictureActive) pipfenster=\(wins.count) rate=\(rate) segmente(5s)=\(segs)")
        NSApp.unhide(nil)
        _ = await B07Engine.wait(3) { !NSApp.isHidden }
        XCTAssertNotNil(hidden)
        XCTAssertTrue(possible, "Bild-in-Bild wäre möglich gewesen")
        XCTAssertFalse(e.isPictureInPictureActive, "macOS: kein automatischer Start")
        XCTAssertTrue(wins.isEmpty)
    }
}
