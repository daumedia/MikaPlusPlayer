import XCTest
import SwiftUI
import SwiftData
import AVFoundation
import AVKit
import AppKit
@testable import MikaPlusPlayer

/// B07 · Verlassen des Players und Zustand in der App (AK-13, AK-15, AK-16, AK-17, EC-03, EC-10) – macOS.
/// Navigation wie in der App (`NavigationStack(path:)` mit `navigationDestination`), „Zurück“ über den echten
/// Zurück-Knopf der Fenster-Toolbar (Bedienungshilfen-Aktion bzw. Klick), sonst über den Pfad.
@MainActor
final class B07VerlassenTests: B07TestCase {

    // MARK: Hilfen

    private func waitPlaying(_ tag: String, _ probe: @escaping () -> AVKitPlaybackEngine?) async -> AVKitPlaybackEngine? {
        let ok = await B07Engine.wait(25) { probe()?.state == .playing }
        if ok == nil { XCTFail("\(tag): Stream spielt nicht"); return nil }
        guard let e = probe() else { return nil }
        _ = await B07Engine.wait(15) { B07Engine.pipController(e)?.isPictureInPicturePossible == true }
        return e
    }

    /// Startet Bild-in-Bild über den Knopf im Player (Klick; ersatzweise Bedienungshilfen-Aktion).
    private func startPiPViaButton(_ w: NSWindow, _ e: AVKitPlaybackEngine, _ tag: String) async -> Bool {
        await showControls(w)
        guard let b = pipButton(w) else { XCTFail("\(tag): kein PiP-Knopf"); return false }
        B07UI.click(b, in: w)
        if await B07Engine.wait(4, { e.isPictureInPictureActive }) == nil, let b2 = pipButton(w) { B07UI.press(b2) }
        let ok = await B07Engine.wait(10) { e.isPictureInPictureActive && !B07PiPWindows.current().isEmpty }
        B07QA.log("\(tag)|PiP gestartet=\(ok != nil)|fenster=\(B07PiPWindows.current())")
        return ok != nil
    }

    /// „Zurück“ über den Knopf der Fenster-Toolbar; Rückgabe: benutzter Weg.
    private func goBack(_ w: NSWindow, _ nav: B07Nav) async -> String {
        try? await activate(w)
        let candidates = B07UI.elements(w, includeFrame: true).filter { e in
            guard B07UI.role(e) == "AXButton" else { return false }
            let l = B07UI.label(e).lowercased()
            return l.contains("zurück") || l.contains("back") || l.contains("chevron.left") || l.contains("chevron.backward")
        }
        if let b = candidates.first {
            let label = B07UI.label(b)
            let ok = B07UI.press(b)
            if await B07Engine.wait(3, { nav.path.isEmpty }) != nil { return "Zurück-Knopf (AXPress '\(label)', \(ok))" }
            B07UI.click(b, in: w)
            if await B07Engine.wait(3, { nav.path.isEmpty }) != nil { return "Zurück-Knopf (Klick '\(label)')" }
        }
        nav.path = []
        _ = await B07Engine.wait(3) { nav.path.isEmpty }
        return "Pfad geleert (kein Zurück-Knopf gefunden: \(B07UI.elements(w, includeFrame: true).filter { B07UI.role($0) == "AXButton" }.map(B07UI.label)))"
    }

    private func playPauseLabel(_ w: NSWindow) -> String {
        B07UI.elements(w).first { B07UI.role($0) == "AXButton" && (B07UI.label($0).contains("pause.fill") || B07UI.label($0).contains("play.fill")) }
            .map(B07UI.label) ?? "-"
    }

    // MARK: AK-13

