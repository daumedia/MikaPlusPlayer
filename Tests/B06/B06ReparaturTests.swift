import XCTest
import SwiftUI
import SwiftData
import AVFoundation
import AppKit
@testable import MikaPlusPlayer

/// Engine-Attrappe für die Übergabe an `DetachedPlayback` (Bild-in-Bild lässt sich ohne Systemfenster schalten).
@MainActor @Observable
final class B06FakeEngine: PlaybackEngine {
    var state: PlaybackState = .playing
    var isPaused = false
    var isMuted = false
    var volume = 1.0
    var isPictureInPictureActive = false
    var supportsPictureInPicture: Bool { true }
    private(set) var stopCalls = 0
    private(set) var pauseCalls = 0

    func load(_ url: URL) { state = .loading }
    func play() { isPaused = false }
    func pause() { isPaused = true; pauseCalls += 1 }
    func stop() { stopCalls += 1; isPaused = true; state = .idle }
    func togglePlayPause() { isPaused ? play() : pause() }
    func toggleMute() { isMuted.toggle() }
    func setMuted(_ muted: Bool) { isMuted = muted }
    func setVolume(_ value: Double) { volume = value }
    func makePlayerView() -> AnyView { AnyView(Color.black) }
}

/// B06 · Reparatur (sdd-build, Fehlerauftrag 2026-09-27): Nachweise für BUG-01, BUG-02, BUG-06, BUG-07, BUG-09.
/// Kein Ton: Medien ohne Tonspur (ffprobe-geprüft), selbst erzeugte Engines vor dem Laden stumm, Streams nur von
/// 127.0.0.1, nur belegte Tasten (Beep-Wächter). Bilder mit Präfix `BUILD-` unter `features/B06-wiedergabe/qa/`.
@MainActor
final class B06ReparaturTests: B06TestCase {

    private var container: ModelContainer!
    private var playlist: Playlist!
    private typealias Failure = VLCPlaybackEngine.Failure

    override func setUp() async throws {
        try await super.setUp()
        B06Registry.reset()
        B06BeepGuard.reset()
        XCTAssertTrue(B06BeepGuard.install(), "Beep-Wächter muss aktiv sein, bevor Tasten gesendet werden")
        container = try B06QA.inMemoryContainer()
        playlist = Playlist(name: "QA M3U", sourceURL: mock.url("/list.m3u"))
        container.mainContext.insert(playlist)
    }

    override func tearDown() async throws {
        DetachedPlayback.shared.stopAll()
        XCTAssertEqual(B06BeepGuard.hits, [], "kein unbehandeltes Tastenereignis")
        try await super.tearDown()
        container = nil
    }

    private func channel(_ name: String, _ path: String) -> Channel {
        let c = Channel(name: name, streamURL: mock.url(path), playlist: playlist, playlistID: playlist.id)
        container.mainContext.insert(c)
        return c
    }

    private func failureText(_ e: any PlaybackEngine) -> String? {
        if case .failed(let m) = e.state { return m }
        return nil
    }

    private func busy(_ w: NSWindow) -> Bool { B06UI.elements(w).contains { B06UI.role($0) == "AXBusyIndicator" } }
    private func button(_ w: NSWindow, _ symbol: String) -> NSObject? { B06UI.find(w, role: "AXButton", symbol) }

    private func activate(_ w: NSWindow) async throws {
        w.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        let ok = await B06Engine.wait(8) {
            if NSApp.isActive && NSApp.keyWindow !== w { w.makeKeyAndOrderFront(nil) }
            return NSApp.isActive && NSApp.keyWindow === w
        }
        if ok == nil { throw XCTSkip("Test-Host wurde nicht aktiv bzw. Fenster nicht Schlüsselfenster") }
    }

    private func waitFullscreen(_ w: NSWindow, _ on: Bool, _ timeout: TimeInterval = 6) async -> TimeInterval? {
        let t = await B06Engine.wait(timeout) { w.styleMask.contains(.fullScreen) == on }
        await B06QA.spin(1.2)
        return t
    }

