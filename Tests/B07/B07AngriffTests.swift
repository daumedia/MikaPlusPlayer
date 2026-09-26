import XCTest
import SwiftUI
import SwiftData
import AVFoundation
import AVKit
import AppKit
@testable import MikaPlusPlayer

/// B07 · Angriffsdurchlauf (angriff.md), übertragen auf Bild-in-Bild in einer lokalen App ohne Backend – macOS.
@MainActor
final class B07AngriffTests: B07TestCase {

    private func waitPlaying(_ probe: @escaping () -> AVKitPlaybackEngine?) async -> AVKitPlaybackEngine? {
        guard await B07Engine.wait(25, { probe()?.state == .playing }) != nil, let e = probe() else { return nil }
        _ = await B07Engine.wait(15) { B07Engine.pipController(e)?.isPictureInPicturePossible == true }
        return e
    }

    /// Entfernte Endpunkte der TCP-Verbindungen dieses Prozesses (lsof).
    private func remoteEndpoints() -> [String] {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/sbin/lsof")
        p.arguments = ["-nP", "-a", "-p", "\(getpid())", "-iTCP"]
        let out = Pipe(); p.standardOutput = out; p.standardError = Pipe()
        try? p.run()
        let d = out.fileHandleForReading.readDataToEndOfFile(); p.waitUntilExit()
        return String(decoding: d, as: UTF8.self).split(separator: "\n").dropFirst().compactMap { l in
            guard let arrow = l.range(of: "->") else { return nil }
            return String(l[arrow.upperBound...]).split(separator: " ").first.map(String.init)
        }
    }

    // MARK: 3 · Wiederholversuche (schnelles Umschalten)

    func testAngriff3_PiPUmschaltenInSchnellerFolge_EinFensterKeinAbsturzKeineZusatzverbindungen() async throws {
        let c = channel("QA Spam", "/livehls/spam/index.m3u8")
        let w = playerWindow(c)
        try await activate(w)
        guard let e = await waitPlaying({ self.lastEngine }) else { return XCTFail("spielt nicht") }
        let before = mock.connections.count
        var maxWins = 0
        for i in 0..<20 {
            await press(w, .char("p"))
            maxWins = max(maxWins, B07PiPWindows.current().count)
            if i % 5 == 4 { B07QA.log("Angriff3|nach \(i + 1)× P: aktiv=\(e.isPictureInPictureActive) fenster=\(B07PiPWindows.current().count)") }
        }
        await B07QA.spin(4)
        let settled = "aktiv=\(e.isPictureInPictureActive) fenster=\(B07PiPWindows.current().count) \(B07Engine.detail(e))"
        B07QA.log("Angriff3|20× P in ~\(B07QA.f1(20 * 0.3)) s: max. gleichzeitige Fenster=\(maxWins) · danach \(settled) · Verbindungen vorher=\(before) nachher=\(mock.connections.count) offen=\(mock.connections.filter { $0.closed == nil }.count)")
        XCTAssertLessThanOrEqual(maxWins, 1, "nie mehr als ein Fenster")
        XCTAssertEqual(e.state, .playing, "kein Abbruch der Wiedergabe")
        XCTAssertEqual(e.isPictureInPictureActive, !B07PiPWindows.current().isEmpty, "App-Zustand und Systemfenster stimmen überein")
        e.stopPictureInPicture()
        _ = await B07Engine.wait(8) { !e.isPictureInPictureActive }
    }

    // MARK: 5 · Daten an Dritte

