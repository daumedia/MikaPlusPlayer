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

    init() {
        playerLayer.player = player
    }

    func load(_ url: URL) {
        state = .loading
        activateAudioSession()
        let item = AVPlayerItem(url: url)
        observe(item)
        player.replaceCurrentItem(with: item)
        player.play()
        isPaused = false
    }

    func play() { player.play(); isPaused = false }
    func pause() { player.pause(); isPaused = true }
    func togglePlayPause() { isPaused ? play() : pause() }

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
        AVPictureInPictureController.isPictureInPictureSupported()
    }

    func startPictureInPicture() {
        setupPictureInPictureIfNeeded()
        guard let pipController, pipController.isPictureInPicturePossible else { return }
        pipController.startPictureInPicture()
    }

    func stopPictureInPicture() {
        pipController?.stopPictureInPicture()
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
        statusObserver?.cancel()
        errorObserver?.cancel()
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
}