    /// Offene Verbindungen mit rohem TS-Datenstrom (HLS-Keep-alive-Verbindungen tragen keinen Strom).
    private func openStreams(_ tag: String) -> [B06StreamServer.Connection] {
        mock.connections.filter { $0.closed == nil && $0.path.contains("/tslive/") && $0.path.contains(tag) }
    }

    // MARK: BUG-01 · Fristen und Meldungen

    func testBUG01_FristenAnalogAVKitUndMeldungenOhneAdresse() {
        XCTAssertEqual(VLCPlaybackEngine.Limits.standard, .init(load: 40, stall: 30),
                       "Laden ≈ 40 s wie AVKit-HLS, Hänger ≈ 30 s wie ein abgebrochener Live-HLS-Stream")
        XCTAssertEqual(VLCPlaybackEngine().state, .idle)
        let messages = [Failure.cannotOpen, .noResponse, .unplayable, .interrupted].map(\.message)
        B06QA.log("BUG-01|Meldungen|\(messages)")
        XCTAssertEqual(Set(messages).count, 4)
        for m in messages {
            XCTAssertTrue(m.hasPrefix("Der ") || m.hasPrefix("Die "), "deutscher Satz: \(m)")
            for technisch in ["://", "127.0.0.1", "/live/", "VLC", "libVLC", "error", "HTTP"] {
                XCTAssertFalse(m.contains(technisch), "\(m) enthält \(technisch)")
            }
        }
    }

    // MARK: BUG-01 · Hänger mitten im Stream

    /// Schnell mit 3 s Hänger-Frist; mit `B06_LANGSAM=1` mit der Standardfrist (30 s).
    func testBUG01_HaengerWaehrendDerWiedergabeMeldetSich() async throws {
        let langsam = ProcessInfo.processInfo.environment["B06_LANGSAM"] == "1"
        if !langsam { VLCPlaybackEngine.limitsForNewEngines = .init(load: 8, stall: 3) }
        let stall = VLCPlaybackEngine.limitsForNewEngines.stall
        let url = mock.url("/stall/4/tslive/b01stall.ts")
        let e = mutedEngine(for: url)
        host(e, index: 0)
        e.load(url)
        let t0 = Date()
        let playing = await B06Engine.wait(4) { e.state == .playing }
        let failed = await B06Engine.wait(stall + 11) { self.failureText(e) != nil }
        let failedAt = Date().timeIntervalSince(t0)
        await B06QA.spin(0.8)
        let conn = mock.connections(containing: "b01stall").last
        B06QA.log("BUG-01|Hänger ab 4 s|frist=\(Int(stall))s|playingNach=\(playing.map(B06QA.f1) ?? "-")s|meldungNach=\(B06QA.f1(failedAt))s|text=\(failureText(e) ?? "-")|verbindung=\(conn?.closed == nil ? "offen" : "zu(\(conn?.closeReason ?? ""))")")
        XCTAssertNotNil(playing, "läuft zunächst")
        XCTAssertNotNil(failed)
        XCTAssertEqual(failureText(e), Failure.interrupted.message)
        XCTAssertGreaterThan(failedAt, 4 + stall - 0.5, "erst nach der Hänger-Frist")
        XCTAssertLessThan(failedAt, 4 + stall + 6)
        XCTAssertNotNil(conn?.closed, "nach der Meldung ist die Verbindung zu")
    }

    // MARK: BUG-01 · „Erneut versuchen“ an der VLC-Engine

    func testBUG01_ErneutVersuchenLaedtNeuUndSpielt() async throws {
        let bad = mock.url("/404/b01retry.ts")
        let e = mutedEngine(for: bad)
        host(e, index: 0)
        e.load(bad)
        let fehler1 = await B06Engine.wait(4) { self.failureText(e) != nil }
        XCTAssertNotNil(fehler1)
        let first = mock.requests(containing: "b01retry").count
        e.load(bad)
        XCTAssertEqual(e.state, .loading, "kurz Ladekreis")
        let fehler2 = await B06Engine.wait(6) { self.failureText(e) != nil && self.mock.requests(containing: "b01retry").count > first }
        XCTAssertNotNil(fehler2)
        let second = mock.requests(containing: "b01retry").count
        let good = mock.url("/tslive/b01retry.ts")
        e.load(good)
        let t = await B06Engine.wait(8) { e.state == .playing }
        B06QA.log("BUG-01|Erneut versuchen|anfragen 404: erstes Öffnen=\(first) nach Versuch=\(second)|danach gültige Adresse playingNach=\(t.map(B06QA.f1) ?? "-")s|abbauten=\(VLCPlayerLifecycle.shared.completedTeardowns)")
        XCTAssertEqual(failureText(e), nil)
        XCTAssertNotNil(t, "dieselbe Engine spielt nach erneutem Laden")
        XCTAssertEqual(openStreams("b01retry").count, 1)
    }

