import AVFoundation
import AppKit
import SwiftUI

/// The picture of an `AVPlayer`: an `NSView` backed by an `AVPlayerLayer` that keeps the aspect ratio. It has no
/// controls and takes no events (the SwiftUI layer above it owns clicks and keys).
struct VideoSurface: NSViewRepresentable {
    let player: AVPlayer

    func makeNSView(context: Context) -> PlayerLayerView {
        let view = PlayerLayerView()
        view.playerLayer.player = player
        return view
    }

    func updateNSView(_ view: PlayerLayerView, context: Context) {
        if view.playerLayer.player !== player { view.playerLayer.player = player }
    }
}

final class PlayerLayerView: NSView {
    var playerLayer: AVPlayerLayer { layer as! AVPlayerLayer }

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        playerLayer.videoGravity = .resizeAspect
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }
    override func makeBackingLayer() -> CALayer { AVPlayerLayer() }
    override func hitTest(_ point: NSPoint) -> NSView? { nil }
    override var acceptsFirstResponder: Bool { false }
}
