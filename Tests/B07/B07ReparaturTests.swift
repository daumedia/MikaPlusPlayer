import XCTest
import SwiftUI
import SwiftData
import AVFoundation
import AVKit
import AppKit
@testable import MikaPlusPlayer

/// B07 · Reparatur (sdd-build, Fehlerauftrag 2026-09-27): Nachweise für BUG-01 und BUG-03 am Mac.
/// Kein Ton: Medien ohne Tonspur (ffprobe-geprüft, `B07Media`), selbst erzeugte Engines vor dem Laden stumm, Streams
/// nur von 127.0.0.1 (`B07StreamServer` mit Anfrageprotokoll). Navigation im Test-Stapel (`NavigationStack(path:)`) und
/// in der echten `ContentView` (Playlists → Senderliste → Player), „Zurück“ über den Zurück-Knopf der Fenster-Toolbar.
@MainActor
final class B07ReparaturTests: B07TestCase {

    override func tearDown() async throws {
        DetachedPlayback.shared.stopAll()
        try await super.tearDown()
    }

    // MARK: Hilfen

    private func waitPlaying(_ tag: String, _ probe: @escaping () -> AVKitPlaybackEngine?) async -> AVKitPlaybackEngine? {
        guard await B07Engine.wait(25, { probe()?.state == .playing }) != nil, let e = probe() else {
            XCTFail("\(tag): Stream spielt nicht")
            return nil
        }
        _ = await B07Engine.wait(15) { B07Engine.pipController(e)?.isPictureInPicturePossible == true }
        return e
    }

    /// Bild-in-Bild über den Knopf im Player (Klick; ersatzweise Bedienungshilfen-Aktion).
    private func startPiP(_ w: NSWindow, _ e: AVKitPlaybackEngine, _ tag: String) async -> Bool {
        await showControls(w)
        guard let b = pipButton(w) else { XCTFail("\(tag): kein PiP-Knopf"); return false }
        B07UI.click(b, in: w)
        if await B07Engine.wait(4, { e.isPictureInPictureActive }) == nil, let b2 = pipButton(w) { B07UI.press(b2) }
        let ok = await B07Engine.wait(10) { e.isPictureInPictureActive && !B07PiPWindows.current().isEmpty }
        B07QA.log("\(tag)|PiP gestartet=\(ok != nil)|fenster=\(B07PiPWindows.current())")
        return ok != nil
    }

    /// „Zurück“ über den Knopf der Fenster-Toolbar, sonst über den Pfad.
    private func goBack(_ w: NSWindow, _ nav: B07Nav) async -> String {
        try? await activate(w)
        let back = B07UI.elements(w, includeFrame: true).first { e in
            guard B07UI.role(e) == "AXButton" else { return false }
            let l = B07UI.label(e).lowercased()
            return l.contains("zurück") || l.contains("back") || l.contains("chevron.left") || l.contains("chevron.backward")
        }
        if let back {
            B07UI.press(back)
            if await B07Engine.wait(3, { nav.path.isEmpty }) != nil { return "Zurück-Knopf" }
        }
        nav.path = []
        _ = await B07Engine.wait(3) { nav.path.isEmpty }
        return "Pfad geleert"
    }

    /// Anfragen eines Senders (Playlist und Segmente) ab `from`.
    private func requests(_ id: String, from: Date, to: Date = .distantFuture) -> [B07StreamServer.Request] {
        mock.requests.filter { $0.path.contains("/\(id)/") && $0.time >= from && $0.time <= to }
    }

    /// Anfragen je Sekunde ab `t0` – das Mock-Protokoll für den Bericht.
    private func perSecond(_ id: String, from t0: Date, seconds: Int) -> [Int] {
        (0..<seconds).map { s in
            requests(id, from: t0.addingTimeInterval(Double(s)), to: t0.addingTimeInterval(Double(s + 1))).count
        }
    }