    func testAK13_OhnePiP_ZurueckUndTabwechselPausieren() async throws {
        let nav = B07Nav()
        let w = stackWindow(nav, tabs: true)
        let c = channel("QA Zurück", "/livehls/ak13/index.m3u8")
        nav.path = [c]
        guard let e = await waitPlaying("AK-13", { self.lastEngine }) else { return }
        XCTAssertFalse(e.isPictureInPictureActive)
        let way = await goBack(w, nav)
        await B07QA.spin(1)
        let rate = B07Engine.avPlayer(e)?.rate ?? -1
        B07QA.log("AK-13|zurück via \(way)|\(B07Engine.detail(e))")
        XCTAssertTrue(e.isPaused, "Zurück pausiert")
        XCTAssertEqual(rate, 0, "Wiedergabe steht")

        // Tabwechsel (anderer Sender → sicher eine neue Engine)
        let c2 = channel("QA Tab", "/livehls/ak13b/index.m3u8")
        nav.path = [c2]
        guard let e2 = await waitPlaying("AK-13b", { B07Registry.engines.last(where: { $0 !== e }) }) else { return }
        XCTAssertFalse(e2.isPaused)
        nav.tab = 1
        await B07QA.spin(1.5)
        B07QA.log("AK-13|Tabwechsel|\(B07Engine.detail(e2))|gleiche Engine=\(e2 === e)")
        XCTAssertTrue(e2.isPaused, "Tabwechsel pausiert")
        nav.tab = 0
        await B07QA.spin(1.5)
        B07QA.log("AK-13|zurück im Tab|\(B07Engine.detail(e2))")
        XCTAssertFalse(e2.isPaused, "Rückkehr in den Tab setzt fort (onAppear → play)")
    }

    // MARK: AK-15 (macOS) · Verlassen mit aktivem Bild-in-Bild

    /// Gemeinsamer Ablauf: Sender A öffnen, Bild-in-Bild per Knopf, „Zurück“, 15 s beobachten (nach 10 s der einzige
    /// Beenden-Aufruf, den die App kennt), dann `next` öffnen und bis `observe` Sekunden beobachten.
    private func runAK15(_ tag: String, idA: String, next: (B07Nav, Channel) -> Channel, observe: TimeInterval) async throws {
        let nav = B07Nav()
        let w = stackWindow(nav)
        let chA = channel("QA Sender A", "/livehls/\(idA)/index.m3u8")
        nav.path = [chA]
        try await activate(w)
        guard let eA = await waitPlaying(tag, { self.lastEngine }) else { return }
        weak let weakA: AVKitPlaybackEngine? = eA
        weak let weakPlayerA: AVPlayer? = B07Engine.avPlayer(eA)
        guard await startPiPViaButton(w, eA, tag) else { return XCTFail("\(tag): PiP startet nicht") }
        let way = await goBack(w, nav)
        let tBack = Date()
        await B07QA.spin(1.5)
        B07QA.log("\(tag)|zurück via \(way)|engineA lebt=\(weakA != nil)|\(weakA.map(B07Engine.detail) ?? "-")")
        B07QA.shot(w, "\(tag)-nach-zurueck-app-mac")
        if let pw = B07PiPWindows.current().first { await B07QA.requestWindowShot(pw.id, "\(tag)-nach-zurueck-pip-fenster-mac") }
        let beepP = await press(w, .char("p"))
        B07QA.log("\(tag)|P in der Liste → unbehandelt=\(beepP)|pipfenster=\(B07PiPWindows.current().count)")

        var stillPlaying = true
        for i in 1...3 {
            let from = Date()
            await B07QA.spin(5)
            let segs = mock.segments(idA, from: from)
            let wins = B07PiPWindows.current().count
            let rate = weakPlayerA?.rate ?? -1
            B07QA.log("\(tag)|t=\(B07QA.f1(Date().timeIntervalSince(tBack)))s pipfenster=\(wins) engineA=\(weakA != nil) aktiv=\(weakA?.isPictureInPictureActive ?? false) rate=\(rate) segmente(5s)=\(segs) pipKnopfInApp=\(pipButton(w) != nil)")
            if wins == 0 || rate < 0.5 || segs == 0 { stillPlaying = false }
            if i == 2 {
                weakA?.stopPictureInPicture()
                B07QA.log("\(tag)|stopPictureInPicture() an der verwaisten Engine (engine lebt=\(weakA != nil))")
            }
        }
        let pipWindowsAfterStop = B07PiPWindows.current().count
        let appHasControl = pipButton(w) != nil

        let chB = next(nav, chA)
        let idB = chB.streamURL.pathComponents.dropLast().last ?? idA
        let tOpen = Date()
        nav.path = [chB]
        let eB = await waitPlaying(tag + "b", { B07Registry.engines.last(where: { $0 !== weakA }) })
        var maxOverlap = 0
        var goneAt: TimeInterval?
        var lastA = Date()
        while Date().timeIntervalSince(tOpen) < observe {
            let from = Date()
            await B07QA.spin(3)
            let sA = idB == idA ? -1 : mock.segments(idA, from: from)
            let sB = mock.segments(idB, from: from)
            let wins = B07PiPWindows.current().count
            if weakA != nil && (weakPlayerA?.rate ?? 0) > 0.5 && wins > 0 { lastA = Date() }
            if goneAt == nil && wins == 0 { goneAt = Date().timeIntervalSince(tOpen) }
            if weakA != nil && (weakPlayerA?.rate ?? 0) > 0.5 && (eB.map { B07Engine.avPlayer($0)?.rate ?? 0 } ?? 0) > 0.5 { maxOverlap += 3 }
            B07QA.log("\(tag)|nach Öffnen t=\(B07QA.f1(Date().timeIntervalSince(tOpen)))s|pipfenster=\(wins) engineA=\(weakA != nil) rateA=\(weakPlayerA?.rate ?? -1) playerA=\(weakPlayerA != nil)|segmente(3s) A=\(sA) B=\(sB)|B: \(eB.map(B07Engine.detail) ?? "-")")
            if goneAt != nil && weakA == nil && Date().timeIntervalSince(tOpen) > 8 { break }
        }
        B07QA.shot(w, "\(tag)-neuer-sender-app-mac")
        B07QA.log("\(tag)|Ergebnis: weiterlaufend nach Zurück=\(stillPlaying) pipKnopfInApp=\(appHasControl) fensterNachStopp=\(pipWindowsAfterStop) gleichzeitig≈\(maxOverlap)s altesFensterWeg=\(goneAt.map(B07QA.f1) ?? "nein (bis \(Int(observe)) s)") engineA frei=\(weakA == nil) letzteParalleleWiedergabe=\(B07QA.f1(lastA.timeIntervalSince(tOpen)))s")
        if weakA != nil {
            // Aufräumen: Fenster schließen (danach soll nichts weiterlaufen)
            weakA?.stopPictureInPicture(); weakPlayerA?.pause()
        }
        // Behoben (BUG-01, 2026-09-27): Beenden aus der App wirkt auch ohne Player, keine zwei Streams.
        XCTAssertFalse(stillPlaying && !appHasControl, "keine Wiedergabe, die die App nicht mehr steuern kann")
        XCTAssertEqual(pipWindowsAfterStop, 0, "Beenden aus der App wirkt")
        XCTAssertEqual(maxOverlap, 0, "keine zwei Streams gleichzeitig")
    }

