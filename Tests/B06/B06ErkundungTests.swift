import XCTest
import SwiftUI
import SwiftData
@testable import MikaPlusPlayer

/// Nur Erkundung (Umgebungsvariable B06_ERKUNDUNG=1): Accessibility-Baum des Players in allen Zuständen protokollieren.
@MainActor
final class B06ErkundungTests: B06TestCase {
    func testErkundungAXBaum() async throws {
        guard ProcessInfo.processInfo.environment["B06_ERKUNDUNG"] == "1" else { throw XCTSkip("nur mit B06_ERKUNDUNG=1") }
        XCTAssertTrue(B06BeepGuard.install())
        let container = try B06QA.inMemoryContainer()
        let ctx = container.mainContext
        let p = Playlist(name: "QA", sourceURL: mock.url("/list.m3u"))
        ctx.insert(p)
        let hls = Channel(name: "QA HLS", streamURL: mock.url("/livehls/erk/index.m3u8"), playlist: p, playlistID: p.id)
        let bad = Channel(name: "QA 404", streamURL: mock.url("/404/erk.m3u8"), playlist: p, playlistID: p.id)
        ctx.insert(hls); ctx.insert(bad)
        let w = B06UI.window(NavigationStack { PlayerView(channel: hls) }.modelContainer(container))
        windows.append(w)
        B06UI.dump(w, "sofort")
        _ = await B06Engine.wait(5) { B06Registry.liveAVPlayers.first?.currentItem?.status == .readyToPlay }
        for p in B06Registry.liveAVPlayers { p.isMuted = true }
        await B06QA.spin(0.5)
        B06UI.dump(w, "spielt")
        B06QA.log("title=\(w.title) toolbar=\(String(describing: w.toolbar)) firstResponder=\(String(describing: w.firstResponder))")
        B06UI.key(w, .space)
        await B06QA.spin(0.2)
        B06UI.dump(w, "nach-space")
        B06QA.log("rate=\(B06Registry.liveAVPlayers.first?.rate ?? -1) beeps=\(B06BeepGuard.hits)")
        await B06QA.spin(4)
        B06UI.dump(w, "nach-4s")
        let w2 = B06UI.window(NavigationStack { PlayerView(channel: bad) }.modelContainer(container), origin: CGPoint(x: 760, y: 120))
        windows.append(w2)
        await B06QA.spin(2)
        B06UI.dump(w2, "fehler")
    }
}
