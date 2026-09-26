import XCTest
import SwiftUI
import SwiftData
import AVFoundation
import AppKit
@testable import MikaPlusPlayer

/// Navigationszustand, den der Test von außen steuert (Öffnen/„Zurück“, Tabwechsel).
@MainActor @Observable
final class B06Nav {
    var path: [Channel] = []
    var tab = 0
}

/// Senderliste-Ersatz mit echtem `navigationDestination` wie in `ChannelListView`.
struct B06StackHost: View {
    @Bindable var nav: B06Nav
    var body: some View {
        NavigationStack(path: $nav.path) {
            Text("B06 Liste")
                .navigationDestination(for: Channel.self) { PlayerView(channel: $0) }
        }
    }
}

/// Zwei Tabs wie `ContentView`: Tab 0 mit Stapel, Tab 1 leer.
struct B06TabHost: View {
    @Bindable var nav: B06Nav
    var body: some View {
        TabView(selection: $nav.tab) {
            B06StackHost(nav: nav).tabItem { Text("Playlists") }.tag(0)
            Text("B06 Favoriten").tabItem { Text("Favoriten") }.tag(1)
        }
    }
}

/// B06 · PlayerView im Test-Host (echtes Fenster, AppKit-Accessibility, synthetische Klicks und nur belegte Tasten).
/// Medien ohne Tonspur (ffprobe-geprüft). Engines, die `PlayerView` selbst erzeugt, lassen sich nicht vor dem Laden
/// stumm schalten, ohne Produktcode zu ändern – deshalb ausschließlich Medien ohne Audiospur.
@MainActor
final class B06PlayerViewTests: B06TestCase {