    // MARK: BUG-02 · Verlassen: 0 weitere Anfragen, höchstens eine Verbindung

    func testBUG02_VerlassenBeendetVerbindungenNullWeitereAnfragen() async throws {
        let nav = B06Nav()
        let w = B06UI.window(B06TabHost(nav: nav).modelContainer(container), size: CGSize(width: 640, height: 440), title: "B06-BUILD Zurück")
        windows.append(w)
        var maxOpenStreams = 0
        var protokoll: [String] = []
        let sender: [(String, String, String)] = [
            ("QA TS 1", "/tslive/b02a.ts", "b02a"), ("QA HLS", "/livehls/b02h/index.m3u8", "b02h"),
            ("QA TS 2", "/tslive/b02b.ts", "b02b"), ("QA TS 1 erneut", "/tslive/b02a.ts", "b02a"),
        ]
        for (name, path, tag) in sender {
            nav.path = [channel(name, path)]
            let t0 = Date()
            var playing = false
            while Date().timeIntervalSince(t0) < 8 {
                maxOpenStreams = max(maxOpenStreams, openStreams("b02").count)
                if (B06Registry.liveVLCEngines.last?.state == .playing && path.hasSuffix(".ts"))
                    || (B06Registry.liveAVPlayers.last?.currentItem?.status == .readyToPlay && path.hasSuffix(".m3u8")) {
                    playing = true
                    break
                }
                await B06QA.spin(0.1)
            }
            XCTAssertTrue(playing, "\(name) spielt")
            for _ in 0..<15 { maxOpenStreams = max(maxOpenStreams, openStreams("b02").count); await B06QA.spin(0.1) }
            let before = mock.requests(containing: tag).count
            nav.path = []
            let tBack = Date()
            for _ in 0..<60 { maxOpenStreams = max(maxOpenStreams, openStreams("b02").count); await B06QA.spin(0.1) }
            let after = mock.requests(containing: tag).filter { $0.time > tBack.addingTimeInterval(1) }
            let offen = openStreams(tag)
            let zeile = "\(name)|anfragenBisZurück=\(before)|anfragen 1–6 s nach Zurück=\(after.count)|offeneStröme=\(offen.count)|engines(VLC lebend)=\(B06Registry.liveVLCEngines.count)|abbauten=\(VLCPlayerLifecycle.shared.completedTeardowns)"
            protokoll.append(zeile)
            B06QA.log("BUG-02|\(zeile)")
            XCTAssertEqual(after.count, 0, "\(name): nach „Zurück“ keine weitere Anfrage")
            XCTAssertEqual(offen.count, 0, "\(name): Verbindung nach „Zurück“ geschlossen")
        }
        let closeReasons = mock.connections.filter { $0.path.contains("/tslive/b02") }.map { "\($0.id):\($0.closeReason ?? "offen")" }
        B06QA.log("BUG-02|höchstens gleichzeitig offene Ströme=\(maxOpenStreams)|verbindungen=\(closeReasons)")
        XCTAssertLessThanOrEqual(maxOpenStreams, 1, "höchstens eine Verbindung je sichtbarem Player")
    }

    // MARK: BUG-02 · Bild-in-Bild: läuft bis zum Ende weiter, endet dann

