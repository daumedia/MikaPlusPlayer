import XCTest
import AVFoundation
@testable import MikaPlusPlayer

/// B06 · AK-01 (Startwerte), AK-15, AK-16, AK-17, EC-05, EC-06 an beiden Engines mit laufendem, stummem Stream.
/// Lautstärke und Stumm werden am Zustand der Engine gelesen (AVPlayer.volume/isMuted, VLC audio.volume/muted), nicht am Gehör.
@MainActor
final class B06SteuerungTests: B06TestCase {

    func testAK01_StartwerteNeuerEngines() {
        for url in [mock.url("/livehls/ak01/index.m3u8"), mock.url("/tslive/ak01.ts")] {
            let e = PlaybackEngineFactory.engine(for: url)   // noch nicht geladen
            B06QA.log("AK-01|\(type(of: e))|volume=\(e.volume)|isMuted=\(e.isMuted)|isPaused=\(e.isPaused)|state=\(B06Engine.name(e.state))")
            XCTAssertEqual(e.volume, 1.0)
            XCTAssertFalse(e.isMuted)
            XCTAssertFalse(e.isPaused)
            XCTAssertEqual(e.state, .idle)
        }
    }

    private func playing() async throws -> [(String, any PlaybackEngine)] {
        let av = mutedEngine(for: mock.url("/livehls/steuer/index.m3u8"))
        let vlc = mutedEngine(for: mock.url("/tslive/steuer.ts"))
        host(av, index: 0)
        host(vlc, index: 1)
        av.load(mock.url("/livehls/steuer/index.m3u8"))
        vlc.load(mock.url("/tslive/steuer.ts"))
        let ok = await B06Engine.wait(8) { av.state == .playing && vlc.state == .playing }
        XCTAssertNotNil(ok, "beide spielen")
        await B06QA.spin(2)
        return [("av", av), ("vlc", vlc)]
    }

    private func raw(_ e: any PlaybackEngine) -> String {
        if let p = B06Engine.avPlayer(e) { return "rate=\(p.rate) volume=\(p.volume) muted=\(p.isMuted)" }
        if let v = B06Engine.vlcPlayer(e) {
            let a = B06Engine.vlcAudio(v)
            return "vlc=\(B06Engine.vlcState(v)) audio.volume=\(a.volume.map(String.init) ?? "-") audio.muted=\(a.muted.map { $0 ? "1" : "0" } ?? "-")"
        }
        return "?"
    }

    func testAK15_PlayPauseBeideEngines() async throws {
        for (label, e) in try await playing() {
            e.togglePlayPause()
            await B06QA.spin(1.5)
            B06QA.log("AK-15|\(label)|nach Pause|isPaused=\(e.isPaused)|state=\(B06Engine.name(e.state))|\(raw(e))")
            XCTAssertTrue(e.isPaused)
            XCTAssertEqual(e.state, .playing, "PlaybackState kennt kein .paused")
            if let p = B06Engine.avPlayer(e) { XCTAssertEqual(p.rate, 0) }
            if let v = B06Engine.vlcPlayer(e) { XCTAssertEqual(B06Engine.vlcState(v), "paused") }
            e.togglePlayPause()
            await B06QA.spin(1.5)
            B06QA.log("AK-15|\(label)|nach Play|isPaused=\(e.isPaused)|\(raw(e))")
            XCTAssertFalse(e.isPaused)
            if let p = B06Engine.avPlayer(e) { XCTAssertEqual(p.rate, 1) }
            if let v = B06Engine.vlcPlayer(e) { XCTAssertEqual(B06Engine.vlcState(v), "playing") }
        }
    }