    private var container: ModelContainer!
    private var playlist: Playlist!

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
        XCTAssertEqual(B06BeepGuard.hits, [], "kein unbehandeltes Tastenereignis")
        try await super.tearDown()
        container = nil
    }

    private func channel(_ name: String, _ path: String, in p: Playlist? = nil) -> Channel {
        let pl = p ?? playlist!
        let c = Channel(name: name, streamURL: path.hasPrefix("/") ? mock.url(path) : URL(string: path)!, playlist: pl, playlistID: pl.id)
        container.mainContext.insert(c)
        return c
    }

    private func player(_ c: Channel, origin: CGPoint = CGPoint(x: 80, y: 120), size: CGSize = CGSize(width: 640, height: 400)) -> NSWindow {
        let w = B06UI.window(NavigationStack { PlayerView(channel: c) }.modelContainer(container), size: size, origin: origin, title: "B06-QA")
        windows.append(w)
        return w
    }

    private func button(_ w: NSWindow, _ symbol: String) -> NSObject? { B06UI.find(w, role: "AXButton", symbol) }
    private func controlsVisible(_ w: NSWindow) -> Bool {
        button(w, "arrow.up.left.and.arrow.down.right") != nil || button(w, "arrow.down.right.and.arrow.up.left") != nil
    }
    private func hudImage(_ w: NSWindow) -> String? {
        B06UI.elements(w).first { B06UI.role($0) == "AXImage" }.map(B06UI.label)
    }
    private func busy(_ w: NSWindow) -> Bool { B06UI.elements(w).contains { B06UI.role($0) == "AXBusyIndicator" } }
    private var av: AVPlayer? { B06Registry.liveAVPlayers.last }

    /// Holt den Test-Host nach vorn. `NSApp.activate` genügt nicht, solange eine andere App aktiv ist; mit
    /// `B06_ACTIVATE_REQ=<Datei>` schreibt der Test seine PID dorthin, ein Helfer außerhalb setzt per Bedienungshilfen
    /// `AXFrontmost` (QA 2026-09-16: `scratchpad/b06qa/tools/watch_activate.sh`).
    private func activate(_ w: NSWindow) async throws {
        w.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        if !(NSApp.isActive), let req = ProcessInfo.processInfo.environment["B06_ACTIVATE_REQ"] {
            try? "\(getpid())".write(toFile: req, atomically: true, encoding: .utf8)
        }
        let ok = await B06Engine.wait(8) {
            if NSApp.isActive && NSApp.keyWindow !== w { w.makeKeyAndOrderFront(nil) }
            return NSApp.isActive && NSApp.keyWindow === w
        }
        if ok == nil { throw XCTSkip("Test-Host wurde nicht aktiv bzw. Fenster nicht Schlüsselfenster (keyWindow=\(String(describing: NSApp.keyWindow)))") }
    }

    private func waitFullscreen(_ w: NSWindow, _ on: Bool, _ timeout: TimeInterval = 6) async -> TimeInterval? {
        let t = await B06Engine.wait(timeout) { w.styleMask.contains(.fullScreen) == on }
        await B06QA.spin(1.2)   // Animation abwarten
        return t
    }

    // MARK: AK-01 / AK-14

    func testAK01_AK14_LadekreisSteuerungNurBeimSpielenUndAusblenden() async throws {
        let c = channel("QA Live", "/livehls/ak14/index.m3u8")
        let t0 = Date()
        let w = player(c)
        let spinnerAmAnfang = busy(w)
        let controlsBeimLaden = controlsVisible(w)
        B06QA.shot(w, "AK-01-ladekreis")
        try await activate(w)
        B06QA.log("AK-01|titel=\(w.title)|ladekreis=\(spinnerAmAnfang)|steuerungBeimLaden=\(controlsBeimLaden)|nach=\(B06QA.f1(Date().timeIntervalSince(t0)))s")
        XCTAssertEqual(w.title, "QA Live")
        XCTAssertTrue(spinnerAmAnfang)
        XCTAssertFalse(controlsBeimLaden)
        let playT = await B06Engine.wait(8) { self.av?.currentItem?.status == .readyToPlay && self.controlsVisible(w) }
        let p = try XCTUnwrap(av)
        B06QA.log("AK-01|spielt nach \(B06QA.f1(Date().timeIntervalSince(t0)))s|volume=\(p.volume)|muted=\(p.isMuted)|rate=\(p.rate)")
        XCTAssertNotNil(playT)
        XCTAssertEqual(p.volume, 1.0)
        XCTAssertFalse(p.isMuted, "startet nicht stumm (Medium ohne Tonspur)")
        XCTAssertEqual(p.rate, 1.0, "startet von selbst")
        XCTAssertFalse(busy(w))
        B06QA.shot(w, "AK-14-steuerung-sichtbar")
        _ = await B06Engine.wait(6, step: 0.05) { !self.controlsVisible(w) }
        let sinceOpen = Date().timeIntervalSince(t0)
        B06QA.log("AK-14|ausgeblendet nach \(B06QA.f1(sinceOpen))s ab Öffnen")
        XCTAssertEqual(sinceOpen, 3.6, accuracy: 0.5, "≈ 3,5 s ab Öffnen")
        B06QA.shot(w, "AK-14-steuerung-ausgeblendet")

        // Klick auf das Bild schaltet ein und aus (nur mit Schlüsselfenster – ein Klick in ein inaktives Fenster
        // aktiviert es zuerst und erreicht die Ansicht nicht)
        try? await activate(w)
        if NSApp.keyWindow === w {
            B06UI.click(w, at: NSPoint(x: 320, y: 200))
            await B06QA.spin(0.5)
            let nachKlick1 = controlsVisible(w)
            B06UI.click(w, at: NSPoint(x: 320, y: 200))
            await B06QA.spin(0.5)
            let nachKlick2 = controlsVisible(w)
            B06QA.log("AK-14|klick1 sichtbar=\(nachKlick1)|klick2 sichtbar=\(nachKlick2)|keyWindow=true")
            XCTAssertTrue(nachKlick1)
            XCTAssertFalse(nachKlick2)
        } else {
            B06QA.log("AK-14|Klickteil übersprungen: Fenster nicht Schlüsselfenster (fremde App im Vordergrund)")
        }

        // Lautstärketaste blendet nicht ein, Leertaste schon
        B06UI.key(w, .up)
        await B06QA.spin(0.3)
        let nachUp = controlsVisible(w)
        let hudUp = hudImage(w)
        B06UI.key(w, .space)
        await B06QA.spin(0.3)
        let nachSpace = controlsVisible(w)
        let s0 = Date()
        _ = await B06Engine.wait(6) { !self.controlsVisible(w) }
        let flashDauer = Date().timeIntervalSince(s0) + 0.3
        B06QA.log("AK-14|↑ blendet ein=\(nachUp) (HUD=\(hudUp ?? "-"))|Leertaste blendet ein=\(nachSpace)|sichtbar ≈\(B06QA.f1(flashDauer))s")
        XCTAssertFalse(nachUp)
        XCTAssertNotNil(hudUp)
        XCTAssertTrue(nachSpace)
        XCTAssertEqual(flashDauer, 3.5, accuracy: 0.6)
        B06UI.key(w, .space)
        await B06QA.spin(0.3)

        // „ab Öffnen, nicht ab Spielbeginn“: Stream, der erst nach > 3,5 s spielt, zeigt keine Steuerung von selbst
        let t1 = Date()
        let wSlow = player(channel("QA Live verzögert", "/delay/5/livehls/ak14slow/index.m3u8"), origin: CGPoint(x: 760, y: 120))
        var controlsWhileLoading = false
        while av === p || av?.currentItem?.status != .readyToPlay {
            if controlsVisible(wSlow) { controlsWhileLoading = true }
            if Date().timeIntervalSince(t1) > 20 { break }
            await B06QA.spin(0.1)
        }
        let startSlow = Date().timeIntervalSince(t1)
        await B06QA.spin(0.5)
        let slowControls = controlsVisible(wSlow)
        B06QA.log("AK-14|verzögert|spielt nach \(B06QA.f1(startSlow))s|steuerungWährendLaden=\(controlsWhileLoading)|steuerungNachSpielbeginn=\(slowControls)|ladekreis=\(busy(wSlow))")
        XCTAssertFalse(controlsWhileLoading, "nie beim Laden")
        if startSlow > 4 { XCTAssertFalse(slowControls, "Auto-Ausblenden lief bereits ab Öffnen ab") }
    }

    // MARK: AK-13 / AK-04 / AK-31 / AK-10 (Ansicht)

    func testAK13_AK04_AK31_Fehleransichten() async throws {
        let store = XtreamCredentialStore.standard
        let ctx = container.mainContext
        // a) AVKit 404 (M3U)
        let wA = player(channel("QA 404", "/404/ak13.m3u8"), origin: CGPoint(x: 40, y: 60), size: CGSize(width: 560, height: 360))
        // b) Xtream ohne Zugangsdaten, gespeicherte Adresse .ts
        let miss = Playlist(name: "X ohne", sourceURL: mock.url("/player_api.php"), isXtream: true, xtreamOutput: "mpegts")
        ctx.insert(miss)
        let requestsBefore = mock.requests.count
        let wB = player(channel("QA fehlt", "/live/104.ts", in: miss), origin: CGPoint(x: 620, y: 60), size: CGSize(width: 560, height: 360))
        let busyB0 = busy(wB)          // vor dem ersten Durchlauf der Ereignisschleife (onAppear noch nicht gelaufen)
        await B06QA.spin(0.05)
        let busyB = busy(wB)
        // c) Xtream, Adresse ohne /live/
        let x = Playlist(name: "X", sourceURL: mock.url("/player_api.php"), isXtream: true, xtreamOutput: "hls")
        ctx.insert(x)
        try store.save(XtreamSecret(host: mock.base, username: B06QA.user, password: B06QA.pass), for: x.id)
        let wC = player(channel("QA ungültig", "/stream/103.m3u8", in: x), origin: CGPoint(x: 40, y: 460), size: CGSize(width: 560, height: 360))
        // d) Xtream 404 mit Zugangsdaten im Pfad (AK-31)
        let wD = player(channel("QA X 404", "/live/404/102.m3u8", in: x), origin: CGPoint(x: 620, y: 460), size: CGSize(width: 560, height: 360))
        _ = await B06Engine.wait(6) { B06UI.has(wA, "Erneut versuchen") && B06UI.has(wD, "Erneut versuchen") }
        await B06QA.spin(0.5)

        let la = B06UI.labels(wA), lb = B06UI.labels(wB), lc = B06UI.labels(wC), ld = B06UI.labels(wD)
        B06QA.log("AK-13|a 404|\(la)")
        B06QA.log("AK-13|b fehlt|\(lb)|ladekreisVorOnAppear=\(busyB0)|ladekreisNach50ms=\(busyB)")
        B06QA.log("AK-13|c ungültig|\(lc)")
        B06QA.log("AK-13|d xtream404|\(ld.map { $0.replacingOccurrences(of: B06QA.pass, with: "<pass>") })")
        B06QA.shot(wA, "AK-13-fehleransicht-avkit-404")
        B06QA.shot(wB, "AK-04-AK-13-zugangsdaten-fehlen-mit-readme-hinweis")
        B06QA.shot(wC, "AK-04-adresse-ungueltig")
        let hint = "Hinweis: Rohe MPEG-TS-Streams (.ts) benötigen VLCKit – siehe README."
        func has(_ l: [String], _ t: String) -> Bool { l.contains { $0.contains(t) } }
        XCTAssertTrue(has(la, "Wiedergabe fehlgeschlagen") && has(la, "The requested URL was not found on this server.") && has(la, "Erneut versuchen"))
        XCTAssertFalse(has(la, hint))
        XCTAssertFalse(has(la, "pause.fill") || has(la, "arrow.up.left.and.arrow.down.right"), "keine Steuerung in der Fehleransicht")
        XCTAssertTrue(has(lb, "Die Zugangsdaten dieser Xtream-Playlist fehlen auf diesem Gerät. Bitte die Playlist löschen und neu importieren."))
        XCTAssertTrue(has(lb, hint), "Ist: README-Hinweis bei fehlenden Zugangsdaten (FB-04)")
        XCTAssertFalse(busyB, "ohne Ladekreis")
        XCTAssertTrue(has(lc, "Die Stream-Adresse ist ungültig."))
        for l in [la, lb, lc, ld] {
            for secret in [B06QA.pass, B06QA.user, "127.0.0.1", "/live/"] { XCTAssertFalse(has(l, secret), "AK-31: \(secret) sichtbar") }
        }
        let xtreamRequests = mock.requests(containing: "/live/").map { $0.target.replacingOccurrences(of: B06QA.pass, with: "<pass>") }
        B06QA.log("AK-04|anfragen /live/ gesamt=\(xtreamRequests)|vorher=\(requestsBefore)")
        XCTAssertFalse(xtreamRequests.contains { $0.contains("104") }, "AK-04: keine Anfrage für den Sender ohne Zugangsdaten")
        // „Erneut versuchen“ bei fehlenden Zugangsdaten: dieselbe Meldung, keine Anfrage
        B06UI.press(try XCTUnwrap(B06UI.find(wB, role: "AXButton", "Erneut versuchen")))
        await B06QA.spin(1.0)
        XCTAssertTrue(B06UI.has(wB, "Die Zugangsdaten dieser Xtream-Playlist fehlen"))
        XCTAssertFalse(mock.requests(containing: "/live/").contains { $0.target.contains("104") })
        XCTExpectFailure("BUG-04 · README-Hinweis erscheint bei fehlenden Zugangsdaten, obwohl VLCKit eingebunden ist (FB-04)") {
            XCTAssertFalse(has(lb, hint))
        }
    }

    func testAK10_AK11_VLCFehlerInDerAnsicht() async throws {
        let w404 = player(channel("QA TS 404", "/404/ak10ui.ts"), origin: CGPoint(x: 40, y: 80), size: CGSize(width: 560, height: 360))
        let wHang = player(channel("QA TS Hänger", "/hang/ak11ui.ts"), origin: CGPoint(x: 620, y: 80), size: CGSize(width: 560, height: 360))
        await B06QA.spin(0.8)
        let hangControls = controlsVisible(wHang)
        B06QA.shot(wHang, "AK-11-vlc-haenger-steuerung-wie-laeuft")
        await B06QA.spin(11)
        let l404 = B06UI.labels(w404)
        B06QA.log("AK-10|ansicht nach 12s|busy=\(busy(w404))|labels=\(l404)|anfragen=\(mock.requests(containing: "ak10ui").count)")
        B06QA.log("AK-11|ansicht|steuerungNach0,8s=\(hangControls)|nach12s labels=\(B06UI.labels(wHang))")
        B06QA.shot(w404, "AK-10-vlc-404-ladekreis-ohne-meldung")
        B06QA.shot(wHang, "AK-11-vlc-haenger-schwarz-ohne-meldung")
        XCTAssertTrue(busy(w404), "Ist: Ladekreis ohne Ende")
        XCTAssertTrue(hangControls, "Ist: Hänger zeigt Steuerung wie ein laufender Stream")
        XCTExpectFailure("BUG-01 · VLC-Fehler erreichen die Oberfläche nie (FB-01)") {
            XCTAssertTrue(B06UI.has(w404, "Erneut versuchen"))
            XCTAssertTrue(B06UI.has(wHang, "Erneut versuchen"))
        }
    }

    // MARK: AK-08 / Angriff 3

    func testAK08_Angriff3_ErneutVersuchenOhneBremse() async throws {
        let w = player(channel("QA Retry", "/404/ak08.m3u8"))
        _ = await B06Engine.wait(6) { B06UI.has(w, "Erneut versuchen") }
        await B06QA.spin(0.5)
        let initial = mock.requests(containing: "ak08")
        B06QA.log("AK-08|erstes Öffnen|anfragen=\(initial.map { "conn=\($0.conn) \($0.method) \($0.target) +\(B06QA.f1($0.time.timeIntervalSince(initial[0].time)))s UA=\($0.userAgent) Kopf=\($0.headers.keys.sorted())" })")
        let perOpen = initial.count
        var counts: [Int] = []
        var sawSpinner = false
        for _ in 0..<2 {
            B06UI.press(try XCTUnwrap(B06UI.find(w, role: "AXButton", "Erneut versuchen")))
            let t0 = Date()
            while Date().timeIntervalSince(t0) < 0.6 { if busy(w) { sawSpinner = true }; await B06QA.spin(0.01) }
            _ = await B06Engine.wait(4) { B06UI.has(w, "Erneut versuchen") }
            counts.append(mock.requests(containing: "ak08").count)
        }
        B06QA.log("AK-08|zwei Versuche|anfragenNachJeVersuch=\(counts)|ladekreisGesehen=\(sawSpinner)|players=\(B06Registry.avPlayers.count)")
        XCTAssertEqual(counts, [perOpen * 2, perOpen * 3], "je Versuch derselbe Abruf wie beim Öffnen (\(perOpen) Anfragen)")
        XCTAssertEqual(B06Registry.avPlayers.count, 1, "dieselbe Engine (ein AVPlayer)")
        // Angriff 3: zehnmal schnell hintereinander
        let before = mock.requests(containing: "ak08").count
        let t0 = Date()
        for _ in 0..<10 {
            if let b = B06UI.find(w, role: "AXButton", "Erneut versuchen") { B06UI.press(b) }
            _ = await B06Engine.wait(3) { B06UI.has(w, "Erneut versuchen") }
        }
        let after = mock.requests(containing: "ak08").count
        B06QA.log("ANGRIFF-3|10 Versuche in \(B06QA.f1(Date().timeIntervalSince(t0)))s|neueAnfragen=\(after - before)")
        XCTAssertEqual(after - before, 10 * perOpen, "keine Drosselung")
    }

    // MARK: AK-15 … AK-19, EC-07 · Tasten und HUD (AVKit)

    func testAK15_AK16_AK17_AK18_AK19_EC07_TastenUndHUD() async throws {
        let w = player(channel("QA Tasten", "/livehls/keys/index.m3u8"))
        _ = await B06Engine.wait(8) { self.av?.currentItem?.status == .readyToPlay }
        let p = try XCTUnwrap(av)
        await B06QA.spin(0.5)
        // AK-19: ohne vorherigen Klick
        B06UI.key(w, .space)
        await B06QA.spin(0.25)
        let hudPause = hudImage(w)
        B06QA.shot(w, "AK-15-hud-pause")
        let playButton = button(w, "play.fill") != nil
        B06QA.log("AK-15|Leertaste|rate=\(p.rate)|hud=\(hudPause ?? "-")|knopfPlay=\(playButton)")
        XCTAssertEqual(p.rate, 0)
        XCTAssertTrue(hudPause?.contains("pause.fill") == true, "HUD zeigt den neuen Zustand (Pause-Balken)")
        XCTAssertTrue(playButton, "Knopf zeigt ▶")
        await B06QA.spin(1.1)
        XCTAssertNil(hudImage(w), "HUD nach 0,9 s weg")
        B06UI.key(w, .space)
        await B06QA.spin(0.25)
        B06QA.log("AK-15|Leertaste 2|rate=\(p.rate)|hud=\(hudImage(w) ?? "-")")
        XCTAssertEqual(p.rate, 1)
        XCTAssertTrue(hudImage(w)?.contains("play.fill") == true)
        // Play/Pause-Knopf (Aktion des Knopfs)
        B06UI.press(try XCTUnwrap(button(w, "pause.fill")))
        await B06QA.spin(0.25)
        XCTAssertEqual(p.rate, 0)
        B06UI.press(try XCTUnwrap(button(w, "play.fill")))
        await B06QA.spin(0.25)
        XCTAssertEqual(p.rate, 1)

        // AK-16: M, Umschalt-M, Feststell-m, Knopf
        await B06QA.spin(1.0)
        B06UI.key(w, .char("m"))
        await B06QA.spin(0.25)
        let hudMute = hudImage(w)
        B06QA.shot(w, "AK-16-hud-stumm")
        B06QA.log("AK-16|m|muted=\(p.isMuted)|volume=\(p.volume)|hud=\(hudMute ?? "-")|knopf=\(button(w, "speaker.slash.fill") != nil)")
        XCTAssertTrue(p.isMuted)
        XCTAssertTrue(hudMute?.contains("speaker.slash.fill") == true)
        XCTAssertEqual(p.volume, 1.0, "Lautstärkewert bleibt")
        B06UI.key(w, .char("M"), flags: .shift)
        await B06QA.spin(0.2)
        XCTAssertFalse(p.isMuted, "Umschalt-M")
        B06UI.key(w, .char("M"), flags: .capsLock)
        await B06QA.spin(0.2)
        XCTAssertTrue(p.isMuted, "Feststelltaste")
        B06UI.press(try XCTUnwrap(button(w, "speaker.slash.fill")))
        await B06QA.spin(0.2)
        XCTAssertFalse(p.isMuted, "Stumm-Knopf")

        // AK-17 + AK-18: ↑ + = ↓ -, Grenzen, HUD-Text
        for _ in 0..<3 { B06UI.key(w, .up) }
        await B06QA.spin(0.2)
        let hud100 = B06UI.labels(w).filter { $0.contains("%") }
        B06QA.shot(w, "AK-17-hud-lautstaerke-100")
        B06QA.log("AK-17|3x↑ bei 100|volume=\(p.volume)|hudTexte=\(hud100)")
        XCTAssertEqual(p.volume, 1.0)
        XCTAssertTrue(hud100.contains { $0.contains("100 %") })
        for _ in 0..<20 { B06UI.key(w, .down) }
        await B06QA.spin(0.2)
        B06QA.log("AK-17|20x↓|volume=\(p.volume)|hud=\(B06UI.labels(w).filter { $0.contains("%") })")
        XCTAssertEqual(p.volume, 0, accuracy: 0.0001)
        XCTAssertTrue(B06UI.labels(w).contains { $0.contains("0 %") })
        B06UI.key(w, .char("+"), flags: .shift)
        B06UI.key(w, .char("="))
        await B06QA.spin(0.2)
        XCTAssertEqual(p.volume, 0.10, accuracy: 0.001, "+ und = je +5")
        B06UI.key(w, .char("-"))
        await B06QA.spin(0.2)
        XCTAssertEqual(p.volume, 0.05, accuracy: 0.001, "- je −5")
        // ↓ hebt Stumm auf (OF-02)
        B06UI.key(w, .up)
        B06UI.key(w, .char("m"))
        await B06QA.spin(0.2)
        XCTAssertTrue(p.isMuted)
        B06UI.key(w, .down)
        await B06QA.spin(0.2)
        B06QA.log("AK-17|stumm, dann ↓|muted=\(p.isMuted)|volume=\(p.volume)")
        XCTAssertFalse(p.isMuted, "OF-02: ↓ auf einen Wert > 0 hebt Stumm auf")

        // EC-07: ⌘↑ ohne Menübefehl wirkt wie ↑ (über NSApp.sendEvent, Menü-Tastenkürzel zuerst)
        let v0 = p.volume
        B06UI.key(w, .up, flags: .command, viaApp: true)
        await B06QA.spin(0.3)
        B06QA.log("EC-07|⌘↑ über NSApp|vorher=\(v0)|nachher=\(p.volume)|keyWindow=\(NSApp.keyWindow === w)")
        if NSApp.keyWindow === w { XCTAssertEqual(p.volume, v0 + 0.05, accuracy: 0.001) }

        // AK-19: nach Klick auf das Bild weiter per Taste bedienbar
        B06UI.click(w, at: NSPoint(x: 320, y: 200))
        await B06QA.spin(0.3)
        B06UI.key(w, .space)
        await B06QA.spin(0.3)
        XCTAssertEqual(p.rate, 0, "AK-19: nach Klick")
        B06UI.key(w, .space)
        XCTAssertEqual(B06BeepGuard.hits, [])
    }

    // MARK: AK-20 / AK-15 · VLC

    func testAK20_AK15_VLCTasteP() async throws {
        let w = player(channel("QA TS Tasten", "/tslive/ak20.ts"))
        _ = await B06Engine.wait(6) { (B06Registry.liveVLCEngines.last?.state ?? .idle) == .playing }
        let e = try XCTUnwrap(B06Registry.liveVLCEngines.last)
        let v = try XCTUnwrap(B06Registry.liveVLCPlayers.last)
        _ = await B06Engine.wait(6) { !self.controlsVisible(w) }
        XCTAssertFalse(controlsVisible(w))
        B06UI.key(w, .char("p"))
        await B06QA.spin(0.3)
        let ctrl = controlsVisible(w)
        let hud = hudImage(w)
        B06QA.shot(w, "AK-20-vlc-taste-p-nur-steuerung")
        B06QA.log("AK-20|P|steuerung=\(ctrl)|hud=\(hud ?? "-")|pipKnopf=\(button(w, "pip") != nil)|beeps=\(B06BeepGuard.hits)")
        XCTAssertTrue(ctrl)
        XCTAssertNil(hud)
        XCTAssertNil(button(w, "pip"), "kein PiP-Knopf bei VLC")
        B06UI.key(w, .space)
        await B06QA.spin(1.0)
        B06QA.log("AK-15|VLC Leertaste|isPaused=\(e.isPaused)|vlc=\(B06Engine.vlcState(v))|hud=\(hudImage(w) ?? "-")")
        XCTAssertEqual(B06Engine.vlcState(v), "paused")
        B06UI.key(w, .space)
        await B06QA.spin(1.0)
        XCTAssertEqual(B06Engine.vlcState(v), "playing")
        B06UI.key(w, .char("m"))
        await B06QA.spin(0.3)
        B06QA.log("AK-16|VLC m|isMuted=\(e.isMuted)|audio=\(B06Engine.vlcAudio(v))")
        XCTAssertTrue(e.isMuted)
        XCTAssertEqual(B06Engine.vlcAudio(v).muted, true)
    }

    // MARK: AK-21 / AK-19 / EC-07 · Vollbild

    func testAK21_AK19_EC07_VollbildTastenUndZurueck() async throws {
        let nav = B06Nav()
        let w = B06UI.window(B06StackHost(nav: nav).modelContainer(container), size: CGSize(width: 640, height: 400), title: "B06-QA Vollbild")
        windows.append(w)
        try await activate(w)
        let c = channel("QA Vollbild", "/livehls/ak21/index.m3u8")
        nav.path = [c]
        _ = await B06Engine.wait(8) { self.av?.currentItem?.status == .readyToPlay }
        let p = try XCTUnwrap(av)
        let frameBefore = w.frame
        B06UI.key(w, .char("f"))
        let tOn = await waitFullscreen(w, true)
        let fsButton = button(w, "arrow.down.right.and.arrow.up.left")
        let fr = fsButton.map(B06UI.frame) ?? .zero
        let screen = w.screen?.frame ?? .zero
        B06QA.shot(w, "AK-21-vollbild-nativ")
        B06QA.log("AK-21|F|vollbild=\(w.styleMask.contains(.fullScreen)) nach \(tOn.map(B06QA.f1) ?? "-")s|fenster=\(w.frame)|bildschirm=\(screen)|titel='\(w.title)'|knopf=\(fr)|abstandRechts=\(screen.maxX - fr.maxX)|abstandOben=\(screen.maxY - fr.maxY)")
        XCTAssertNotNil(tOn)
        XCTAssertEqual(w.frame.width, screen.width, "ganze Bildschirmbreite")
        XCTAssertGreaterThan(w.frame.height, screen.height - 80, "ganze Höhe (ohne Menüleistenbereich)")
        XCTAssertEqual(w.title, "", "Titel leer im Vollbild")
        XCTAssertEqual(screen.maxX - fr.maxX, 24, accuracy: 2, "Knopf 24 pt vom Rand")
        // AK-19: Tasten wirken im Vollbild ohne Klick
        B06UI.key(w, .space)
        await B06QA.spin(0.3)
        XCTAssertEqual(p.rate, 0, "AK-19 nach Vollbildwechsel")
        B06UI.key(w, .space)
        // Esc zurück
        B06UI.key(w, .escape)
        let tOff = await waitFullscreen(w, false)
        B06QA.log("AK-21|Esc|vollbild=\(w.styleMask.contains(.fullScreen)) nach \(tOff.map(B06QA.f1) ?? "-")s|fenster=\(w.frame)|vorher=\(frameBefore)|titel='\(w.title)'")
        XCTAssertNotNil(tOff)
        XCTAssertEqual(w.frame.origin.x, frameBefore.origin.x, accuracy: 2, "vorherige Fensterposition")
        XCTAssertEqual(w.frame.width, frameBefore.width, accuracy: 2, "vorherige Fensterbreite")
        XCTAssertEqual(w.frame.height, frameBefore.height, accuracy: 2, "vorherige Fensterhöhe")
        XCTAssertEqual(w.title, "QA Vollbild")
        // EC-07: ⌘F über NSApp (kein Menübefehl dafür im Test-Host?) — Ergebnis protokollieren
        B06UI.key(w, .char("f"), flags: .command, viaApp: true)
        let tCmd = await waitFullscreen(w, true, 4)
        B06QA.log("EC-07|⌘F|vollbild=\(w.styleMask.contains(.fullScreen))|nach=\(tCmd.map(B06QA.f1) ?? "-")")
        XCTAssertNotNil(tCmd, "⌘F wirkt wie F")
        // „Zurück“ im Vollbild (Pfad leeren wie der Zurück-Knopf) → Fenster verlässt das Vollbild
        nav.path = []
        let tBack = await waitFullscreen(w, false)
        B06QA.log("AK-21|Zurück im Vollbild|vollbild=\(w.styleMask.contains(.fullScreen))|nach=\(tBack.map(B06QA.f1) ?? "-")")
        XCTAssertNotNil(tBack, "Verlassen des Players beendet das Vollbild")
    }

    // MARK: AK-22 · Hover oben im Vollbild

    func testAK22_HoverAmOberenRandImVollbild() async throws {
        let w = player(channel("QA Hover", "/livehls/ak22/index.m3u8"))
        try await activate(w)
        _ = await B06Engine.wait(8) { self.av?.currentItem?.status == .readyToPlay }
        B06UI.key(w, .char("f"))
        _ = await waitFullscreen(w, true)
        _ = await B06Engine.wait(6) { !self.controlsVisible(w) }
        let hiddenBefore = !controlsVisible(w)
        let h = w.contentView?.bounds.height ?? 0
        for y in stride(from: h / 2, through: h - 20, by: 40) { B06UI.move(w, to: NSPoint(x: 300, y: y)); await B06QA.spin(0.05) }
        await B06QA.spin(0.5)
        let shown = controlsVisible(w)
        B06QA.log("AK-22|versteckt vorher=\(hiddenBefore)|nach mouseMoved oben=\(shown)|toolbar=\(String(describing: w.toolbar?.isVisible))")
        B06UI.key(w, .escape)
        _ = await waitFullscreen(w, false)
        if !shown { throw XCTSkip("Synthetische Mausbewegung erreicht onContinuousHover nicht – AK-22 so nicht prüfbar") }
    }

    // MARK: AK-23 ⚠ · zwei Fenster

    func testAK23_ZweiFensterVollbildTrifftSchluesselfenster() async throws {
        let wA = player(channel("QA Fenster A", "/livehls/ak23/index.m3u8"), origin: CGPoint(x: 60, y: 120))
        _ = await B06Engine.wait(8) { self.av?.currentItem?.status == .readyToPlay }
        let wB = B06UI.window(Text("Fenster B (Senderliste)").frame(maxWidth: .infinity, maxHeight: .infinity), origin: CGPoint(x: 740, y: 120), title: "B06-QA Fenster B")
        windows.append(wB)
        try await activate(wB)
        B06UI.press(try XCTUnwrap(button(wA, "arrow.up.left.and.arrow.down.right")))   // Aktion des Knopfs in A, B ist Schlüsselfenster
        _ = await B06Engine.wait(6) { wB.styleMask.contains(.fullScreen) || wA.styleMask.contains(.fullScreen) }
        await B06QA.spin(1.5)
        let aFS = wA.styleMask.contains(.fullScreen), bFS = wB.styleMask.contains(.fullScreen)
        B06QA.shot(wB, "AK-23-fenster-b-im-vollbild")
        B06QA.shot(wA, "AK-23-fenster-a-player-ohne-titel")
        B06QA.log("AK-23|A vollbild=\(aFS) titel='\(wA.title)'|B vollbild=\(bFS)|knopfA=\(button(wA, "arrow.down.right.and.arrow.up.left") != nil ? "Vollbild-aus-Symbol" : "Vollbild-an-Symbol")")
        XCTAssertTrue(bFS, "Ist: Fenster B geht ins Vollbild")
        XCTAssertFalse(aFS)
        XCTAssertEqual(wA.title, "", "Fenster A verliert den Titel")
        // dieselbe Aktion noch einmal holt B zurück
        B06UI.press(try XCTUnwrap(button(wA, "arrow.down.right.and.arrow.up.left") ?? button(wA, "arrow.up.left.and.arrow.down.right")))
        _ = await waitFullscreen(wB, false)
        B06QA.log("AK-23|zweite Aktion|B vollbild=\(wB.styleMask.contains(.fullScreen))|A titel='\(wA.title)'")
        XCTAssertFalse(wB.styleMask.contains(.fullScreen))
        XCTExpectFailure("BUG-06 · Vollbild-Aktion des Players schaltet das Schlüsselfenster statt des Player-Fensters (FB-06)") {
            XCTAssertTrue(aFS)
            XCTAssertFalse(bFS)
        }
    }

    // MARK: AK-24 ⚠ · grüner Knopf

    func testAK24_GruenerKnopfVerstimmtPlayer() async throws {
        let w = player(channel("QA Grün", "/livehls/ak24/index.m3u8"))
        try await activate(w)
        _ = await B06Engine.wait(8) { self.av?.currentItem?.status == .readyToPlay }
        w.toggleFullScreen(nil)   // wie der grüne Knopf / Menü „Enter Full Screen“
        _ = await waitFullscreen(w, true)
        B06UI.press(try XCTUnwrap(button(w, "pause.fill")))   // Steuerung einblenden
        await B06QA.spin(0.3)
        let fr = button(w, "arrow.up.left.and.arrow.down.right").map(B06UI.frame)
        let screen = w.screen?.frame ?? .zero
        B06QA.shot(w, "AK-24-gruener-knopf-player-in-fensterdarstellung")
        B06QA.log("AK-24|grüner Knopf|vollbild=\(w.styleMask.contains(.fullScreen))|titel='\(w.title)'|knopfSymbol=\(fr != nil ? "Vollbild-an" : "Vollbild-aus")|abstandRechts=\(fr.map { screen.maxX - $0.maxX } ?? -1)")
        XCTAssertNotNil(fr, "Player hält sich nicht für Vollbild")
        XCTAssertEqual(screen.maxX - (fr?.maxX ?? 0), 12, accuracy: 2, "normaler Abstand 12 pt")
        XCTAssertEqual(w.title, "QA Grün")
        B06UI.key(w, .space)   // weiterlaufen lassen
        B06UI.key(w, .char("f"))
        await B06QA.spin(2.0)
        let afterF1 = w.styleMask.contains(.fullScreen)
        B06QA.log("AK-24|erstes F|vollbild=\(afterF1)|titel='\(w.title)'")
        XCTAssertTrue(afterF1, "erstes F verlässt das Vollbild nicht")
        XCTAssertEqual(w.title, "")
        B06UI.key(w, .char("f"))
        let off = await waitFullscreen(w, false)
        B06QA.log("AK-24|zweites F|vollbild=\(w.styleMask.contains(.fullScreen))|nach=\(off.map(B06QA.f1) ?? "-")")
        XCTAssertNotNil(off, "erst das zweite F verlässt das Vollbild")
        XCTExpectFailure("BUG-06 · Vollbild über grünen Knopf/Menü ist dem Player unbekannt (FB-06)") {
            XCTAssertNil(fr)
            XCTAssertFalse(afterF1)
        }
    }

    // MARK: AK-27 / AK-19 · Tabwechsel (VLC)

    func testAK27_AK19_TabwechselPausiertUndSetztFort() async throws {
        let nav = B06Nav()
        let w = B06UI.window(B06TabHost(nav: nav).modelContainer(container), size: CGSize(width: 640, height: 440), title: "B06-QA Tabs")
        windows.append(w)
        nav.path = [channel("QA Tab TS", "/tslive/ak27.ts")]
        _ = await B06Engine.wait(8) { (B06Registry.liveVLCEngines.last?.state ?? .idle) == .playing }
        let v = try XCTUnwrap(B06Registry.liveVLCPlayers.last)
        await B06QA.spin(1)
        let connsBefore = mock.connections(containing: "ak27").map(\.id)
        nav.tab = 1
        await B06QA.spin(2.5)
        let away = B06Engine.vlcState(v)
        nav.tab = 0
        await B06QA.spin(2.5)
        let back = B06Engine.vlcState(v)
        let conns = mock.connections(containing: "ak27")
        B06QA.log("AK-27|anderer Tab: vlc=\(away)|zurück: vlc=\(back)|verbindungen vorher=\(connsBefore) nachher=\(conns.map { "\($0.id):\($0.closed == nil ? "offen" : "zu")" })|anfragen=\(mock.requests(containing: "ak27").count)|engines=\(B06Registry.vlcEngines.count)")
        XCTAssertEqual(away, "paused")
        XCTAssertEqual(back, "playing")
        XCTAssertEqual(B06Registry.vlcEngines.count, 1, "dieselbe Engine")
        XCTAssertEqual(mock.requests(containing: "ak27").count, 1, "ohne neuen Aufbau")
        // AK-19: Taste ohne Klick nach Rückkehr
        B06UI.key(w, .space)
        await B06QA.spin(1.0)
        B06QA.log("AK-19|nach Tabwechsel Leertaste|vlc=\(B06Engine.vlcState(v))")
        XCTAssertEqual(B06Engine.vlcState(v), "paused")
        B06UI.key(w, .space)
    }

    // MARK: AK-28 ⚠ · Verlassen

    func testAK28_VerlassenBeendetEngineUndVerbindungNicht() async throws {
        let nav = B06Nav()
        let w = B06UI.window(B06StackHost(nav: nav).modelContainer(container), title: "B06-QA Zurück")
        windows.append(w)
        // HLS live
        nav.path = [channel("QA Zurück HLS", "/livehls/ak28/index.m3u8")]
        _ = await B06Engine.wait(8) { self.av?.currentItem?.status == .readyToPlay }
        await B06QA.spin(2)
        weak var weakAV = av
        nav.path = []
        let tBack = Date()
        await B06QA.spin(12)
        let hlsAfter = mock.requests(containing: "/livehls/ak28/").filter { $0.time > tBack.addingTimeInterval(1) }
        B06QA.log("AK-28|HLS|12s nach Zurück|anfragen=\(hlsAfter.count) (playlist=\(hlsAfter.filter { $0.path.hasSuffix(".m3u8") }.count), segmente=\(hlsAfter.filter { $0.path.contains("seg") }.count))|avPlayerLebt=\(weakAV != nil)|rate=\(weakAV?.rate ?? -1)")
        // TS
        nav.path = [channel("QA Zurück TS", "/tslive/ak28.ts")]
        _ = await B06Engine.wait(8) { (B06Registry.liveVLCEngines.last?.state ?? .idle) == .playing }
        await B06QA.spin(2)
        weak var weakVLC = B06Registry.liveVLCPlayers.last
        nav.path = []
        let tBackTS = Date()
        var timeline: [String] = []
        for s in [1.0, 3.0, 6.0, 12.0] {
            await B06QA.spin(s - Date().timeIntervalSince(tBackTS))
            let c = mock.connections(containing: "ak28.ts").last
            timeline.append("+\(Int(s))s: engine=\(weakVLC != nil ? B06Engine.vlcState(weakVLC!) : "frei") verbindung=\(c?.closed == nil ? "offen" : "zu(\(c?.closeReason ?? ""))") bytes=\(c?.bytesSent ?? 0)")
        }
        B06QA.log("AK-28|TS|\(timeline)")
        let tsOpen = mock.connections(containing: "ak28.ts").last?.closed == nil
        B06QA.log("AK-28|HLS-Player lebt nach Öffnen des TS-Senders=\(weakAV != nil)")
        XCTExpectFailure("BUG-02 · Verlassen beendet Engine und Verbindung nicht (FB-02)") {
            XCTAssertEqual(hlsAfter.count, 0, "nach Zurück keine weiteren HLS-Abrufe")
            XCTAssertFalse(tsOpen, "TS-Verbindung nach Zurück geschlossen")
        }
    }

    /// Wie lange liest die pausierte, verlassene VLC-Engine weiter? (Loopback-Puffer füllen sich erst nach MB)
    func testAK28b_VerlassenTSVerbindungLangBeobachtet() async throws {
        let nav = B06Nav()
        let w = B06UI.window(B06StackHost(nav: nav).modelContainer(container), title: "B06-QA Zurück lang")
        windows.append(w)
        nav.path = [channel("QA Zurück TS lang", "/tslive/ak28b.ts")]
        _ = await B06Engine.wait(8) { (B06Registry.liveVLCEngines.last?.state ?? .idle) == .playing }
        await B06QA.spin(3)
        weak var v = B06Registry.liveVLCPlayers.last
        nav.path = []
        let t0 = Date()
        var line: [String] = []
        var lastBytes = mock.connections(containing: "ak28b").last?.bytesSent ?? 0
        for i in 1...9 {
            await B06QA.spin(Double(i * 5) - Date().timeIntervalSince(t0))
            let c = mock.connections(containing: "ak28b").last
            let b = c?.bytesSent ?? 0
            line.append("+\(i * 5)s: vlc=\(v.map { "\(B06Engine.vlcState($0))/spielt=\(B06Engine.vlcIsPlaying($0))" } ?? "frei") verbindung=\(c?.closed == nil ? "offen" : "zu") Δbytes/5s=\(b - lastBytes)")
            lastBytes = b
        }
        B06QA.log("AK-28b|TS nach Zurück (Rate \(Int(mock.media.tsRate)) B/s)|\(line)")
        let open = mock.connections(containing: "ak28b").last?.closed == nil
        // Lebensdauer schwankt (Erfassung: 0,2 s bis > 90 s); nicht strikt
        let options = XCTExpectedFailure.Options()
        options.isStrict = false
        XCTExpectFailure("BUG-02 · verlassene VLC-Engine hält die Verbindung (FB-02) – nicht in jedem Lauf", options: options) {
            XCTAssertFalse(open)
        }
    }

    // MARK: AK-29 ⚠ · Verlassen, während VLC lädt

    func testAK29_VerlassenWaehrendTSLaedtStreamLaeuftWeiter() async throws {
        let nav = B06Nav()
        let w = B06UI.window(B06StackHost(nav: nav).modelContainer(container), title: "B06-QA Laden")
        windows.append(w)
        nav.path = [channel("QA Laden TS", "/delay/3/tslive/ak29.ts")]
        await B06QA.spin(0.6)
        let e = try XCTUnwrap(B06Registry.liveVLCEngines.last)
        weak var v = B06Registry.liveVLCPlayers.last
        nav.path = []
        let tBack = Date()
        await B06QA.spin(9)
        let now = Date()
        let c = mock.connections(containing: "ak29").last
        let last5 = c?.bytes(from: now.addingTimeInterval(-5), to: now) ?? 0
        let state = v.map { "\(B06Engine.vlcState($0)) isPlaying=\(B06Engine.vlcIsPlaying($0))" } ?? "freigegeben"
        let playingNow = v.map(B06Engine.vlcIsPlaying) ?? false
        B06QA.log("AK-29|9s nach Zurück (Server liefert ab +2,4s)|vlc=\(state)|engine.isPaused=\(e.isPaused)|bytesLetzte5s=\(last5)|rate/s=\(Int(mock.media.tsRate))|verbindung=\(c?.closed == nil ? "offen" : "zu")|seitZurück=\(B06QA.f1(now.timeIntervalSince(tBack)))")
        XCTAssertTrue(e.isPaused, "App hält ihn für pausiert")
        XCTExpectFailure("BUG-02 · Nach Verlassen während des Ladens startet VLC den Stream trotzdem mit voller Datenrate (FB-02)") {
            XCTAssertFalse(playingNow)
            XCTAssertLessThan(last5, Int(mock.media.tsRate))
        }
    }

    // MARK: EC-13 · Fenster schließen

    func testEC13_FensterSchliessenBeendetVerbindung() async throws {
        let w = player(channel("QA Schließen", "/tslive/ec13.ts"))
        _ = await B06Engine.wait(8) { (B06Registry.liveVLCEngines.last?.state ?? .idle) == .playing }
        await B06QA.spin(1.5)
        weak var v = B06Registry.liveVLCPlayers.last
        windows.removeAll { $0 === w }
        B06UI.close(w)
        var line: [String] = []
        for _ in 0..<4 {
            await B06QA.spin(2)
            let c = mock.connections(containing: "ec13").last
            line.append("vlc=\(v.map(B06Engine.vlcState) ?? "frei") verbindung=\(c?.closed == nil ? "offen" : "zu") bytes=\(c?.bytesSent ?? 0)")
        }
        B06QA.log("EC-13|nach Schließen je 2s|\(line)")
    }

    // MARK: EC-11 · Playlist gelöscht, dann „Erneut versuchen“

    func testEC11_LoeschenDannErneutVersuchen() async throws {
        let ctx = container.mainContext
        let x = Playlist(name: "X löschen", sourceURL: mock.url("/player_api.php"), isXtream: true, xtreamOutput: "hls")
        ctx.insert(x)
        try XtreamCredentialStore.standard.save(XtreamSecret(host: mock.base, username: B06QA.user, password: B06QA.pass), for: x.id)
        let c = channel("QA EC11", "/live/404/ec11.m3u8", in: x)
        try ctx.save()
        let w = player(c)
        _ = await B06Engine.wait(6) { B06UI.has(w, "Erneut versuchen") }
        await B06QA.spin(0.5)
        try PlaylistImporter(modelContext: ctx).delete(x)
        let resolved: String
        do { resolved = try StreamURLResolver.playableURL(for: c).absoluteString.replacingOccurrences(of: B06QA.pass, with: "<pass>") } catch { resolved = "Fehler: \(error.localizedDescription)" }
        B06QA.log("EC-11|nach Löschen|playlist=\(String(describing: c.playlist?.name))|isDeleted=\(c.isDeleted)|context=\(c.modelContext != nil)|gespeichert=\(c.streamURL.absoluteString)|resolver=\(resolved)|schlüsselbund=\((try? XtreamCredentialStore.standard.load(for: x.id)) == nil ? "leer" : "vorhanden")")
        let before = mock.requests(containing: "ec11").count
        B06UI.press(try XCTUnwrap(B06UI.find(w, role: "AXButton", "Erneut versuchen")))
        await B06QA.spin(2)
        let reqs = mock.requests(containing: "ec11").map { $0.target.replacingOccurrences(of: B06QA.pass, with: "<pass>") }
        let labels = B06UI.labels(w)
        B06QA.log("EC-11|nach Löschen + Erneut versuchen|anfragen vorher=\(before)|alle=\(reqs)|texte=\(labels)")
        // Ist (In-Memory-Container, Sender behält die Playlist-Referenz): Resolver meldet „Zugangsdaten fehlen“, die Ansicht
        // zeigt aber weiter den alten Engine-Fehler (resolveError wird nur ohne Engine angezeigt); kein neuer Abruf.
        // Zwei beobachtete Varianten (je nach Lauf): (a) Sender hält die Playlist noch → Resolver „Zugangsdaten fehlen“, die
        // Ansicht zeigt weiter den alten Engine-Fehler, kein Abruf; (b) Playlist-Referenz schon nil → Resolver liefert die
        // gespeicherte Adresse ohne Zugangsdaten → neuer Abruf `/live/404/ec11.m3u8` (vgl. B03 QA BUG-05).
        let variante = reqs.count == before ? "a: kein Abruf, alter Fehler" : "b: Abruf ohne Zugangsdaten \(reqs.suffix(reqs.count - before))"
        B06QA.log("EC-11|variante=\(variante)")
        XCTAssertFalse(labels.contains { $0.contains("Zugangsdaten") }, "Ist: Meldung „Zugangsdaten fehlen“ erscheint nicht (Spec EC-11 gelesen, anders)")
        XCTAssertTrue(labels.contains { $0.contains("The requested URL was not found on this server.") }, "Ist: Fehlertext der Engine")
        XCTAssertFalse(reqs.dropFirst(before).contains { $0.contains(B06QA.user) }, "nach dem Löschen keine Zugangsdaten mehr im Abruf")
    }

    // MARK: EC-12 · zwei Player

    func testEC12_ZweiPlayerZweiVerbindungenTastenNurImAktivenFenster() async throws {
        let wA = player(channel("QA A", "/tslive/ec12a.ts"), origin: CGPoint(x: 60, y: 120), size: CGSize(width: 480, height: 300))
        let wB = player(channel("QA B", "/tslive/ec12b.ts"), origin: CGPoint(x: 600, y: 120), size: CGSize(width: 480, height: 300))
        _ = await B06Engine.wait(8) { B06Registry.liveVLCEngines.count == 2 && B06Registry.liveVLCEngines.allSatisfy { $0.state == .playing } }
        try await activate(wB)
        await B06QA.spin(1)
        let players = B06Registry.liveVLCPlayers
        XCTAssertEqual(players.count, 2)
        B06UI.key(wB, .space, viaApp: true)   // NSApp leitet an das Schlüsselfenster
        await B06QA.spin(1.0)
        let states = players.map { B06Engine.vlcIsPlaying($0) ? "spielt" : B06Engine.vlcState($0) }
        let conns = mock.connections.filter { $0.path.contains("ec12") && $0.closed == nil }.map(\.path)
        B06QA.log("EC-12|verbindungen offen=\(conns)|vlc A,B=\(states)|keyWindow=B:\(NSApp.keyWindow === wB)")
        XCTAssertEqual(conns.count, 2)
        XCTAssertEqual(states, ["spielt", "paused"])
        B06UI.key(wB, .space, viaApp: true)
        _ = wA
    }
}