    /// Sender A öffnen, Bild-in-Bild per Knopf, „Zurück“. Rückgabe: Engine A (schwach gehalten vom Aufrufer).
    private func openWithPiPAndGoBack(_ tag: String, id: String, nav: B07Nav, w: NSWindow) async throws -> AVKitPlaybackEngine? {
        let chA = channel("QA Sender A", "/livehls/\(id)/index.m3u8")
        nav.path = [chA]
        try await activate(w)
        guard let eA = await waitPlaying(tag, { self.lastEngine }) else { return nil }
        guard await startPiP(w, eA, tag) else { XCTFail("\(tag): PiP startet nicht"); return nil }
        let way = await goBack(w, nav)
        await B07QA.spin(1)
        B07QA.log("\(tag)|zurück via \(way)|übernommen=\(DetachedPlayback.shared.holds(eA))|\(B07Engine.detail(eA))|pipfenster=\(B07PiPWindows.current().count)")
        return eA
    }

    // MARK: BUG-01 · anderer Sender beendet das verwaiste Bild-in-Bild

    func testBUG01_ZurueckMitPiP_AndererSender_AltesEndetNieZweiStreams() async throws {
        let nav = B07Nav()
        let w = stackWindow(nav)
        guard let eAStrong = try await openWithPiPAndGoBack("BUG-01a", id: "r01a", nav: nav, w: w) else { return }
        weak let eA: AVKitPlaybackEngine? = eAStrong
        weak let playerA: AVPlayer? = B07Engine.avPlayer(eAStrong)
        _ = eAStrong   // ab hier nur noch schwach gehalten

        // Das verwaiste Fenster spielt weiter, bis etwas es beendet (B06 · BUG-02, Annahme 3).
        let tBack = Date()
        await B07QA.spin(6)
        let aWhileOrphan = requests("r01a", from: tBack).count
        let winsWhileOrphan = B07PiPWindows.current().count
        B07QA.log("BUG-01a|6 s nach Zurück: pipfenster=\(winsWhileOrphan) anfragenA=\(aWhileOrphan) rateA=\(playerA?.rate ?? -1) übernommen=\(eA.map { DetachedPlayback.shared.holds($0) } ?? false)")
        XCTAssertEqual(winsWhileOrphan, 1, "Bild-in-Bild läuft nach „Zurück“ im Fenster weiter")
        XCTAssertGreaterThan(aWhileOrphan, 0)

        // Anderer Sender
        let chB = channel("QA Sender B", "/livehls/r01b/index.m3u8")
        let tOpen = Date()
        nav.path = [chB]
        let eB = await waitPlaying("BUG-01a B", { B07Registry.engines.last(where: { $0 !== eA }) })
        let goneAfter = await B07Engine.wait(8) { B07PiPWindows.current().isEmpty }
        await B07QA.spin(12)
        let firstB = requests("r01b", from: tOpen).first?.time
        let aAfterB = firstB.map { requests("r01a", from: $0).count } ?? -1
        let aAfterOpen = requests("r01a", from: tOpen.addingTimeInterval(0.5)).count
        let protokollA = perSecond("r01a", from: tOpen.addingTimeInterval(-6), seconds: 20)
        let protokollB = perSecond("r01b", from: tOpen.addingTimeInterval(-6), seconds: 20)
        let both = zip(protokollA, protokollB).filter { $0 > 0 && $1 > 0 }.count
        B07QA.log("BUG-01a|Mock-Protokoll je Sekunde ab 6 s vor dem Öffnen von B|A=\(protokollA)|B=\(protokollB)")
        B07QA.log("BUG-01a|B geöffnet: altes Fenster weg nach \(goneAfter.map(B07QA.f1) ?? "-")s|anfragenA nach erster Anfrage von B=\(aAfterB)|anfragenA ab 0,5 s nach dem Öffnen=\(aAfterOpen)|Sekunden mit Anfragen an A und B=\(both)|engineA frei=\(eA == nil)|rateA=\(playerA?.rate ?? -1)|B=\(eB.map(B07Engine.detail) ?? "-")|übernommen=\(DetachedPlayback.shared.engines.count)")
        B07QA.shot(w, "BUILD-BUG-01-neuer-sender-app-mac")
        XCTAssertNotNil(eB, "B spielt")
        XCTAssertNotNil(goneAfter, "das alte Bild-in-Bild-Fenster schließt, sobald B öffnet")
        XCTAssertEqual(aAfterB, 0, "nach der ersten Anfrage von B keine Anfrage mehr an A")
        XCTAssertEqual(aAfterOpen, 0, "A lädt nach dem Öffnen von B nicht weiter")
        XCTAssertEqual(both, 0, "keine Sekunde mit zwei Streams")
        XCTAssertTrue(DetachedPlayback.shared.engines.isEmpty)
        XCTAssertNil(playerA?.currentItem, "Element von A freigegeben")

        // B verlassen (ohne Bild-in-Bild) → danach keine Anfragen mehr an A oder B
        _ = await goBack(w, nav)
        let tEnd = Date()
        await B07QA.spin(8)
        let rest = requests("r01a", from: tEnd.addingTimeInterval(1)).count + requests("r01b", from: tEnd.addingTimeInterval(1)).count
        B07QA.log("BUG-01a|B verlassen: Anfragen A+B 1–8 s danach=\(rest)|pipfenster=\(B07PiPWindows.current().count)")
        XCTAssertEqual(rest, 0, "nach dem Ende 0 Anfragen")
    }