    func testAK16_AK17_EC06_StummUndLautstaerkeBeideEngines() async throws {
        for (label, e) in try await playing() {
            // Ausgangslage dieses Tests: stumm (vor dem Laden gesetzt), 100 %
            XCTAssertTrue(e.isMuted)
            if let p = B06Engine.avPlayer(e) { XCTAssertTrue(p.isMuted) }
            if let v = B06Engine.vlcPlayer(e) { B06QA.log("AK-16|\(label)|vlc stumm vor dem Laden|\(raw(e))"); XCTAssertEqual(B06Engine.vlcAudio(v).muted, true) }
            // AK-16: Umschalten, Lautstärkewert bleibt
            e.toggleMute()
            B06QA.log("AK-16|\(label)|toggle→\(e.isMuted)|volume=\(e.volume)|\(raw(e))")
            XCTAssertFalse(e.isMuted)
            XCTAssertEqual(e.volume, 1.0)
            e.toggleMute()
            XCTAssertTrue(e.isMuted)
            if let p = B06Engine.avPlayer(e) { XCTAssertTrue(p.isMuted) }
            if let v = B06Engine.vlcPlayer(e) { XCTAssertEqual(B06Engine.vlcAudio(v).muted, true) }

            // AK-17: dreimal ↑ bei 100 % – ohne Stumm aufzuheben? (Wert > 0 hebt Stumm auf, auch an der Grenze)
            for _ in 0..<3 { e.setVolume(e.volume + 0.05) }
            B06QA.log("AK-17|\(label)|3x hoch bei 100%|volume=\(e.volume)|isMuted=\(e.isMuted)|\(raw(e))")
            XCTAssertEqual(e.volume, 1.0)
            e.setMuted(true)
            // zwanzigmal ↓ von 100 % (EC-06: Gleitkomma, angezeigt gerundet)
            var seq: [String] = []
            for i in 1...20 {
                e.setVolume(e.volume - 0.05)
                seq.append("\(i):\(e.volume)→\(Int((e.volume * 100).rounded()))%")
                if i == 1 { XCTAssertFalse(e.isMuted, "OF-02: ↓ hebt Stumm auf"); e.setMuted(true) }
            }
            B06QA.log("EC-06|\(label)|20x runter|\(seq.joined(separator: " "))")
            B06QA.log("AK-17|\(label)|nach 20x runter|volume=\(e.volume)|isMuted=\(e.isMuted)|\(raw(e))")
            XCTAssertEqual(e.volume, 0.0, accuracy: 1e-9)
            XCTAssertEqual(Int((e.volume * 100).rounded()), 0)
            e.setVolume(e.volume - 0.05)
            XCTAssertEqual(e.volume, 0.0, "untere Grenze 0 %")
            // Stumm bleibt bei 0 %: Wert 0 hebt nicht auf
            e.setMuted(true)
            e.setVolume(0)
            XCTAssertTrue(e.isMuted)
            // Systemlautstärke bleibt unberührt (nur gelesen)
            let sysBefore = B06QA.systemVolume()
            e.setVolume(0.15)
            e.setVolume(1.0)
            let sysAfter = B06QA.systemVolume()
            B06QA.log("AK-17|\(label)|Systemlautstärke vorher=\(sysBefore) nachher=\(sysAfter)")
            XCTAssertEqual(sysBefore, sysAfter, "AK-17: Systemlautstärke unverändert")
            // Werte an der Engine
            e.setVolume(0.35)
            e.setMuted(true)
            await B06QA.spin(0.3)
            B06QA.log("AK-17|\(label)|0,35 stumm|\(raw(e))")
            if let p = B06Engine.avPlayer(e) { XCTAssertEqual(p.volume, 0.35, accuracy: 0.001) }
            if let v = B06Engine.vlcPlayer(e) { XCTAssertEqual(B06Engine.vlcAudio(v).volume, 35) }
            e.setVolume(1.0)
            e.setMuted(true)
        }
    }

    // MARK: EC-05 / AK-29 (Engine) · Pause während VLC noch lädt

