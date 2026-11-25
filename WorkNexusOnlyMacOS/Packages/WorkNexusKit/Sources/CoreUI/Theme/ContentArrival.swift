import AppKit
import SwiftUI

public extension View {
    /// New content settles in: when `trigger` changes, the content shows through a thin veil of `backdrop` (the colour
    /// behind it) that clears over `AppMotion.base`. Its identity, size and position do not change.
    ///
    /// The veil is one layer animated by Core Animation, off the main thread. Fading the content itself (opacity, offset)
    /// had SwiftUI update the whole subtree on every frame of the animation, right when the main thread is busiest with
    /// the content that just arrived: on a chat switch that doubled the late frames. Over a uniform backdrop the two look
    /// the same - content at 80 % is the backdrop at 20 % over it.
    func contentArrival<Trigger: Equatable>(on trigger: Trigger, backdrop: Color, enabled: Bool = true) -> some View {
        modifier(ContentArrival(trigger: trigger, backdrop: backdrop, enabled: enabled))
    }
}

private struct ContentArrival<Trigger: Equatable>: ViewModifier {
    @Environment(\.appTheme) private var theme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let trigger: Trigger
    let backdrop: Color
    let enabled: Bool

    func body(content: Content) -> some View {
        content.overlay {
            ArrivalVeil(trigger: trigger, color: NSColor(backdrop), duration: theme.motion.base,
                        animates: enabled && !reduceMotion)
                .allowsHitTesting(false)
                .accessibilityHidden(true)
        }
    }
}

/// The veil: a layer that is clear at rest and, on a new `trigger`, starts at `ArrivalVeilView.strength` and clears.
private struct ArrivalVeil<Trigger: Equatable>: NSViewRepresentable {
    let trigger: Trigger
    let color: NSColor
    let duration: Double
    let animates: Bool

    final class Coordinator { var last: Trigger?; var seen = false }

    func makeCoordinator() -> Coordinator { Coordinator() }
    func makeNSView(context: Context) -> ArrivalVeilView { ArrivalVeilView() }

    func updateNSView(_ view: ArrivalVeilView, context: Context) {
        let coordinator = context.coordinator
        defer { coordinator.last = trigger; coordinator.seen = true }
        // The first value is what the content was built with, not an arrival.
        guard coordinator.seen, coordinator.last != trigger, animates else { return }
        view.play(color: color, duration: duration)
    }
}

final class ArrivalVeilView: NSView {
    static let strength: Float = 0.2

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        layer?.opacity = 0
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    /// Clicks, hovers and drags go to what is under the veil.
    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    func play(color: NSColor, duration: Double) {
        guard let layer else { return }
        effectiveAppearance.performAsCurrentDrawingAppearance { layer.backgroundColor = color.cgColor }
        let fade = CABasicAnimation(keyPath: "opacity")
        fade.fromValue = Self.strength
        fade.toValue = 0
        fade.duration = duration
        fade.timingFunction = CAMediaTimingFunction(name: .easeOut)
        layer.add(fade, forKey: "arrival")
    }
}