    // MARK: BUG-01 · dasselbe in der echten Oberfläche (ContentView → Playlist → Sender)

    private func openInApp(_ w: NSWindow, _ name: String, expectTitle: String) async -> Bool {
        for attempt in 0..<3 {
            try? await activate(w)
            let el = B07UI.elements(w).first { B07UI.label($0).contains(name) && B07UI.role($0) != "AXWindow" && B07UI.frame($0).width > 10 }
            guard let el else { await B07QA.spin(1); continue }
            if attempt == 0 { B07UI.press(el) } else { B07UI.click(el, in: w) }
            if await B07Engine.wait(4, { w.title == expectTitle }) != nil { return true }
        }
        return false
    }

    private func backInApp(_ w: NSWindow, expectTitle: String) async -> Bool {
        try? await activate(w)
        guard let b = B07UI.elements(w, includeFrame: true).first(where: {
            B07UI.role($0) == "AXButton" && (B07UI.label($0).contains("chevron.backward") || B07UI.label($0).contains("Back") || B07UI.label($0).contains("Zurück"))
        }) else { return false }
        B07UI.press(b)
        if await B07Engine.wait(4, { w.title == expectTitle }) != nil { return true }
        B07UI.click(b, in: w)
        return await B07Engine.wait(4, { w.title == expectTitle }) != nil
    }