    func testEC05_PauseWaehrendVLCLaedtWirktNicht() async throws {
        let url = mock.url("/delay/3/tslive/ec05.ts")
        let e = mutedEngine(for: url)
        host(e, index: 0)
        e.load(url)
        await B06QA.spin(0.5)
        B06QA.log("EC-05|vor pause()|state=\(B06Engine.name(e.state))|\(raw(e))")
        e.pause()
        B06QA.log("EC-05|nach pause()|isPaused=\(e.isPaused)|\(raw(e))")
        await B06QA.spin(8)
        let now = Date()
        let conn = mock.connections(containing: "ec05").last
        let last4 = conn?.bytes(from: now.addingTimeInterval(-4), to: now) ?? 0
        B06QA.log("EC-05|+8s|isPaused=\(e.isPaused)|state=\(B06Engine.name(e.state))|\(raw(e))|vlcIsPlaying=\(B06Engine.vlcPlayer(e).map(B06Engine.vlcIsPlaying) ?? false)|bytesLetzte4s=\(last4)|rate/s=\(Int(mock.media.tsRate))")
        XCTAssertTrue(e.isPaused, "App hält den Stream für pausiert (Knopf zeigt ▶)")
        XCTExpectFailure("BUG-02 · pause() während VLC lädt wirkt nicht – Stream läuft mit voller Datenrate (FB-02, EC-05)") {
            XCTAssertEqual(B06Engine.vlcPlayer(e).map(B06Engine.vlcIsPlaying), false)
            XCTAssertLessThan(last4, Int(mock.media.tsRate))
        }
    }

    // MARK: AK-28 (Engine) · pausierte Engines laden weiter

    /// Was tut eine pausierte Engine, die noch lebt (wie nach „Zurück“ bis zur Freigabe)? 60 s beobachtet.
    func testAK28_PausierteEnginesLadenWeiter() async throws {
        let av = mutedEngine(for: mock.url("/livehls/ak28p/index.m3u8"))
        let vlc = mutedEngine(for: mock.url("/tslive/ak28p.ts"))
        host(av, index: 0)
        host(vlc, index: 1)
        av.load(mock.url("/livehls/ak28p/index.m3u8"))
        vlc.load(mock.url("/tslive/ak28p.ts"))
        _ = await B06Engine.wait(8) { av.state == .playing && vlc.state == .playing }
        await B06QA.spin(3)
        av.pause()
        vlc.pause()
        let t0 = Date()
        var line: [String] = []
        var lastBytes = mock.connections(containing: "ak28p.ts").last?.bytesSent ?? 0
        var lastHLS = mock.requests(containing: "/livehls/ak28p/").count
        for i in 1...12 {
            await B06QA.spin(Double(i * 5) - Date().timeIntervalSince(t0))
            let c = mock.connections(containing: "ak28p.ts").last
            let b = c?.bytesSent ?? 0
            let h = mock.requests(containing: "/livehls/ak28p/").count
            line.append("+\(i * 5)s: TS Δbytes=\(b - lastBytes) verbindung=\(c?.closed == nil ? "offen" : "zu") vlc=\(B06Engine.vlcPlayer(vlc).map(B06Engine.vlcState) ?? "-") | HLS Δanfragen=\(h - lastHLS) rate=\(B06Engine.avPlayer(av)?.rate ?? -1)")
            lastBytes = b
            lastHLS = h
        }
        B06QA.log("AK-28p|pausiert, Referenz gehalten, je 5 s (TS-Rate \(Int(mock.media.tsRate)) B/s)|\(line)")
        let hlsLast20 = mock.requests(containing: "/livehls/ak28p/").filter { $0.time > Date().addingTimeInterval(-20) }.count
        XCTAssertGreaterThan(hlsLast20, 10, "Ist: pausierte AVKit-Engine lädt Live-Playlist und Segmente weiter")
        XCTAssertNil(mock.connections(containing: "ak28p.ts").last?.closed, "Ist: VLC-Verbindung bleibt offen")
    }
}
