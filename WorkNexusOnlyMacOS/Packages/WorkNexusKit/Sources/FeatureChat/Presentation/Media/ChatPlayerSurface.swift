import AVFoundation
import AppKit
import SwiftUI

/// The picture of an `AVPlayer`, fitted in its frame, without any system controls (the chat draws its own).
struct ChatPlayerSurface: NSViewRepresentable {
    let player: AVPlayer
    var fill = false

    func makeNSView(context: Context) -> PlayerLayerView {
        let v = PlayerLayerView()
        v.playerLayer.player = player
        v.playerLayer.videoGravity = fill ? .resizeAspectFill : .resizeAspect
        return v
    }

    func updateNSView(_ v: PlayerLayerView, context: Context) {
        if v.playerLayer.player !== player { v.playerLayer.player = player }
        v.playerLayer.videoGravity = fill ? .resizeAspectFill : .resizeAspect
    }

    final class PlayerLayerView: NSView {
        let playerLayer = AVPlayerLayer()
        override init(frame: NSRect) { super.init(frame: frame); wantsLayer = true; layer = playerLayer }
        required init?(coder: NSCoder) { fatalError() }
    }
}