    func testBUG01_EchteOberflaeche_ZurueckMitPiP_AndererSender_AltesEndet() async throws {
        let session = MultiviewSession()
        let chA = channel("QA Sender A", "/livehls/r01e/index.m3u8")
        let chB = channel("QA Sender B", "/livehls/r01f/index.m3u8")
        playlist.channelCount = 2
        try container.mainContext.save()
        let w = B07UI.window(ContentView().environment(session).modelContainer(container),
                             size: CGSize(width: 900, height: 600), title: "B07-BUILD App")
        windows.append(w)
        try await activate(w)
        await B07QA.spin(1.5)
        guard await openInApp(w, "QA M3U", expectTitle: "QA M3U"),
              await openInApp(w, chA.name, expectTitle: chA.name) else { return XCTFail("Sender A nicht geöffnet") }
        guard let eAStrong = await waitPlaying("BUG-01d", { self.lastEngine }) else { return }
        weak let eA: AVKitPlaybackEngine? = eAStrong
        weak let playerA: AVPlayer? = B07Engine.avPlayer(eAStrong)
        guard await startPiP(w, eAStrong, "BUG-01d") else { return XCTFail("PiP startet nicht") }
        let backOK = await backInApp(w, expectTitle: "QA M3U")
        XCTAssertTrue(backOK, "Zurück zur Senderliste")
        await B07QA.spin(1.5)
        let held = eA.map { DetachedPlayback.shared.holds($0) } ?? false
        B07QA.log("BUG-01d|nach Zurück: übernommen=\(held)|pipfenster=\(B07PiPWindows.current().count)|\(eA.map(B07Engine.detail) ?? "-")")
        XCTAssertTrue(held, "DetachedPlayback hält die Wiedergabe im schwebenden Fenster")
        await B07QA.spin(4)
        let tOpen = Date()
        guard await openInApp(w, chB.name, expectTitle: chB.name) else { return XCTFail("Sender B nicht geöffnet") }
        let playingB = await B07Engine.wait(25) { B07Registry.engines.last(where: { $0 !== eA })?.state == .playing }
        let gone = await B07Engine.wait(8) { B07PiPWindows.current().isEmpty }
        await B07QA.spin(10)
        let firstB = requests("r01f", from: tOpen).first?.time
        let aAfterB = firstB.map { requests("r01e", from: $0).count } ?? -1
        let pa = perSecond("r01e", from: tOpen.addingTimeInterval(-4), seconds: 16)
        let pb = perSecond("r01f", from: tOpen.addingTimeInterval(-4), seconds: 16)
        let both = zip(pa, pb).filter { $0 > 0 && $1 > 0 }.count
        B07QA.log("BUG-01d|Mock-Protokoll je Sekunde ab 4 s vor dem Öffnen von B|A=\(pa)|B=\(pb)")
        B07QA.log("BUG-01d|B spielt=\(playingB != nil)|altes Fenster weg nach \(gone.map(B07QA.f1) ?? "-")s|anfragenA nach erster Anfrage von B=\(aAfterB)|Sekunden mit A und B=\(both)|rateA=\(playerA?.rate ?? -1)|übernommen=\(DetachedPlayback.shared.engines.count)")
        B07QA.shot(w, "BUILD-BUG-01-echte-oberflaeche-sender-b")
        XCTAssertNotNil(playingB)
        XCTAssertNotNil(gone, "altes Bild-in-Bild-Fenster schließt")
        XCTAssertEqual(aAfterB, 0, "keine Anfrage an A nach der ersten Anfrage von B")
        XCTAssertEqual(both, 0, "nie zwei Streams zugleich")
        B07UI.close(w); windows.removeAll()
        await B07QA.spin(1)
        session.clear()
    }

    /// Gegenprobe zur Erkennung über den sichtbaren Tab: In der echten Oberfläche pausiert ein Tabwechsel nur
    /// (B06 AK-27, dieselbe Engine), „Zurück“ aus der Senderliste beendet die Wiedergabe (B06 BUG-02).
    func testBUG01_EchteOberflaeche_TabwechselPausiert_ZurueckBeendet() async throws {
        let session = MultiviewSession()
        let ch = channel("QA Sender T", "/livehls/r01t/index.m3u8")
        playlist.channelCount = 1
        try container.mainContext.save()
        let w = B07UI.window(ContentView().environment(session).modelContainer(container),
                             size: CGSize(width: 900, height: 600), title: "B07-BUILD Tabs")
        windows.append(w)
        try await activate(w)
        await B07QA.spin(1.5)
        guard await openInApp(w, "QA M3U", expectTitle: "QA M3U"),
              await openInApp(w, ch.name, expectTitle: ch.name) else { return XCTFail("Sender nicht geöffnet") }
        guard let e = await waitPlaying("BUG-01t", { self.lastEngine }), let player = B07Engine.avPlayer(e) else { return }
        func tab(_ name: String) -> NSObject? {
            B07UI.elements(w, includeFrame: true).first { B07UI.label($0).contains(name) && ["AXRadioButton", "AXButton", "AXTab"].contains(B07UI.role($0)) }
        }
        guard let fav = tab("Favoriten") else { return XCTFail("kein Favoriten-Tab") }
        B07UI.press(fav)
        _ = await B07Engine.wait(4) { w.title == "Favoriten" }
        await B07QA.spin(1.5)
        let tabSwitch = "titel=\(w.title)|isPaused=\(e.isPaused)|rate=\(player.rate)|element=\(player.currentItem != nil)"
        XCTAssertTrue(e.isPaused, "Tabwechsel pausiert")
        XCTAssertNotNil(player.currentItem, "Tabwechsel beendet nicht (dieselbe Engine setzt fort)")
        guard let pl = tab("Playlists") else { return XCTFail("kein Playlists-Tab") }
        B07UI.press(pl)
        _ = await B07Engine.wait(4) { w.title == ch.name }
        let resumed = await B07Engine.wait(6) { player.rate > 0.5 }
        XCTAssertNotNil(resumed, "zurück im Tab: dieselbe Engine spielt weiter")
        let backOK = await backInApp(w, expectTitle: "QA M3U")
        let tBack = Date()
        await B07QA.spin(6)
        let after = requests("r01t", from: tBack.addingTimeInterval(1)).count
        B07QA.log("BUG-01t|Tabwechsel: \(tabSwitch)|Rückkehr spielt nach \(resumed.map(B07QA.f1) ?? "-")s|Zurück=\(backOK): element=\(player.currentItem != nil) rate=\(player.rate) anfragen 1–6 s danach=\(after)")
        XCTAssertTrue(backOK)
        XCTAssertNil(player.currentItem, "„Zurück“ aus der Senderliste beendet die Wiedergabe")
        XCTAssertEqual(after, 0, "nach „Zurück“ 0 Anfragen")
        B07UI.close(w); windows.removeAll()
        await B07QA.spin(1)
        session.clear()
    }