    func testBUG02_MitBildInBildLaeuftWeiterBisBildInBildEndet() async throws {
        let ohne = B06FakeEngine()
        DetachedPlayback.shared.adopt(ohne)
        XCTAssertEqual(ohne.stopCalls, 1, "ohne Bild-in-Bild endet die Wiedergabe sofort")
        XCTAssertTrue(DetachedPlayback.shared.engines.isEmpty)

        let mit = B06FakeEngine()
        mit.isPictureInPictureActive = true
        DetachedPlayback.shared.adopt(mit)
        await B06QA.spin(1.0)
        XCTAssertEqual(mit.stopCalls, 0, "läuft im schwebenden Fenster weiter")
        XCTAssertEqual(mit.pauseCalls, 0)
        XCTAssertTrue(DetachedPlayback.shared.engines.contains { $0 === mit })
        mit.isPictureInPictureActive = false        // Fenster geschlossen / „Zurück zur App“
        let stopped = await B06Engine.wait(2) { mit.stopCalls == 1 }
        B06QA.log("BUG-02|Bild-in-Bild endet → stop nach \(stopped.map(B06QA.f1) ?? "-")s|übrig=\(DetachedPlayback.shared.engines.count)")
        XCTAssertNotNil(stopped, "endet, sobald Bild-in-Bild endet")
        XCTAssertTrue(DetachedPlayback.shared.engines.isEmpty)
    }

    // MARK: BUG-06 · Tabwechsel im Vollbild

    func testBUG06_TabwechselImVollbildPlayerKenntFensterzustand() async throws {
        let nav = B06Nav()
        let w = B06UI.window(B06TabHost(nav: nav).modelContainer(container), size: CGSize(width: 640, height: 440), title: "B06-BUILD Tabs")
        windows.append(w)
        try await activate(w)
        nav.path = [channel("QA Tab Vollbild", "/livehls/b06tab/index.m3u8")]
        _ = await B06Engine.wait(8) { B06Registry.liveAVPlayers.last?.currentItem?.status == .readyToPlay }
        B06UI.key(w, .char("f"))
        let vollbild = await waitFullscreen(w, true)
        XCTAssertNotNil(vollbild, "F → Vollbild")
        nav.tab = 1
        let aus = await waitFullscreen(w, false)
        nav.tab = 0
        await B06QA.spin(1.0)
        B06UI.key(w, .space)          // Steuerung einblenden (pausiert)
        await B06QA.spin(0.4)
        let enter = button(w, "arrow.up.left.and.arrow.down.right") != nil
        let exit = button(w, "arrow.down.right.and.arrow.up.left") != nil
        B06QA.log("BUG-06|Tabwechsel im Vollbild|fensterVerlässtVollbild=\(aus != nil)|zurück: titel='\(w.title)' knopf=\(enter ? "Vollbild-an" : (exit ? "Vollbild-aus" : "-"))")
        B06UI.key(w, .space)
        XCTAssertNotNil(aus)
        XCTAssertEqual(w.title, "QA Tab Vollbild", "Titel zurück")
        XCTAssertTrue(enter, "Knopf zeigt „Vollbild“, nicht „Vollbild verlassen“")
        XCTAssertFalse(exit)
    }

    // MARK: BUG-07 · Multiview schließen und sofort neu belegen

