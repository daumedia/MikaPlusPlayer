import Foundation
import SwiftUI

// VLCKit kann je nach Bezugsquelle unter verschiedenen Modulnamen vorliegen:
//   - SwiftPM-Binärpaket (tylerjonesio/vlckit-spm): VLCKitSPM  (iOS + macOS)
//   - CocoaPods iOS/tvOS:                           MobileVLCKit
//   - CocoaPods macOS:                              VLCKit
// Der gesamte Inhalt dieser Datei ist hinter `canImport` gekapselt, damit die
// App auch OHNE eingebundenes VLCKit kompiliert (Fallback: AVKit).
#if canImport(VLCKitSPM)
import VLCKitSPM
#elseif canImport(MobileVLCKit)
import MobileVLCKit
#elseif canImport(VLCKit)
import VLCKit
#endif

#if canImport(VLCKitSPM) || canImport(MobileVLCKit) || canImport(VLCKit)

/// VLCKit-basierte Engine. Spielt – im Gegensatz zu AVPlayer – auch rohe
/// MPEG-TS-Streams (.ts) sowie viele weitere Formate.
///
/// B06 · BUG-01: Der Zustand folgt dem, was VLC tatsächlich meldet und zeigt. „Läuft" heißt erst, wenn ein Bild
/// (bzw. Ton) ausgegeben wurde; Fehler, Ende des Datenstroms und Hänger enden in `.failed` mit einer deutschen
/// Meldung ohne Adresse. Nach einem Fehler ist die Verbindung geschlossen.
/// B06 · BUG-02 / BUG-07: Jeder `VLCMediaPlayer` wird nach Gebrauch über `VLCPlayerLifecycle` gestoppt und
/// einzeln abgebaut; ein neuer entsteht erst, wenn kein Abbau mehr läuft.
@MainActor
@Observable
final class VLCPlaybackEngine: NSObject, PlaybackEngine {
    /// Zeitgrenzen analog zur AVKit-Engine (HLS gibt nach ≈ 40 s ohne Daten auf, ein abgebrochener Live-Stream
    /// meldet sich nach ≈ 31 s).
    struct Limits: Equatable {
        /// Längste Zeit vom Laden bis zum ersten Bild.
        var load: TimeInterval
        /// Längste Zeit ohne neues Bild während der Wiedergabe (nicht pausiert).
        var stall: TimeInterval

        static let standard = Limits(load: 40, stall: 30)
    }

    /// Zeitgrenzen für neu erzeugte Engines. Nur Tests setzen kürzere Werte.
    static var limitsForNewEngines = Limits.standard

    /// Gründe, aus denen die Wiedergabe scheitert – mit der Meldung, die der Player zeigt (ohne Adresse,
    /// Host oder Zugangsdaten).
    enum Failure: Equatable {
        /// libVLC meldet einen Fehler (HTTP 401/403/404, Host nicht erreichbar oder unbekannt …).
        case cannotOpen
        /// Innerhalb der Ladefrist kam kein Bild.
        case noResponse
        /// Der Datenstrom endete, bevor ein Bild kam (z. B. eine HTML-Seite statt eines Videos).
        case unplayable
        /// Der laufende Stream brach ab oder blieb stehen.
        case interrupted

        var message: String {
            switch self {
            case .cannotOpen:
                return "Der Sender konnte nicht geöffnet werden. Möglicherweise ist er nicht erreichbar oder nicht mehr vorhanden, oder der Zugang wurde abgelehnt."
            case .noResponse:
                return "Der Sender antwortet nicht."
            case .unplayable:
                return "Der Sender liefert kein abspielbares Video."
            case .interrupted:
                return "Die Verbindung zum Sender wurde unterbrochen."
            }
        }
    }

    private(set) var state: PlaybackState = .idle
    private(set) var isPaused = false
    private(set) var volume: Double = 1.0
    private(set) var isMuted = false

