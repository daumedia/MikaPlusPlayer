import Foundation
import AVKit
import AVFoundation
import SwiftUI
import Combine

/// AVKit-basierte Engine. Spielt HLS (.m3u8) und gängige Container, aber KEINE
/// rohen MPEG-TS-Streams (.ts) – dafür siehe `VLCPlaybackEngine`.
@MainActor
@Observable
final class AVKitPlaybackEngine: PlaybackEngine {
    private(set) var state: PlaybackState = .idle
    /// B07 · BUG-03: folgt dem Player – auch wenn das System ihn ohne die App anhält oder fortsetzt
    /// (Pause und Schließen im Bild-in-Bild-Fenster, ein zweites Bild-in-Bild). Siehe `observePlayback()`.
    private(set) var isPaused = false
    private(set) var volume: Double = 1.0
    private(set) var isMuted = false
    /// Von der PiP-Delegate (siehe unten) gesetzt; steuert den Button-Zustand.
    fileprivate(set) var isPictureInPictureActive = false

    @ObservationIgnored private let player = AVPlayer()
    /// Die Videofläche. Gehört der Engine, damit derselbe Layer sowohl in SwiftUI
    /// eingebettet (`makePlayerView`) als auch an den PiP-Controller gehängt wird.
    @ObservationIgnored let playerLayer = AVPlayerLayer()
    @ObservationIgnored private var pipController: AVPictureInPictureController?
    @ObservationIgnored private var pipDelegate: PiPDelegate?
    /// Gemerkter Wunsch für Auto-PiP – wird angewandt, sobald der Controller existiert
    /// (der wird erst beim ersten `makePlayerView` erzeugt).
    @ObservationIgnored private var automaticPiP = false
    @ObservationIgnored private var statusObserver: AnyCancellable?
    @ObservationIgnored private var errorObserver: AnyCancellable?
    @ObservationIgnored private var playbackObserver: AnyCancellable?
    /// B08 · BUG-07: Frist ohne Fortschritt während der Wiedergabe; danach gilt der Stream als unterbrochen. `nil`
    /// (Standard, Player): AVKit entscheidet selbst, wann es aufgibt (B06 AK-06). Multiview-Kacheln setzen eine Frist
    /// (`MultiviewSession`), weil AVKit bei Live-HLS, dessen Segmente fehlen, nie aufgibt und die Kachel sonst ohne
    /// Meldung ein Standbild zeigt.
    @ObservationIgnored private var stallLimit: TimeInterval?
    @ObservationIgnored private var stallWatch: Task<Void, Never>?
    @ObservationIgnored private var lastPlaybackTime = -Double.infinity
    @ObservationIgnored private var lastProgressAt = Date()

    /// Meldung, wenn die Wiedergabe länger als `stallLimit` keinen Fortschritt macht (wie `VLCPlaybackEngine`).
    static let interruptedMessage = "Die Verbindung zum Sender wurde unterbrochen."

    init() {
        playerLayer.player = player
        observePlayback()
    }

    func load(_ url: URL) {
        state = .loading
        activateAudioSession()
        let item = AVPlayerItem(url: url)
        observe(item)
        player.replaceCurrentItem(with: item)
        player.play()
        isPaused = false
        startStallWatch()
    }

    func play() { player.play(); isPaused = false }
    func pause() { player.pause(); isPaused = true }

    /// Hält an und gibt das Element frei – das beendet auch das Nachladen und die Verbindung (B03 · BUG-05).
    /// Läuft Bild-in-Bild noch, endet es mit (B07 · BUG-01), auch wenn der Player schon verlassen ist.
    func stop() {
        endPictureInPicture()
        stallWatch?.cancel()
        player.pause()
        player.replaceCurrentItem(with: nil)
        statusObserver?.cancel()
        errorObserver?.cancel()
        isPaused = true
        state = .idle
    }

    /// B08 · BUG-07: Setzt die Frist ohne Fortschritt (`nil` = keine eigene Frist). Gilt ab dem nächsten `load`.
    func limitStalls(to seconds: TimeInterval?) {
        stallLimit = seconds
    }