    func testAK15a_Mac_ZurueckMitPiP_DenselbenSenderErneutOeffnen() async throws {
        try await runAK15("AK-15a", idA: "a15", next: { _, a in a }, observe: 40)
    }

    func testAK15b_Mac_ZurueckMitPiP_AnderenSenderOeffnen() async throws {
        try await runAK15("AK-15b", idA: "c15", next: { _, _ in self.channel("QA Sender B", "/livehls/d15/index.m3u8") }, observe: 60)
    }

    // MARK: AK-16 · Pause im schwebenden Fenster

    func testAK16_PauseImPiPFenster_AppZeigtAngehalten_ErsterDruckSetztFort() async throws {
        let c = channel("QA Pause", "/livehls/ak16/index.m3u8")
        let w = playerWindow(c)
        try await activate(w)
        guard let e = await waitPlaying("AK-16", { self.lastEngine }) else { return }
        guard await startPiPViaButton(w, e, "AK-16") else { return }
        let player = B07Engine.avPlayer(e)
        // Pause-Knopf des Systemfensters: setzt die Rate des AVPlayer auf 0 (wie AVKit es tut)
        player?.pause()
        await B07QA.spin(1)
        await showControls(w)
        let label0 = playPauseLabel(w)
        B07QA.log("AK-16|nach Pause im Fenster: rate=\(player?.rate ?? -1) isPaused(App)=\(e.isPaused) knopf='\(label0)'")
        B07QA.shot(w, "AK-16-pause-im-fenster-app-zeigt-pause-knopf")
        // Leertaste 1
        let b1 = await press(w, .space)
        await B07QA.spin(1)
        let r1 = player?.rate ?? -1
        let label1 = playPauseLabel(w)
        // Leertaste 2
        let b2 = await press(w, .space)
        await B07QA.spin(1.5)
        let r2 = player?.rate ?? -1
        B07QA.log("AK-16|Leertaste 1 → rate=\(r1) knopf='\(label1)' | Leertaste 2 → rate=\(r2) knopf='\(playPauseLabel(w))'|beep=\(b1 + b2)")
        XCTAssertEqual(b1 + b2, [])
        B07QA.log("AK-16|Befund: knopf='\(label0)' ersterDruckRate=\(r1) zweiterDruckRate=\(r2)")
        // Behoben (BUG-03, 2026-09-27): Die App folgt der Pause im Fenster, der erste Druck setzt fort.
        XCTAssertTrue(label0.contains("play.fill"), "Knopf zeigt nach Pause im Fenster „Abspielen“")
        XCTAssertEqual(r1, 1, accuracy: 0.01, "erster Druck setzt fort")
    }