    /// Der Player der laufenden Wiedergabe. Je `load` ein frischer; `nil`, solange keiner gebraucht wird oder
    /// der vorherige noch abgebaut wird.
    @ObservationIgnored private var mediaPlayer: VLCMediaPlayer?
    // Der View, auf den VLC rendert. Wird vom Representable gesetzt.
    @ObservationIgnored fileprivate let drawableView = VLCDrawableView()
    @ObservationIgnored private let limits: Limits
    @ObservationIgnored private var currentURL: URL?
    /// Zählt Laden/Stoppen; verspätete Aufgaben einer älteren Runde erkennen sich daran.
    @ObservationIgnored private var session = 0
    @ObservationIgnored private var sawOpening = false
    @ObservationIgnored private var hasPicture = false
    /// Ende einer Datei (VOD) erreicht: Standbild wie bei AVKit (EC-04), keine Zeitgrenze mehr.
    @ObservationIgnored private var reachedEndOfFile = false
    /// Pause während des Ladens: Laden abgebrochen, `play()` lädt neu (EC-05, AK-29).
    @ObservationIgnored private var reloadOnPlay = false
    @ObservationIgnored private var loadStarted = Date()
    @ObservationIgnored private var lastProgress = OutputProgress()
    @ObservationIgnored private var lastProgressAt = Date()
    @ObservationIgnored private var watchdog: Task<Void, Never>?

    init(limits: Limits) {
        self.limits = limits
        super.init()
    }

    override convenience init() {
        self.init(limits: VLCPlaybackEngine.limitsForNewEngines)
    }

    deinit {
        watchdog?.cancel()
        // Freigabe ohne `stop()` (z. B. eine verworfene Engine): Player trotzdem geordnet abbauen (BUG-07).
        if let player = mediaPlayer {
            let box = VLCPlayerBox(player)
            Task { @MainActor in VLCPlayerLifecycle.shared.retire(box) }
        }
    }

    // MARK: - Steuerung

    func load(_ url: URL) {
        session += 1
        let token = session
        currentURL = url
        reloadOnPlay = false
        sawOpening = false
        hasPicture = false
        reachedEndOfFile = false
        isPaused = false
        // Je Laden ein frischer Player; ein vorhandener wird geordnet abgebaut (auch bei „Erneut versuchen").
        retirePlayer()
        state = .loading
        loadStarted = Date()
        lastProgress = OutputProgress()
        startWatchdog(token)
        VLCPlayerLifecycle.shared.whenIdle { [weak self] in
            guard let self, self.session == token, self.mediaPlayer == nil else { return }
            let player = VLCMediaPlayer()
            player.delegate = self
            player.drawable = self.drawableView
            self.mediaPlayer = player
            player.media = VLCMedia(url: url)
            player.play()
            self.applyAudio()
        }
    }

    func play() {
        isPaused = false
        if reloadOnPlay, let url = currentURL {
            load(url)
            return
        }
        guard case .playing = state, let player = mediaPlayer else { return }
        player.play()
        lastProgressAt = Date()
    }

    func pause() {
        isPaused = true
        switch state {
        case .playing:
            mediaPlayer?.pause()
        case .loading:
            // EC-05 / AK-29: VLC nimmt eine Pause erst an, wenn der Stream läuft – vorher würde er danach trotzdem
            // starten. Deshalb das Laden abbrechen (Verbindung zu) und bei `play()` neu laden.
            session += 1
            watchdog?.cancel()
            retirePlayer()
            reloadOnPlay = true
            state = .idle
        case .idle, .failed:
            break
        }
    }

    /// Beendet Wiedergabe und Verbindung und gibt den Player geordnet frei (B03 · BUG-05, B06 · BUG-02).
    func stop() {
        session += 1
        watchdog?.cancel()
        reloadOnPlay = false
        retirePlayer()
        isPaused = true
        state = .idle
    }

    func togglePlayPause() { isPaused ? play() : pause() }

    func setVolume(_ value: Double) {
        volume = min(1, max(0, value))
        if volume > 0 { isMuted = false }
        applyAudio()
    }

