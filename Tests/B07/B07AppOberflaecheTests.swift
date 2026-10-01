import XCTest
import SwiftUI
import SwiftData
import AVFoundation
import AVKit
import AppKit
@testable import MikaPlusPlayer

/// B07 · AK-15 in der **echten** App-Oberfläche (`ContentView` → `PlaylistsView` → `ChannelListView` → `PlayerView`),
/// bedient per Bedienungshilfen-Aktion bzw. Klick: Sender öffnen, Bild-in-Bild per Knopf, „Zurück“ über die Toolbar,
/// anderen Sender öffnen, danach zurück bis zur Übersicht. In-Memory-Datenbank, Streams von 127.0.0.1, ohne Tonspur.
@MainActor
final class B07AppOberflaecheTests: B07TestCase {

    private func open(_ w: NSWindow, _ name: String, expectTitle: String) async -> String {
        for attempt in 0..<3 {
            try? await activate(w)
            let el = B07UI.elements(w).first { B07UI.label($0).contains(name) && B07UI.role($0) != "AXWindow" && B07UI.frame($0).width > 10 }
            guard let el else { await B07QA.spin(1); continue }
            if attempt == 0 { B07UI.press(el) } else { B07UI.click(el, in: w) }
            if await B07Engine.wait(4, { w.title == expectTitle }) != nil { return attempt == 0 ? "AXPress" : "Klick" }
        }
        return "nicht geöffnet (Titel '\(w.title)', Elemente: \(B07UI.elements(w).map { "\(B07UI.role($0)):\(B07UI.label($0))" }.filter { $0.count > 8 }.prefix(25)))"
    }

    private func back(_ w: NSWindow, expectTitle: String) async -> String {
        try? await activate(w)
        let b = B07UI.elements(w, includeFrame: true).first { B07UI.role($0) == "AXButton" && (B07UI.label($0).contains("chevron.backward") || B07UI.label($0).contains("Back") || B07UI.label($0).contains("Zurück")) }
        guard let b else { return "kein Zurück-Knopf" }
        B07UI.press(b)
        if await B07Engine.wait(4, { w.title == expectTitle }) != nil { return "Zurück-Knopf (AXPress)" }
        B07UI.click(b, in: w)
        if await B07Engine.wait(4, { w.title == expectTitle }) != nil { return "Zurück-Knopf (Klick)" }
        return "Zurück ohne Wirkung (Titel '\(w.title)')"
    }

