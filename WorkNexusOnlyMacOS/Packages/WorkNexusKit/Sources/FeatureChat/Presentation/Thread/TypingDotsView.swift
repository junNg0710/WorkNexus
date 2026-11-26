/// Not in the Flutter app.
import AppKit
import SwiftUI

/// The typing dots drawn as three Core Animation layers.
///
/// As SwiftUI views moved by a `TimelineView`, the dots made the window work out and draw its whole content again on
/// every screen frame for as long as anyone was typing: 258 ms of the main thread a second against 14 without them,
/// measured on an optimized build (144 ms at 30 frames a second). Layers are animated by the window server: the main
/// thread sets the animation up once and is not asked again.
struct TypingDotsLayers: NSViewRepresentable {
    let color: Color
    let size: CGFloat
    let running: Bool

    func makeNSView(context: Context) -> TypingDotsView { TypingDotsView() }

    func updateNSView(_ view: TypingDotsView, context: Context) {
        view.show(color: color.resolve(in: context.environment).cgColor, size: size, running: running)
    }

    func sizeThatFits(_ proposal: ProposedViewSize, nsView: TypingDotsView, context: Context) -> CGSize? {
        TypingDotsView.size(dot: size)
    }
}

final class TypingDotsView: NSView {
    static let animationKey = "typing"
    /// How many steps the rise of a dot is drawn in (it follows `ThreadTypingDots.lift`, a half sine).
    static let steps = 16

    let dots = (0..<3).map { _ in CALayer() }
    private var size: CGFloat = 0
    private var running = false

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        for dot in dots { layer?.addSublayer(dot) }
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { nil }

    /// Three dots half a dot apart, with room above them for the rise.
    static func size(dot: CGFloat) -> CGSize { CGSize(width: dot * 4, height: dot * (1 + ThreadTypingDots.riseHeight)) }

    /// The pointer goes to the row under the dots (its tooltip says who is typing).
    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    func show(color: CGColor, size: CGFloat, running: Bool) {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        for (i, dot) in dots.enumerated() {
            dot.backgroundColor = color
            dot.cornerRadius = size / 2
            // Resting on the bottom edge (the view is not flipped); the rise goes up into the room above.
            dot.frame = CGRect(x: CGFloat(i) * size * 1.5, y: 0, width: size, height: size)
            dot.opacity = Float(ThreadTypingDots.restOpacity)
        }
        CATransaction.commit()
        let changed = running != self.running || size != self.size
        self.size = size
        self.running = running
        if changed { restart() }
    }

    /// A layer loses its animations when its view leaves the window: back in one, they start again.
    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if window != nil { restart() }
    }

    private func restart() {
        for dot in dots { dot.removeAnimation(forKey: Self.animationKey) }
        guard running, size > 0 else { return }
        let period = ThreadTypingDots.period
        let times = (0...Self.steps).map { ThreadTypingDots.riseShare * Double($0) / Double(Self.steps) } + [1]
        let lifts = times.map { ThreadTypingDots.lift(0, $0) }
        for (i, dot) in dots.enumerated() {
            let rise = CAKeyframeAnimation(keyPath: "transform.translation.y")
            rise.values = lifts.map { $0 * ThreadTypingDots.riseHeight * size }
            let fade = CAKeyframeAnimation(keyPath: "opacity")
            fade.values = lifts.map { ThreadTypingDots.restOpacity + (1 - ThreadTypingDots.restOpacity) * $0 }
            for part in [rise, fade] { part.keyTimes = times.map { NSNumber(value: $0) }; part.duration = period }
            let wave = CAAnimationGroup()
            wave.animations = [rise, fade]
            wave.duration = period
            wave.repeatCount = .infinity
            wave.isRemovedOnCompletion = false
            // Each dot the same wave, `stagger` of a period behind its left neighbour.
            wave.timeOffset = period * (1 - Double(i) * ThreadTypingDots.stagger)
            dot.add(wave, forKey: Self.animationKey)
        }
    }
}