    func toggleMute() { setMuted(!isMuted) }

    func setMuted(_ muted: Bool) { isMuted = muted; applyAudio() }

    /// Wendet `volume`/`isMuted` auf den VLC-Audiokanal an. `mediaPlayer.audio` ist
    /// vor Wiedergabestart oft `nil`, daher wird dies bei jedem Zustandswechsel erneut
    /// aufgerufen, damit die Soll-Werte greifen.
    private func applyAudio() {
        guard let audio = mediaPlayer?.audio else { return }
        audio.volume = Int32(volume * 100)
        // VLCAudio: @property (getter=isMuted) BOOL muted; -> in Swift settable als isMuted.
        audio.isMuted = isMuted
    }

    func makePlayerView() -> AnyView {
        AnyView(VLCPlayerSurface(view: drawableView).ignoresSafeArea())
    }

    // MARK: - Zustand

    /// Übergibt den aktuellen Player dem geordneten Abbau.
    private func retirePlayer() {
        guard let player = mediaPlayer else { return }
        mediaPlayer = nil
        player.delegate = nil
        VLCPlayerLifecycle.shared.retire(VLCPlayerBox(player))
    }

    private func fail(_ failure: Failure) {
        session += 1
        watchdog?.cancel()
        retirePlayer()          // schließt die Verbindung; „Erneut versuchen" lädt mit einem neuen Player
        state = .failed(failure.message)
    }

    /// Wird aufgerufen, sobald VLC Bild oder Ton dekodiert bzw. ausgibt.
    private func becamePlaying(_ progress: OutputProgress) {
        hasPicture = true
        lastProgress = progress
        lastProgressAt = Date()
        state = .playing
        applyAudio()
    }

    /// Datenstrom zu Ende, ohne dass die App gestoppt hat. VLCKit startet libVLC mit `--play-and-pause`: das Ende
    /// kommt deshalb als „paused" (Abbruch, Dateiende, HTML) oder als „stopped"/„ended".
    private func streamEnded(_ player: VLCMediaPlayer) {
        let progress = OutputProgress(player)
        if !hasPicture, progress.hasOutput { hasPicture = true }
        guard hasPicture else { return fail(.unplayable) }
        if player.isSeekable, player.position >= 0.9 {
            // Ende einer Datei (VOD, nicht im Scope): stehen bleiben wie AVKit (EC-04).
            reachedEndOfFile = true
            return
        }
        fail(.interrupted)
    }

    fileprivate func handleStateChange(_ rawValue: Int, playerID: ObjectIdentifier) {
        guard let player = mediaPlayer, ObjectIdentifier(player) == playerID,
              let raw = VLCMediaPlayerState(rawValue: rawValue) else { return }
        switch raw {
        case .opening:
            sawOpening = true
        case .buffering, .esAdded, .playing:
            // Kein Beleg für ein Bild (BUG-01: „buffering" galt als „läuft"); das entscheidet der Wächter.
            // Der Audiokanal kann jetzt existieren – Soll-Lautstärke/Stumm anwenden.
            applyAudio()
        case .paused:
            // Eigene Pause, oder Ende des Datenstroms (`--play-and-pause`).
            guard sawOpening, !isPaused, !reachedEndOfFile else { return }
            streamEnded(player)
        case .error:
            fail(.cannotOpen)
        case .stopped, .ended:
            guard sawOpening, !reachedEndOfFile else { return }
            streamEnded(player)
        @unknown default:
            break
        }
    }

    // MARK: - Wächter (Zeitgrenzen)