    // MARK: BUG-01 · Beenden aus der App wirkt auch ohne Player

    func testBUG01_BeendenOhnePlayer_FensterZuNullAnfragen() async throws {
        let nav = B07Nav()
        let w = stackWindow(nav)
        guard let eAStrong = try await openWithPiPAndGoBack("BUG-01b", id: "r01c", nav: nav, w: w) else { return }
        weak let eA: AVKitPlaybackEngine? = eAStrong
        weak let playerA: AVPlayer? = B07Engine.avPlayer(eAStrong)
        await B07QA.spin(3)
        XCTAssertEqual(B07PiPWindows.current().count, 1)
        // Der Aufruf, der vor der Reparatur wirkungslos blieb (QA 1 AK-15: Fenster blieb)
        let tStop = Date()
        eAStrong.stopPictureInPicture()
        let gone = await B07Engine.wait(8) { B07PiPWindows.current().isEmpty }
        let inactive = await B07Engine.wait(3) { !(eA?.isPictureInPictureActive ?? false) }
        let released = await B07Engine.wait(3) { DetachedPlayback.shared.engines.isEmpty }
        await B07QA.spin(8)
        let after = requests("r01c", from: tStop.addingTimeInterval(1)).count
        B07QA.log("BUG-01b|stopPictureInPicture() ohne Player: fenster weg nach \(gone.map(B07QA.f1) ?? "-")s|inaktiv nach \(inactive.map(B07QA.f1) ?? "-")s|übernommen leer nach \(released.map(B07QA.f1) ?? "-")s|anfragen 1–9 s danach=\(after)|rate=\(playerA?.rate ?? -1)|element=\(playerA?.currentItem != nil)|protokoll=\(perSecond("r01c", from: tStop.addingTimeInterval(-3), seconds: 12))")
        XCTAssertNotNil(gone, "Fenster schließt")
        XCTAssertNotNil(inactive)
        XCTAssertNotNil(released, "DetachedPlayback beendet die Wiedergabe mit dem Ende von Bild-in-Bild")
        XCTAssertEqual(after, 0, "nach dem Ende 0 Anfragen")
        XCTAssertNil(playerA?.currentItem)
    }

    // MARK: BUG-01 · „Zurück zur App“: mit Player wiederherstellen, ohne Player beenden

