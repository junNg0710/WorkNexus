/// Not in the Flutter app.
import AppKit
import QuartzCore
import SwiftUI

/// What a mouse wheel's turns have left to scroll, spent frame by frame along an ease-out curve.
///
/// Each frame covers the same share of what is left (`1 - e^(-dt / timeConstant)`): fast at first, slowing into place,
/// and a new turn of the wheel simply adds to what is left - nothing restarts, so turning the wheel on and on stays
/// one movement. Never slower than `minimumSpeed`, or the last few points would take a second to arrive.
struct WheelGlide {
    /// Points still to scroll, signed as the wheel's own deltas are.
    private(set) var remaining: CGFloat = 0
    /// The time in which what is left falls to about a third (0.37).
    let timeConstant: TimeInterval
    let minimumSpeed: CGFloat

    init(timeConstant: TimeInterval = 0.085, minimumSpeed: CGFloat = 90) {
        self.timeConstant = timeConstant; self.minimumSpeed = minimumSpeed
    }

    var isMoving: Bool { remaining != 0 }

    /// The wheel turned by `points`. A turn the other way gives up what was left of the last.
    mutating func turn(_ points: CGFloat) {
        if remaining != 0, (points > 0) != (remaining > 0) { remaining = 0 }
        remaining += points
    }

    /// The points to scroll in a frame `dt` seconds long.
    mutating func step(_ dt: TimeInterval) -> CGFloat {
        guard remaining != 0, dt > 0 else { return 0 }
        let eased = abs(remaining) * CGFloat(1 - exp(-dt / timeConstant))
        let move = min(abs(remaining), max(eased, minimumSpeed * CGFloat(dt))) * (remaining > 0 ? 1 : -1)
        remaining -= move
        if abs(remaining) < 0.01 { remaining = 0 }
        return move
    }

    mutating func stop() { remaining = 0 }
}

/// Scrolls the scroll views it is given smoothly under a mouse wheel.
///
/// A wheel that turns in notches sends a jump of some lines per notch, and AppKit moves the content there at once: the
/// text leaps, and the eye has to find its place again. Here a notch's distance is covered over a few frames instead
/// (`WheelGlide`), as a trackpad's own scrolling is. A trackpad or a Magic Mouse already sends smooth, measured
/// scrolling and is left to the system, as is every scroll view not handed to `adopt`.
///
/// Whether it is on (`isOn`) and how far a turn goes (`travel`) are the user's, set in Settings. `defaults write
/// com.worknexus.macos wheel.glide -float 0.12` changes how long the glide takes (0.085 s, read at launch).
@MainActor
public final class SmoothWheelScroll: NSObject {
    public static let shared = SmoothWheelScroll()

    /// Off: the wheel is left to AppKit, which jumps.
    public var isOn = true
    /// How far a turn goes against the distance the system gives it: 4 is the 40 points a line that browsers scroll.
    public var travel: CGFloat = 4
    /// The least one event of the wheel moves.
    public static let leastTurn: CGFloat = 40

    private struct Adopted {
        weak var view: NSScrollView?
        var onTurn: () -> Void
        var onMoving: (Bool) -> Void
    }

    private var adopted: [ObjectIdentifier: Adopted] = [:]
    private var monitor: Any?
    private var glide: WheelGlide
    private weak var moving: NSScrollView?
    private var link: CADisplayLink?
    private var lastFrame: CFTimeInterval = 0
    private var carry: CGFloat = 0
    /// Where the content was when the last frame scrolled, and for how many frames in a row scrolling left it there.
    private var lastOrigin: CGFloat = .nan
    private var stillFrames = 0
    private static let stillLimit = 4

    init(defaults: UserDefaults = .standard) {
        let time = defaults.double(forKey: "wheel.glide")
        glide = WheelGlide(timeConstant: time > 0 ? time : 0.085)
    }

    /// `scrollView` glides under the wheel from now on. `onTurn` runs at each turn of the wheel taken (the reader is
    /// scrolling by hand), `onMoving` when the content starts and stops moving for it.
    public func adopt(_ scrollView: NSScrollView, onTurn: @escaping () -> Void = {}, onMoving: @escaping (Bool) -> Void = { _ in }) {
        adopted = adopted.filter { $0.value.view != nil }
        adopted[ObjectIdentifier(scrollView)] = Adopted(view: scrollView, onTurn: onTurn, onMoving: onMoving)
        if monitor == nil {
            monitor = NSEvent.addLocalMonitorForEvents(matching: .scrollWheel) { [weak self] event in
                let taken = MainActor.assumeIsolated { self?.take(event) ?? false }
                return taken ? nil : event
            }
        }
    }

    /// Whether `event` is a notched wheel turning over an adopted scroll view - then it is glided, not passed on.
    private func take(_ event: NSEvent) -> Bool {
        guard isOn, !event.hasPreciseScrollingDeltas, event.phase == [], event.momentumPhase == [],
              event.scrollingDeltaY != 0, abs(event.scrollingDeltaY) >= abs(event.scrollingDeltaX),
              event.modifierFlags.intersection([.shift, .option, .command, .control]).isEmpty,
              let scrollView = target(of: event) else { return false }
        // The distance the system would scroll for this turn, in points.
        let system = CGFloat(event.cgEvent?.getIntegerValueField(.scrollWheelEventPointDeltaAxis1) ?? 0)
        turn(points: Self.distance(system: system, lines: event.scrollingDeltaY, travel: travel), in: scrollView)
        return true
    }