    private func startWatchdog(_ token: Int) {
        watchdog?.cancel()
        watchdog = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(250))
                guard let self, self.session == token else { return }
                self.checkProgress()
            }
        }
    }

    private func checkProgress() {
        let now = Date()
        switch state {
        case .loading:
            if let player = mediaPlayer {
                let progress = OutputProgress(player)
                if progress.hasOutput { return becamePlaying(progress) }
            }
            if now.timeIntervalSince(loadStarted) >= limits.load { fail(.noResponse) }
        case .playing:
            guard let player = mediaPlayer, !isPaused, !reachedEndOfFile else {
                lastProgressAt = now
                return
            }
            let progress = OutputProgress(player)
            if progress != lastProgress {
                lastProgress = progress
                lastProgressAt = now
            } else if now.timeIntervalSince(lastProgressAt) >= limits.stall {
                fail(.interrupted)
            }
        case .idle, .failed:
            return
        }
    }

    /// Fortschritt der Wiedergabe: dekodierte Video-/Audioblöcke, angezeigte Bilder, Wiedergabezeit. Dekodierte
    /// Blöcke zählen auch, wenn die Zeichenfläche gerade in keinem Fenster liegt (z. B. verdeckte Multiview-Kachel).
    private struct OutputProgress: Equatable {
        var decoded: Int32 = 0
        var pictures: Int32 = 0
        var time: Int32 = 0

        init() {}

        init(_ player: VLCMediaPlayer) {
            if let stats = player.media?.statistics {
                decoded = stats.decodedVideo &+ stats.decodedAudio
                pictures = stats.displayedPictures
            }
            time = player.time.intValue
        }

        var hasOutput: Bool { decoded > 0 || pictures > 0 }
    }
}

// MARK: - VLCMediaPlayerDelegate

extension VLCPlaybackEngine: VLCMediaPlayerDelegate {
    nonisolated func mediaPlayerStateChanged(_ aNotification: Notification) {
        // B06 · BUG-01: VLCKit ruft den Delegate synchron auf seinem Ereignis-Thread auf, direkt nachdem es den
        // neuen Zustand gespeichert hat. Der Zustand wird deshalb HIER gelesen (nicht erst später auf dem
        // Hauptthread – dort hatte „stopped" den „error" aus derselben Millisekunde schon überschrieben) und in
        // Reihenfolge an den Hauptthread gereicht.
        guard let player = aNotification.object as? VLCMediaPlayer else { return }
        let rawValue = player.state.rawValue
        let playerID = ObjectIdentifier(player)
        DispatchQueue.main.async { [weak self] in
            MainActor.assumeIsolated {
                self?.handleStateChange(rawValue, playerID: playerID)
            }
        }
    }
}

// MARK: - Geordneter Abbau (B06 · BUG-07)

/// Hält einen `VLCMediaPlayer`, um ihn zwischen Hauptthread und Abbau-Queue weiterzureichen.
final class VLCPlayerBox: @unchecked Sendable {
    fileprivate var player: VLCMediaPlayer?
    fileprivate init(_ player: VLCMediaPlayer) { self.player = player }
}

/// Baut `VLCMediaPlayer` einzeln und nacheinander ab und lässt neue erst entstehen, wenn kein Abbau läuft.
///
/// B06 · BUG-07: libVLC hing, als ein neuer Player entstand (Hauptthread in `config_GetFloat`), während mehrere
/// andere – nicht gestoppte – Player gleichzeitig auf eigenen Queues abgebaut wurden (`libvlc_media_player_destroy`
/// → `pthread_join`; Samples `features/B06-wiedergabe/qa/BUG-07-*.txt`). Deshalb:
/// 1. jeder Player wird vor der Freigabe gestoppt, und es wird gewartet, bis libVLC „stopped" meldet;
/// 2. die letzte Referenz fällt auf einer eigenen seriellen Queue (der Abbau blockiert nie den Hauptthread), und es
///    wird gewartet, bis der Player wirklich freigegeben ist;
/// 3. erst dann folgt der nächste – es läuft nie mehr als ein Abbau;
/// 4. neue Player entstehen nur, wenn die Warteschlange leer ist (`whenIdle`). Multiview (B08) gibt beim Schließen
///    bis zu vier Player auf einmal zurück; sie werden so nacheinander abgebaut.
@MainActor
final class VLCPlayerLifecycle {
    static let shared = VLCPlayerLifecycle()