    func testBUG07_MultiviewSchliessenUndSofortNeuAbbauNacheinander() async throws {
        let lifecycle = VLCPlayerLifecycle.shared
        let session = MultiviewSession()
        var runde = 0
        func belegen() -> [Channel] {
            runde += 1
            return (1...4).map { channel("QA MV \(runde)-\($0)", "/tslive/b07mv-\(runde)-\($0).ts") }
        }
        for c in belegen() { session.add(c) }
        let erstBelegt = await B06Engine.wait(10) { session.slots.count == 4 && session.slots.allSatisfy { $0.engine.state == .playing } }
        XCTAssertNotNil(erstBelegt)
        for durchgang in 1...3 {
            let abbautenVorher = lifecycle.completedTeardowns
            let zurueckgestelltVorher = lifecycle.deferredCreations
            let t0 = Date()
            session.clear()                                  // wie Schließen des Multiview-Fensters
            for c in belegen() { session.add(c) }            // sofort vier neue
            let hauptthreadFrei = Date().timeIntervalSince(t0)
            let spielen = await B06Engine.wait(15) { session.slots.count == 4 && session.slots.allSatisfy { $0.engine.state == .playing } }
            _ = await B06Engine.wait(10) { lifecycle.isIdle }
            let alt = mock.connections.filter { $0.path.contains("b07mv-\(runde - 1)-") }
            B06QA.log("BUG-07|Durchgang \(durchgang)|clear+add in \(B06QA.f1(hauptthreadFrei))s|alle vier spielen nach \(spielen.map(B06QA.f1) ?? "-")s|abbauten +\(lifecycle.completedTeardowns - abbautenVorher)|zurückgestellte Erzeugungen +\(lifecycle.deferredCreations - zurueckgestelltVorher)|höchstens gleichzeitige Abbauten=\(lifecycle.maxConcurrentTeardowns)|alte Verbindungen offen=\(alt.filter { $0.closed == nil }.count)")
            XCTAssertLessThan(hauptthreadFrei, 1.0, "Schließen und Neubelegen blockieren den Hauptthread nicht")
            XCTAssertNotNil(spielen, "Durchgang \(durchgang): vier neue Kacheln spielen")
            XCTAssertEqual(lifecycle.completedTeardowns - abbautenVorher, 4, "vier Player abgebaut")
            XCTAssertGreaterThanOrEqual(lifecycle.deferredCreations - zurueckgestelltVorher, 1, "neue Player warten auf den Abbau")
            XCTAssertEqual(alt.filter { $0.closed == nil }.count, 0, "alte Verbindungen zu")
        }
        XCTAssertEqual(lifecycle.maxConcurrentTeardowns, 1, "nie mehr als ein Abbau gleichzeitig")
        session.clear()
        _ = await B06Engine.wait(10) { lifecycle.isIdle }
        XCTAssertEqual(openStreams("b07mv").count, 0)
    }

    // MARK: BUG-09 · Ladekreis hell auf Schwarz

    func testBUG09_LadekreisWeissAufSchwarzInBeidenErscheinungsbildern() async throws {
        for (name, appearance) in [("hell", NSAppearance.Name.aqua), ("dunkel", NSAppearance.Name.darkAqua)] {
            let w = B06UI.window(NavigationStack { PlayerView(channel: channel("QA Laden \(name)", "/hang/b09\(name).ts")) }
                .modelContainer(container), size: CGSize(width: 560, height: 360), title: "B06-BUILD Laden \(name)")
            w.appearance = NSAppearance(named: appearance)
            windows.append(w)
            await B06QA.spin(1.5)
            XCTAssertTrue(busy(w), "\(name): Ladekreis sichtbar")
            // Bild über die Fensteraufnahme der Testbasis (schreibt es als Nachweis) und von dort vermessen
            let shotName = "BUILD-BUG-09-ladekreis-\(name)"
            B06QA.shot(w, shotName)
            guard let data = try? Data(contentsOf: B06QA.qaFolder.appendingPathComponent("\(shotName).png")),
                  let rep = NSBitmapImageRep(data: data) else {
                return XCTFail("Fensterbild nicht verfügbar")
            }
            var maxLum = 0.0, hell = 0
            let cx = rep.pixelsWide / 2, cy = rep.pixelsHigh / 2
            for x in (cx - 60)..<(cx + 60) {
                for y in (cy - 60)..<(cy + 60) {
                    guard let c = rep.colorAt(x: x, y: y)?.usingColorSpace(.sRGB) else { continue }
                    let lum = 0.2126 * c.redComponent + 0.7152 * c.greenComponent + 0.0722 * c.blueComponent
                    maxLum = max(maxLum, lum)
                    if lum > 0.5 { hell += 1 }
                }
            }
            B06QA.log("BUG-09|\(name)|max. Helligkeit im Ladekreis=\(String(format: "%.3f", maxLum))|Pixel > 0,5=\(hell) (QA 1: 0,275 bzw. 0)")
            // Weiße Striche mit der (halbtransparenten) Deckkraft des System-Ladekreises: ≈ 0,6 auf Schwarz;
            // der graue Kreis aus QA 1 erreichte 0,275 und keinen Pixel über 0,5.
            XCTAssertGreaterThan(maxLum, 0.5, "\(name): Ladekreis hell")
            XCTAssertGreaterThan(hell, 20, "\(name): nicht nur ein einzelner Pixel")
        }
    }
}