    private func startStallWatch() {
        stallWatch?.cancel()
        lastPlaybackTime = -.infinity
        lastProgressAt = Date()
        guard stallLimit != nil else { return }
        stallWatch = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(500))
                guard let self, !Task.isCancelled else { return }
                self.checkStall()
            }
        }
    }

    /// Fortschritt = die Wiedergabezeit läuft weiter. Laden, eigene Pause und das Ende einer Datei zählen nicht.
    private func checkStall() {
        let now = Date()
        guard let limit = stallLimit, state == .playing, let item = player.currentItem,
              player.timeControlStatus != .paused else {
            lastProgressAt = now
            return
        }
        let time = item.currentTime().seconds
        if time.isFinite, time != lastPlaybackTime {
            lastPlaybackTime = time
            lastProgressAt = now
        } else if now.timeIntervalSince(lastProgressAt) >= limit {
            // Wie ein Fehler der Engine: Nachladen und Verbindung beenden, Meldung zeigen.
            stallWatch?.cancel()
            statusObserver?.cancel()
            errorObserver?.cancel()
            player.pause()
            player.replaceCurrentItem(with: nil)
            state = .failed(Self.interruptedMessage)
        }
    }

    /// Entscheidet nach dem tatsächlichen Zustand des Players (B07 · BUG-03).
    func togglePlayPause() {
        syncPausedWithPlayer()
        isPaused ? play() : pause()
    }

    func setVolume(_ value: Double) {
        volume = min(1, max(0, value))
        player.volume = Float(volume)
        if volume > 0, isMuted { isMuted = false; player.isMuted = false }
    }

    func toggleMute() { setMuted(!isMuted) }

    func setMuted(_ muted: Bool) { isMuted = muted; player.isMuted = muted }

    func makePlayerView() -> AnyView {
        setupPictureInPictureIfNeeded()
        return AnyView(PlayerLayerView(playerLayer: playerLayer).ignoresSafeArea())
    }

    // MARK: - Picture-in-Picture

    var supportsPictureInPicture: Bool {
        Self.deviceSupportsPictureInPicture
    }

    /// Ob das Gerät System-Bild-in-Bild kann – unabhängig vom Sender (iPhone-Simulatoren z. B. nicht).
    static var deviceSupportsPictureInPicture: Bool {
        AVPictureInPictureController.isPictureInPictureSupported()
    }

    func startPictureInPicture() {
        setupPictureInPictureIfNeeded()
        guard let pipController, pipController.isPictureInPicturePossible else { return }
        pipController.startPictureInPicture()
    }

    func stopPictureInPicture() {
        // B07 · BUG-01: Ohne Player (von `DetachedPlayback` übernommen) bleibt der normale Stopp wirkungslos –
        // Bild-in-Bild dann endgültig beenden; `DetachedPlayback` beendet daraufhin die Wiedergabe.
        if DetachedPlayback.shared.holds(self) {
            endPictureInPicture()
        } else {
            pipController?.stopPictureInPicture()
        }
    }

    /// B07 · BUG-01: Beendet Bild-in-Bild endgültig. Hängt die Videofläche nicht mehr in einem Fenster (Player
    /// verlassen), bleibt `stopPictureInPicture()` wirkungslos – das schwebende Fenster schließt erst, wenn der
    /// Controller frei ist. Deshalb wird er hier abgegeben; `setupPictureInPictureIfNeeded()` legt bei Bedarf
    /// einen neuen an.
    private func endPictureInPicture() {
        guard let controller = pipController else { return }
        if controller.isPictureInPictureActive { controller.stopPictureInPicture() }
        controller.delegate = nil
        pipController = nil
        pipDelegate = nil
        isPictureInPictureActive = false
    }

    /// B07 · BUG-01: „Zurück zur App" im Bild-in-Bild-Fenster. Liegt die Wiedergabe noch in einem offenen Player,
    /// holt das System das Bild dorthin zurück. Wurde der Player verlassen (`DetachedPlayback`), gibt es keinen
    /// Player mehr: Bild-in-Bild endet ohne Rückkehr, und `DetachedPlayback` beendet die Wiedergabe.
    fileprivate func canRestoreUserInterface() -> Bool {
        !DetachedPlayback.shared.holds(self)
    }

    func setAutomaticPictureInPicture(_ enabled: Bool) {
        automaticPiP = enabled
        #if os(iOS)
        pipController?.canStartPictureInPictureAutomaticallyFromInline = enabled
        #endif
    }

    /// Erzeugt den PiP-Controller einmalig für den engine-eigenen Layer.
    private func setupPictureInPictureIfNeeded() {
        guard pipController == nil,
              AVPictureInPictureController.isPictureInPictureSupported(),
              let controller = AVPictureInPictureController(playerLayer: playerLayer) else { return }
        let delegate = PiPDelegate(engine: self)
        controller.delegate = delegate
        #if os(iOS)
        controller.canStartPictureInPictureAutomaticallyFromInline = automaticPiP
        #endif
        pipController = controller
        pipDelegate = delegate
    }

    // MARK: - Audio-Session (iOS)

    /// iOS-PiP/Hintergrund-Audio setzt eine aktive `.playback`-Session voraus.
    /// macOS kennt keine `AVAudioSession`.
    private func activateAudioSession() {
        #if os(iOS)
        let session = AVAudioSession.sharedInstance()
        try? session.setCategory(.playback, mode: .moviePlayback)
        try? session.setActive(true)
        #endif
    }

    // MARK: - Status-Beobachtung

    /// B07 · BUG-03: `isPaused` aus dem Player ableiten statt nur aus eigenen Aufrufen. Beobachtet wird
    /// `timeControlStatus` (angehalten ↔ spielt/wartet); Laden und Puffern zählen nicht als Pause.
    private func observePlayback() {
        playbackObserver = player.publisher(for: \.timeControlStatus, options: [.new])
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.syncPausedWithPlayer() }
    }

    /// Übernimmt den Zustand des Players. Ohne Element (vor `load`, nach `stop`) gilt der eigene Zustand. Am
    /// natürlichen Ende einer Datei bleibt die Anzeige „läuft" (Standbild, B06 EC-04).
    private func syncPausedWithPlayer() {
        guard let item = player.currentItem else { return }
        let paused = player.timeControlStatus == .paused
        guard paused != isPaused else { return }
        if paused, Self.reachedEnd(of: item) { return }
        isPaused = paused
    }

    private static func reachedEnd(of item: AVPlayerItem) -> Bool {
        let duration = item.duration
        guard duration.isNumeric, duration.seconds > 0 else { return false }   // Live: kein Ende
        return item.currentTime().seconds >= duration.seconds - 0.5
    }

    private func observe(_ item: AVPlayerItem) {
        statusObserver = item.publisher(for: \.status)
            .receive(on: RunLoop.main)
            .sink { [weak self] status in
                guard let self else { return }
                switch status {
                case .readyToPlay:
                    self.state = .playing
                case .failed:
                    let message = item.error?.localizedDescription
                        ?? "Der Stream konnte nicht geladen werden."
                    self.state = .failed(message)
                case .unknown:
                    self.state = .loading
                @unknown default:
                    self.state = .loading
                }
            }

        // Laufzeitfehler während der Wiedergabe (z. B. Netzwerkabbruch).
        errorObserver = NotificationCenter.default
            .publisher(for: .AVPlayerItemFailedToPlayToEndTime, object: item)
            .receive(on: RunLoop.main)
            .sink { [weak self] note in
                let err = note.userInfo?[AVPlayerItemFailedToPlayToEndTimeErrorKey] as? Error
                self?.state = .failed(err?.localizedDescription
                    ?? "Wiedergabe wurde unterbrochen.")
            }
    }

    deinit {
        stallWatch?.cancel()
        statusObserver?.cancel()
        errorObserver?.cancel()
        playbackObserver?.cancel()
    }
}