    private var queue: [VLCPlayerBox] = []
    private var tearingDown = false
    private var waiting: [@MainActor () -> Void] = []
    private static let releaseQueue = DispatchQueue(label: "lu.daumedia.MikaPlusPlayer.vlc-release", qos: .userInitiated)

    /// Belege für Tests: abgeschlossene Abbauten, zurückgestellte Erzeugungen, gleichzeitige Abbauten (höchstens).
    private(set) var completedTeardowns = 0
    private(set) var deferredCreations = 0
    private(set) var maxConcurrentTeardowns = 0
    private var runningTeardowns = 0

    var isIdle: Bool { !tearingDown && queue.isEmpty }

    /// Führt `work` sofort aus, wenn kein Abbau läuft, sonst direkt nach dem letzten.
    func whenIdle(_ work: @escaping @MainActor () -> Void) {
        if isIdle {
            work()
        } else {
            deferredCreations += 1
            waiting.append(work)
        }
    }

    /// Übernimmt einen Player zum Abbau.
    func retire(_ box: VLCPlayerBox) {
        guard box.player != nil else { return }
        box.player?.delegate = nil
        queue.append(box)
        pump()
    }

    private func pump() {
        guard !tearingDown else { return }
        if !queue.isEmpty {
            let box = queue.removeFirst()
            tearingDown = true
            Task {
                await self.tearDown(box)
                self.tearingDown = false
                self.pump()
            }
            return
        }
        while isIdle, !waiting.isEmpty {
            let work = waiting.removeFirst()
            work()
        }
    }

    private func tearDown(_ box: VLCPlayerBox) async {
        runningTeardowns += 1
        maxConcurrentTeardowns = max(maxConcurrentTeardowns, runningTeardowns)
        defer {
            runningTeardowns -= 1
            completedTeardowns += 1
        }
        // 1. Stoppen (VLCKit: libvlc_media_player_stop_async) und auf „stopped" warten, höchstens 5 s.
        box.player?.stop()
        let started = Date()
        while let state = box.player?.state, state != .stopped, Date().timeIntervalSince(started) < 5 {
            try? await Task.sleep(for: .milliseconds(20))
        }
        // 2. Letzte Referenz auf der Abbau-Queue abgeben und warten, bis der Player freigegeben ist – auch wenn
        //    VLCKit ihn in einem Ereignisblock noch kurz hält (höchstens 5 s).
        await withCheckedContinuation { (done: CheckedContinuation<Void, Never>) in
            Self.releaseQueue.async {
                weak let released = box.player
                box.player = nil
                let deadline = Date().addingTimeInterval(5)
                while released != nil, Date() < deadline { usleep(10_000) }
                done.resume()
            }
        }
    }
}

// MARK: - Plattform-Brücke (UIView / NSView)

#if os(iOS)
typealias VLCDrawableView = UIView

/// Bettet den VLC-Drawable-View in SwiftUI ein (iOS).
private struct VLCPlayerSurface: UIViewRepresentable {
    let view: VLCDrawableView
    func makeUIView(context: Context) -> VLCDrawableView {
        view.backgroundColor = .black
        return view
    }
    func updateUIView(_ uiView: VLCDrawableView, context: Context) {}
}

#elseif os(macOS)
typealias VLCDrawableView = NSView

/// Bettet den VLC-Drawable-View in SwiftUI ein (macOS).
///
/// B08 · BUG-02: Die Zeichenfläche gehört der Engine, eingebettet wird sie in einen eigenen Behälter je Einbettung
/// (wie `PlayerLayerView` bei AVKit). Legt SwiftUI für dieselbe Engine eine neue Einbettung an, übernimmt die neue die
/// Fläche; wird die zeigende Einbettung abgebaut, geht die Fläche an eine andere derselben Engine. Hängt die Fläche
/// nirgends mehr, holt der Behälter sie bei der nächsten Aktualisierung bzw. beim Einfügen ins Fenster zurück. Vorher
/// gab `makeNSView` die Fläche selbst zurück und `updateNSView` war leer: Nach einem Fokuswechsel im Multiview hing die
/// Fläche des Streams mit Ton in keinem Fenster, das große Bild blieb schwarz.
private struct VLCPlayerSurface: NSViewRepresentable {
    let view: VLCDrawableView