    // MARK: AK-17 / EC-10 · Zweites Bild-in-Bild

    func testAK17_EC10_ZweiterPlayerStartetPiP_ErsterPausiertUndZeigtEs() async throws {
        let c1 = channel("QA Eins", "/livehls/a17/index.m3u8")
        let c2 = channel("QA Zwei", "/livehls/b17/index.m3u8")
        let w1 = playerWindow(c1, origin: CGPoint(x: 60, y: 120), size: CGSize(width: 560, height: 360))
        try await activate(w1)
        guard let e1 = await waitPlaying("AK-17a", { self.lastEngine }) else { return }
        let w2 = playerWindow(c2, origin: CGPoint(x: 660, y: 120), size: CGSize(width: 560, height: 360))
        try await activate(w2)
        guard let e2 = await waitPlaying("AK-17b", { B07Registry.engines.last(where: { $0 !== e1 }) }) else { return }
        guard await startPiPViaButton(w1, e1, "AK-17-1") else { return }
        let win1 = B07PiPWindows.current()
        try await activate(w2)
        guard await startPiPViaButton(w2, e2, "AK-17-2") else { return }
        await B07QA.spin(3)
        await showControls(w1)
        let label1 = playPauseLabel(w1)
        let wins = B07PiPWindows.current()
        B07QA.log("AK-17|fenster vorher=\(win1.map(\.id)) nachher=\(wins.map(\.id))|1: \(B07Engine.detail(e1)) knopf='\(label1)'|2: \(B07Engine.detail(e2))")
        B07QA.shot(w1, "AK-17-erster-player-zeigt-pause-knopf")
        XCTAssertEqual(wins.count, 1, "immer nur ein schwebendes Fenster")
        XCTAssertFalse(e1.isPictureInPictureActive, "Fenster des ersten geschlossen")
        XCTAssertTrue(e2.isPictureInPictureActive, "der zuletzt gestartete gewinnt")
        XCTAssertEqual(B07Engine.avPlayer(e1)?.rate ?? -1, 0, "Stream des ersten pausiert (Systemverhalten)")
        B07QA.log("AK-17|Befund: erster isPaused(App)=\(e1.isPaused) rate=\(B07Engine.avPlayer(e1)?.rate ?? -1) knopf='\(label1)'")
        // Behoben (BUG-03, 2026-09-27): Anzeige und Wiedergabe des ersten Players stimmen überein.
        XCTAssertTrue(e1.isPaused || (B07Engine.avPlayer(e1)?.rate ?? 0) > 0.5, "Anzeige und Wiedergabe stimmen überein")
        XCTAssertTrue(label1.contains("play.fill"), "Knopf des ersten zeigt „Abspielen“")
    }

    // MARK: EC-03 · Tabwechsel bei aktivem Bild-in-Bild

    func testEC03_TabwechselMitPiP_KeinePause_EngineBleibt() async throws {
        let nav = B07Nav()
        let w = stackWindow(nav, tabs: true)
        let c = channel("QA Tab", "/livehls/ec03/index.m3u8")
        nav.path = [c]
        try await activate(w)
        guard let e = await waitPlaying("EC-03", { self.lastEngine }) else { return }
        guard await startPiPViaButton(w, e, "EC-03") else { return }
        weak let weakE: AVKitPlaybackEngine? = e
        nav.tab = 1
        await B07QA.spin(4)
        let during = "engine=\(weakE != nil) \(weakE.map(B07Engine.detail) ?? "-") pipfenster=\(B07PiPWindows.current().count)"
        B07QA.log("EC-03|Favoriten-Tab 4 s: \(during)")
        XCTAssertNotNil(weakE, "Stapel des Tabs bleibt, Engine lebt")
        XCTAssertEqual(weakE?.isPaused, false, "keine Pause")
        XCTAssertEqual(B07PiPWindows.current().count, 1)
        nav.tab = 0
        await B07QA.spin(2)
        B07QA.log("EC-03|zurück im Tab: \(weakE.map(B07Engine.detail) ?? "-")|pipfenster=\(B07PiPWindows.current().count)|gleiche Engine=\(B07Registry.engines.last === weakE)")
        XCTAssertTrue(weakE?.isPictureInPictureActive ?? false)
    }
}