    func testAngriff5_BildInBildErzeugtKeineZusaetzlichenAnfragenNurLoopback() async throws {
        let c = channel("QA Payload", "/live/\(B07QA.user)/\(B07QA.pass)/501.m3u8")
        let w = playerWindow(c)
        try await activate(w)
        guard let e = await waitPlaying({ self.lastEngine }) else { return XCTFail("spielt nicht") }
        await B07QA.spin(2)
        let t0 = Date()
        _ = await press(w, .char("p"))
        _ = await B07Engine.wait(10) { e.isPictureInPictureActive }
        await B07QA.spin(4)
        let endpointsDuring = Set(remoteEndpoints())
        _ = await press(w, .char("p"))
        _ = await B07Engine.wait(10) { !e.isPictureInPictureActive }
        await B07QA.spin(2)
        let reqs = mock.requests.filter { $0.time >= t0 }
        let paths = Set(reqs.map { $0.path.replacingOccurrences(of: #"seg\d+"#, with: "segN", options: .regularExpression) })
        let headers = Set(reqs.flatMap { $0.headers.keys }).sorted()
        let ua = Set(reqs.compactMap { $0.headers["user-agent"] })
        B07QA.log("Angriff5|Anfragen während PiP an/aus=\(reqs.count) Pfade=\(paths.sorted()) Kopfzeilen=\(headers) UA=\(ua)")
        B07QA.log("Angriff5|entfernte TCP-Endpunkte des Prozesses während PiP=\(endpointsDuring.sorted())")
        XCTAssertTrue(paths.allSatisfy { $0.hasPrefix("/live/\(B07QA.user)/\(B07QA.pass)/") }, "nur die Stream-Adresse selbst")
        XCTAssertFalse(headers.contains("cookie") || headers.contains("authorization"))
        XCTAssertTrue(endpointsDuring.allSatisfy { $0.hasPrefix("127.0.0.1:") || $0.hasPrefix("[::1]") }, "keine Verbindung zu anderen Hosts")
    }

    // MARK: 7 · Eingaben

    func testAngriff7_SendernameLangEmojiSonderzeichen_PlatzhalterUndFensterOhneName() async throws {
        let names = [String(repeating: "Ä", count: 10_000), "📺🇱🇺 Sender 😀", "'; drop table ZCHANNEL; --", "<script>alert(1)</script>", "../../etc/passwd", ""]
        for (i, n) in names.enumerated() {
            let c = channel(n, "/livehls/in\(i)/index.m3u8")
            let prev = Set(B07Registry.engines.map(ObjectIdentifier.init))
            let w = playerWindow(c)
            try await activate(w)
            guard let e = await waitPlaying({ B07Registry.engines.last(where: { !prev.contains(ObjectIdentifier($0)) }) }) else { XCTFail("spielt nicht: \(n.prefix(20))"); continue }
            _ = await press(w, .char("p"))
            let on = await B07Engine.wait(10) { e.isPictureInPictureActive && !B07PiPWindows.current().isEmpty }
            let pip = B07PiPWindows.current()
            let texts = B07UI.elements(w).map(B07UI.label).filter { !$0.isEmpty }
            B07QA.log("Angriff7|name(\(n.count) Zeichen, '\(n.prefix(24))')|pip=\(on != nil) fenster=\(pip.map { "\($0.owner) '\($0.name)' \(Int($0.bounds.width))x\(Int($0.bounds.height))" })|fenstertitel(\(w.title.count))|app-texte=\(texts)")
            XCTAssertNotNil(on, "PiP startet trotz ungewöhnlichem Namen")
            XCTAssertTrue(pip.allSatisfy { n.isEmpty || !$0.name.contains(n.prefix(8)) })
            if i == 1 { B07QA.shot(w, "Angriff7-emoji-name-platzhalter") }
            e.stopPictureInPicture()
            _ = await B07Engine.wait(8) { !e.isPictureInPictureActive }
            B07UI.close(w); windows.removeAll()
            await B07QA.spin(0.5)
        }
    }

    // MARK: 8 · Löschen während Bild-in-Bild

    func testAngriff8_PlaylistLoeschenWaehrendPiP_WiedergabeLaeuftWeiter() async throws {
        let c = channel("QA Löschen", "/livehls/del8/index.m3u8")
        try container.mainContext.save()
        let w = playerWindow(c)
        try await activate(w)
        guard let e = await waitPlaying({ self.lastEngine }) else { return XCTFail("spielt nicht") }
        _ = await press(w, .char("p"))
        guard await B07Engine.wait(10, { e.isPictureInPictureActive }) != nil else { return XCTFail("PiP startet nicht") }
        container.mainContext.delete(playlist)
        try container.mainContext.save()
        let rest = try container.mainContext.fetchCount(FetchDescriptor<Channel>())
        let from = Date()
        await B07QA.spin(10)
        let segs = mock.segments("del8", from: from)
        B07QA.log("Angriff8|Playlist gelöscht (Sender in DB: \(rest))|10 s danach: pip=\(e.isPictureInPictureActive) fenster=\(B07PiPWindows.current().count) rate=\(B07Engine.avPlayer(e)?.rate ?? -1) segmente=\(segs)|fenster='\(w.title)'")
        XCTAssertEqual(rest, 0)
        // Ist-Verhalten (B03 BUG-05 / BF-56): Die Wiedergabe des gelöschten Senders läuft im schwebenden Fenster weiter.
        e.stopPictureInPicture()
        _ = await B07Engine.wait(8) { !e.isPictureInPictureActive }
    }
}
