import SwiftUI
import AVFoundation

/// Bettet einen extern verwalteten `AVPlayerLayer` in die SwiftUI-Hierarchie ein.
///
/// Wird von `AVKitPlaybackEngine.makePlayerView()` statt SwiftUI-`VideoPlayer`
/// verwendet, damit an denselben Layer ein `AVPictureInPictureController` gehängt
/// werden kann. Der Layer gehört der Engine (bleibt über Rerenders stabil); dieser
/// Host fügt ihn nur als Sublayer ein und hält seinen Frame synchron.
struct PlayerLayerView {
    let playerLayer: AVPlayerLayer
}

#if os(iOS)
import UIKit

extension PlayerLayerView: UIViewRepresentable {
    func makeUIView(context: Context) -> PlayerLayerHostView {
        let view = PlayerLayerHostView()
        view.backgroundColor = .black
        view.attach(playerLayer)
        return view
    }

    func updateUIView(_ uiView: PlayerLayerHostView, context: Context) {
        uiView.attach(playerLayer)
    }
}

/// UIView, die den `AVPlayerLayer` als Sublayer trägt und auf ihre Bounds synct.
final class PlayerLayerHostView: UIView {
    private weak var hosted: AVPlayerLayer?

    func attach(_ playerLayer: AVPlayerLayer) {
        guard hosted !== playerLayer else { return }
        hosted?.removeFromSuperlayer()
        hosted = playerLayer
        playerLayer.frame = bounds
        layer.addSublayer(playerLayer)
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        // Ohne implizite Animation, sonst „springt" der Layer bei Rotation/Resize.
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        hosted?.frame = bounds
        CATransaction.commit()
    }
}
#endif

#if os(macOS)
import AppKit

extension PlayerLayerView: NSViewRepresentable {
    func makeNSView(context: Context) -> PlayerLayerHostView {
        let view = PlayerLayerHostView()
        view.attach(playerLayer)
        return view
    }

    func updateNSView(_ nsView: PlayerLayerHostView, context: Context) {
        nsView.attach(playerLayer)
    }
}

/// NSView (layer-backed), die den `AVPlayerLayer` als Sublayer trägt.
final class PlayerLayerHostView: NSView {
    private weak var hosted: AVPlayerLayer?

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer = CALayer()
        layer?.backgroundColor = NSColor.black.cgColor
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) wird nicht verwendet") }

    func attach(_ playerLayer: AVPlayerLayer) {
        guard hosted !== playerLayer else { return }
        hosted?.removeFromSuperlayer()
        hosted = playerLayer
        playerLayer.frame = bounds
        layer?.addSublayer(playerLayer)
    }

    override func layout() {
        super.layout()
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        hosted?.frame = bounds
        CATransaction.commit()
    }
}
#endif