    /// How far one event of the wheel scrolls: the system's own distance (or ten points a line when it gives none)
    /// times `travel`, and at least `leastTurn` - a slow notch is ten points to the system, a quarter of a message.
    public static func distance(system: CGFloat, lines: CGFloat, travel: CGFloat) -> CGFloat {
        let base = system != 0 ? system : lines * 10
        return (base < 0 ? -1 : 1) * max(abs(base) * travel, leastTurn)
    }

    /// The adopted scroll view under the pointer, unless a scroll view inside it would scroll for the wheel itself.
    private func target(of event: NSEvent) -> NSScrollView? {
        var view = event.window?.contentView?.hitTest(event.locationInWindow)
        while let current = view {
            if let scroll = current as? NSScrollView {
                if adopted[ObjectIdentifier(scroll)]?.view != nil { return scroll }
                if let document = scroll.documentView, document.frame.height > scroll.contentView.bounds.height + 1 { return nil }
            }
            view = current.superview
        }
        return nil
    }

    /// The wheel turned by `points` over `scrollView` (positive: toward the top of the content).
    public func turn(points: CGFloat, in scrollView: NSScrollView) {
        if moving !== scrollView { stop() }
        let entry = adopted[ObjectIdentifier(scrollView)]
        entry?.onTurn()
        if !glide.isMoving { entry?.onMoving(true) }
        moving = scrollView
        glide.turn(points)
        guard link == nil else { return }
        lastFrame = 0
        let link = scrollView.displayLink(target: self, selector: #selector(frame(_:)))
        link.add(to: .main, forMode: .common)
        self.link = link
    }

    @objc private func frame(_ link: CADisplayLink) {
        guard let scrollView = moving, scrollView.window != nil else { stop(); return }
        let dt = lastFrame == 0 ? link.duration : link.timestamp - lastFrame
        lastFrame = link.timestamp
        // A frame that came late does not leap to make up for it.
        carry += glide.step(min(dt, 0.05))
        let whole = carry.rounded(.towardZero)
        carry -= whole
        if whole != 0 {
            // Against the end of the content there is nowhere left to go: what the last frames asked for moved nothing.
            // (Looked at a frame later: the scroll view may take a scroll in only with its next layout.)
            let origin = scrollView.contentView.bounds.origin.y
            stillFrames = origin == lastOrigin ? stillFrames + 1 : 0
            lastOrigin = origin
            if stillFrames >= Self.stillLimit { glide.stop() }
            // A measured wheel event, handled as a trackpad's is; setting the clip view's origin is undone by the
            // scroll view's own state.
            else if let cg = CGEvent(scrollWheelEvent2Source: nil, units: .pixel, wheelCount: 1, wheel1: Int32(whole), wheel2: 0, wheel3: 0),
                    let event = NSEvent(cgEvent: cg) {
                scrollView.scrollWheel(with: event)
            }
        }
        if !glide.isMoving { stop() }
    }

    private func stop() {
        link?.invalidate(); link = nil
        glide.stop(); carry = 0
        lastOrigin = .nan; stillFrames = 0
        if let scrollView = moving { adopted[ObjectIdentifier(scrollView)]?.onMoving(false) }
        moving = nil
    }
}

/// Hands the scroll view this view lies in to `SmoothWheelScroll`.
private struct WheelGlideAnchor: NSViewRepresentable {
    let onTurn: () -> Void
    let onMoving: (Bool) -> Void

    func makeNSView(context: Context) -> AnchorView { AnchorView() }
    func updateNSView(_ view: AnchorView, context: Context) { view.onTurn = onTurn; view.onMoving = onMoving; view.adopt() }

    final class AnchorView: NSView {
        var onTurn: () -> Void = {}
        var onMoving: (Bool) -> Void = { _ in }
        private weak var adoptedScroll: NSScrollView?

        override func hitTest(_ point: NSPoint) -> NSView? { nil }
        override func viewDidMoveToWindow() { super.viewDidMoveToWindow(); adopt() }

        func adopt() {
            guard let scroll = enclosingScrollView, scroll !== adoptedScroll else { return }
            adoptedScroll = scroll
            SmoothWheelScroll.shared.adopt(scroll, onTurn: { [weak self] in self?.onTurn() }, onMoving: { [weak self] in self?.onMoving($0) })
        }
    }
}

public extension View {
    /// Put on the content of a `ScrollView`: a notched mouse wheel scrolls it smoothly (see `SmoothWheelScroll`).
    func smoothWheelScrolling(onTurn: @escaping () -> Void = {}, onMoving: @escaping (Bool) -> Void = { _ in }) -> some View {
        background { WheelGlideAnchor(onTurn: onTurn, onMoving: onMoving).frame(width: 0, height: 0).allowsHitTesting(false) }
    }
}