/// Leitet die PiP-Zustandswechsel an die (`@MainActor`-isolierte) Engine weiter.
/// Als eigenständiges `NSObject`, damit die `@Observable`-Engine kein NSObject sein muss.
private final class PiPDelegate: NSObject, AVPictureInPictureControllerDelegate {
    weak var engine: AVKitPlaybackEngine?

    init(engine: AVKitPlaybackEngine) {
        self.engine = engine
    }

    func pictureInPictureControllerDidStartPictureInPicture(_ controller: AVPictureInPictureController) {
        MainActor.assumeIsolated { engine?.isPictureInPictureActive = true }
    }

    func pictureInPictureControllerDidStopPictureInPicture(_ controller: AVPictureInPictureController) {
        MainActor.assumeIsolated { engine?.isPictureInPictureActive = false }
    }

    func pictureInPictureController(_ controller: AVPictureInPictureController,
                                    failedToStartPictureInPictureWithError error: Error) {
        MainActor.assumeIsolated { engine?.isPictureInPictureActive = false }
    }

    /// „Zurück zur App" im schwebenden Fenster (B07 · BUG-01).
    func pictureInPictureController(_ controller: AVPictureInPictureController,
                                    restoreUserInterfaceForPictureInPictureStopWithCompletionHandler completionHandler: @escaping (Bool) -> Void) {
        let restored = MainActor.assumeIsolated { engine?.canRestoreUserInterface() ?? false }
        completionHandler(restored)
    }
}