    func makeNSView(context: Context) -> VLCSurfaceHostView {
        let host = VLCSurfaceHostView()
        host.attach(view)
        return host
    }

    func updateNSView(_ host: VLCSurfaceHostView, context: Context) {
        host.attachIfNeeded(view)
    }

    static func dismantleNSView(_ host: VLCSurfaceHostView, coordinator: ()) {
        host.release()
    }
}

/// Behälter für die Zeichenfläche einer VLC-Engine (macOS). Genau ein Behälter zeigt die Fläche; gibt er sie ab, geht
/// sie an einen anderen Behälter derselben Fläche, der im Fenster steht.
final class VLCSurfaceHostView: NSView {
    private weak var drawable: VLCDrawableView?

    private final class WeakHost {
        weak var host: VLCSurfaceHostView?
        init(_ host: VLCSurfaceHostView) { self.host = host }
    }
    /// Alle Behälter je Zeichenfläche (schwach gehalten).
    private static var hostsByDrawable: [ObjectIdentifier: [WeakHost]] = [:]

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.backgroundColor = NSColor.black.cgColor
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) wird nicht verwendet") }

    /// Setzt die Fläche in diesen Behälter (die jüngste Einbettung gewinnt).
    func attach(_ view: VLCDrawableView) {
        if let old = drawable, old !== view { release() }
        if drawable !== view {
            drawable = view
            Self.register(self, for: view)
        }
        guard view.superview !== self else { return }
        view.wantsLayer = true
        view.layer?.backgroundColor = NSColor.black.cgColor
        view.frame = bounds
        view.autoresizingMask = [.width, .height]
        addSubview(view)
    }

    /// Andere Engine, oder die Fläche hängt nirgends mehr: wieder einsetzen.
    func attachIfNeeded(_ view: VLCDrawableView) {
        if drawable !== view || view.superview == nil { attach(view) }
    }

    /// Beim Abbau der Einbettung: die Fläche abgeben – an einen anderen Behälter im Fenster, falls es einen gibt.
    func release() {
        guard let view = drawable else { return }
        drawable = nil
        Self.unregister(self, for: view)
        guard view.superview === self else { return }
        view.removeFromSuperview()
        let others = Self.hosts(for: view)
        if let next = others.first(where: { $0.window != nil }) ?? others.first { next.attach(view) }
    }

    override func layout() {
        super.layout()
        if let view = drawable, view.superview === self, view.frame != bounds { view.frame = bounds }
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        // Im Fenster angekommen, die Fläche aber verwaist oder in einem Behälter ohne Fenster: übernehmen.
        guard window != nil, let view = drawable, view.superview !== self,
              view.superview == nil || view.window == nil else { return }
        attach(view)
    }

    private static func register(_ host: VLCSurfaceHostView, for view: VLCDrawableView) {
        let key = ObjectIdentifier(view)
        var list = (hostsByDrawable[key] ?? []).filter { $0.host != nil && $0.host !== host }
        list.append(WeakHost(host))
        hostsByDrawable[key] = list
    }

    private static func unregister(_ host: VLCSurfaceHostView, for view: VLCDrawableView) {
        let key = ObjectIdentifier(view)
        let list = (hostsByDrawable[key] ?? []).filter { $0.host != nil && $0.host !== host }
        hostsByDrawable[key] = list.isEmpty ? nil : list
    }

    private static func hosts(for view: VLCDrawableView) -> [VLCSurfaceHostView] {
        (hostsByDrawable[ObjectIdentifier(view)] ?? []).compactMap(\.host).filter { $0.drawable === view }
    }
}
#endif

#endif // canImport VLCKit