    func testBUG01_ZurueckZurApp_MitPlayerWiederherstellen_OhnePlayerBeenden() async throws {
        let nav = B07Nav()
        let w = stackWindow(nav)
        let ch = channel("QA Restore", "/livehls/r01d/index.m3u8")
        nav.path = [ch]
        try await activate(w)
        guard let e = await waitPlaying("BUG-01c", { self.lastEngine }) else { return }
        guard await startPiP(w, e, "BUG-01c") else { return XCTFail("PiP startet nicht") }
        guard let controller = B07Engine.pipController(e),
              let delegate = controller.delegate else { return XCTFail("kein Controller/Delegate") }
        func restore() async -> Bool? {
            let result = RestoreAnswer()
            Self.askRestore(delegate, controller) { result.value = $0 }
            _ = await B07Engine.wait(2) { result.value != nil }
            return result.value
        }
        let withPlayer = await restore()
        _ = await goBack(w, nav)
        await B07QA.spin(1)
        let detached = DetachedPlayback.shared.holds(e)
        let withoutPlayer = await restore()
        B07QA.log("BUG-01c|restoreUserInterface… mit offenem Player=\(withPlayer.map(String.init) ?? "-")|nach Zurück (übernommen=\(detached))=\(withoutPlayer.map(String.init) ?? "-")")
        XCTAssertEqual(withPlayer, true, "offener Player: das System holt das Bild zurück")
        XCTAssertTrue(detached)
        XCTAssertEqual(withoutPlayer, false, "ohne Player: kein Wiederherstellen, Bild-in-Bild endet")
    }

    /// Ruft den Delegate so auf, wie das System es bei „Zurück zur App“ tut (synchron, mit Rückruf).
    private static func askRestore(_ delegate: AVPictureInPictureControllerDelegate, _ controller: AVPictureInPictureController,
                                   _ done: @escaping @Sendable (Bool) -> Void) {
        delegate.pictureInPictureController?(controller, restoreUserInterfaceForPictureInPictureStopWithCompletionHandler: done)
    }

    /// Antwort des Delegates (der Rückruf ist `@Sendable`).
    private final class RestoreAnswer: @unchecked Sendable {
        var value: Bool?
    }

    // MARK: BUG-03 · isPaused folgt dem Player

    func testBUG03_SystemHaeltAnUndSetztFort_IsPausedFolgt() async throws {
        let url = mock.url("/livehls/r03/index.m3u8")
        let e = mutedEngine(for: url)
        guard let avk = e as? AVKitPlaybackEngine else { return XCTFail("keine AVKit-Engine") }
        let w = B07UI.window(avk.makePlayerView(), title: "B07-BUILD BUG-03")
        windows.append(w)
        e.load(url)
        guard await B07Engine.wait(25, { e.state == .playing }) != nil, let player = B07Engine.avPlayer(e) else { return XCTFail("spielt nicht") }
        _ = await B07Engine.wait(10) { player.rate > 0.5 }
        XCTAssertFalse(e.isPaused)
        // Pause ohne die App (so hält das System den Player an: Pause-Knopf im Fenster, zweites Bild-in-Bild, Schließen)
        player.pause()
        let followedPause = await B07Engine.wait(2) { e.isPaused }
        // Fortsetzen ohne die App (Play-Knopf im Fenster)
        player.play()
        let followedPlay = await B07Engine.wait(2) { !e.isPaused }
        // Erneut von außen angehalten → der erste Druck setzt fort
        player.pause()
        _ = await B07Engine.wait(2) { e.isPaused }
        e.togglePlayPause()
        let resumed = await B07Engine.wait(3) { player.rate > 0.5 }
        B07QA.log("BUG-03|Pause von außen → isPaused nach \(followedPause.map(B07QA.f2) ?? "-")s|Play von außen → nach \(followedPlay.map(B07QA.f2) ?? "-")s|erster Druck setzt fort nach \(resumed.map(B07QA.f2) ?? "-")s|\(B07Engine.detail(e))")
        XCTAssertNotNil(followedPause, "Pause durch das System wird angezeigt")
        XCTAssertNotNil(followedPlay, "Fortsetzen durch das System wird angezeigt")
        XCTAssertNotNil(resumed, "erster Druck setzt fort")
        XCTAssertFalse(e.isPaused)
    }
}