    func testAK15c_EchteOberflaeche_ZurueckMitPiP_AndererSender_DannZurUebersicht() async throws {
        let session = MultiviewSession()
        let chA = channel("QA Sender A", "/livehls/e15/index.m3u8")
        let chB = channel("QA Sender B", "/livehls/f15/index.m3u8")
        _ = chB
        playlist.channelCount = 2
        try container.mainContext.save()
        let w = B07UI.window(ContentView().environment(session).modelContainer(container),
                             size: CGSize(width: 900, height: 600), title: "B07-App")
        windows.append(w)
        try await activate(w)
        await B07QA.spin(1.5)
        let o1 = await open(w, "QA M3U", expectTitle: "QA M3U")
        let o2 = await open(w, chA.name, expectTitle: chA.name)
        B07QA.log("AK-15c|Playlist: \(o1)|Sender A: \(o2)|Titel='\(w.title)'")
        guard w.title == chA.name else { return XCTFail("Player nicht geöffnet: \(o2)") }
        guard await B07Engine.wait(25, { self.lastEngine?.state == .playing }) != nil, let eA = lastEngine else { return XCTFail("A spielt nicht") }
        _ = await B07Engine.wait(15) { B07Engine.pipController(eA)?.isPictureInPicturePossible == true }
        weak let weakA: AVKitPlaybackEngine? = eA
        weak let weakPlayerA: AVPlayer? = B07Engine.avPlayer(eA)
        await showControls(w)
        if let b = pipButton(w) { B07UI.click(b, in: w) }
        if await B07Engine.wait(4, { eA.isPictureInPictureActive }) == nil, let b = pipButton(w) { B07UI.press(b) }
        guard await B07Engine.wait(10, { eA.isPictureInPictureActive && !B07PiPWindows.current().isEmpty }) != nil else { return XCTFail("PiP startet nicht") }
        B07QA.log("AK-15c|PiP aktiv|\(B07PiPWindows.current())")

        let bk = await back(w, expectTitle: "QA M3U")
        let tBack = Date()
        await B07QA.spin(1.5)
        B07QA.shot(w, "AK-15c-nach-zurueck-senderliste")
        B07QA.log("AK-15c|\(bk)|Titel='\(w.title)'|engineA=\(weakA != nil)|\(weakA.map(B07Engine.detail) ?? "-")|pipfenster=\(B07PiPWindows.current().count)")
        var from = Date()
        await B07QA.spin(10)
        B07QA.log("AK-15c|10 s nach Zurück: pipfenster=\(B07PiPWindows.current().count) engineA=\(weakA != nil) rateA=\(weakPlayerA?.rate ?? -1) segmente A=\(mock.segments("e15", from: from))")

        let o3 = await open(w, chB.name, expectTitle: chB.name)
        let tOpen = Date()
        B07QA.log("AK-15c|Sender B: \(o3)|\(B07QA.f1(tOpen.timeIntervalSince(tBack))) s nach Zurück")
        let eB = await B07Engine.wait(25, { B07Registry.engines.last(where: { $0 !== weakA })?.state == .playing }) != nil
            ? B07Registry.engines.last(where: { $0 !== weakA }) : nil
        var overlap = 0.0
        var goneAt: TimeInterval?
        while Date().timeIntervalSince(tOpen) < 45 {
            from = Date()
            await B07QA.spin(3)
            let sA = mock.segments("e15", from: from), sB = mock.segments("f15", from: from)
            let wins = B07PiPWindows.current().count
            if sA > 0 && sB > 0 { overlap += 3 }
            if goneAt == nil && wins == 0 { goneAt = Date().timeIntervalSince(tOpen) }
            B07QA.log("AK-15c|B offen t=\(B07QA.f1(Date().timeIntervalSince(tOpen)))s|pipfenster=\(wins) engineA=\(weakA != nil) rateA=\(weakPlayerA?.rate ?? -1)|segmente(3s) A=\(sA) B=\(sB)|B=\(eB.map { B07Engine.name($0.state) } ?? "-")")
            if goneAt != nil && Date().timeIntervalSince(tOpen) > 9 { break }
        }
        let aliveAfterB = weakA != nil
        // Zurück bis zur Übersicht
        let bk2 = await back(w, expectTitle: "QA M3U")
        let bk3 = await back(w, expectTitle: "Playlists")
        from = Date()
        await B07QA.spin(8)
        B07QA.log("AK-15c|zurück zur Übersicht: \(bk2) / \(bk3)|Titel='\(w.title)'|8 s danach: pipfenster=\(B07PiPWindows.current().count) engineA=\(weakA != nil) rateA=\(weakPlayerA?.rate ?? -1) segmente A=\(mock.segments("e15", from: from)) B=\(mock.segments("f15", from: from))")
        B07QA.log("AK-15c|Ergebnis: parallel≈\(Int(overlap)) s, altes Fenster weg=\(goneAt.map(B07QA.f1) ?? "nein (45 s)"), engineA nach B=\(aliveAfterB)")
        if let a = weakA { a.stopPictureInPicture() }
        weakPlayerA?.pause()
        // Behoben (BUG-01, 2026-09-27): Sender B beendet die verwaiste Wiedergabe von A samt Fenster.
        XCTAssertEqual(overlap, 0, "keine zwei Streams gleichzeitig")
        XCTAssertNotNil(goneAt, "das alte Bild-in-Bild-Fenster schließt")
        B07UI.close(w); windows.removeAll()
        await B07QA.spin(1)
        session.clear()
    }
}
