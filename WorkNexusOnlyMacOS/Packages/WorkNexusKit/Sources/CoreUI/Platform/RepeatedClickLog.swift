/// Not in the Flutter app.
import AppKit
import CoreDomain

/// Tells a click made again at the same spot from an ordinary one.
///
/// A button that does not answer is clicked again, a moment later, where the pointer already is. A double click is
/// faster than that, and two clicks far apart in time or place are two things done.
struct RepeatedClickGate {
    /// Sooner than this is a double click.
    static let soonest: TimeInterval = 0.35
    /// Later than this is another click, not a second try.
    static let latest: TimeInterval = 4
    /// How far the pointer may have drifted between the two.
    static let slop: CGFloat = 8

    private var last: (point: CGPoint, window: Int, time: TimeInterval, what: String)?

    /// A click at `point` in window `window` at `time`, landing on `what`. Returns the earlier click it repeats: how long
    /// ago it was and what that one landed on.
    mutating func note(_ point: CGPoint, window: Int, time: TimeInterval, what: String) -> (gap: TimeInterval, first: String)? {
        defer { last = (point, window, time, what) }
        guard let last, last.window == window else { return nil }
        let gap = time - last.time
        guard gap >= Self.soonest, gap <= Self.latest, hypot(point.x - last.point.x, point.y - last.point.y) <= Self.slop else { return nil }
        return (gap, last.what)
    }
}

/// Writes into the log every click that was made again at the same spot, with what each of the two landed on: which
/// window (the app's own, the floating pet's, a bubble's, a popover's), which AppKit view in it, and how the app was at
/// that moment. A button that "sometimes cannot be pressed" leaves its trace here the next time it happens; nobody has to
/// catch it in the act. Places and class names only, never what is on screen.
@MainActor
public final class RepeatedClickLog {
    public static let shared = RepeatedClickLog()
    private var gate = RepeatedClickGate()
    private var monitor: Any?
    /// What lies over the app's content now (a search's results, a toast, a dialog, a ticket's panel), as its owners say.
    private var up: Set<String> = []

    /// `what` came up over the content, or went away: named in the line of a click made again while it is up, since a
    /// layer of SwiftUI's own that takes a click is not an AppKit view the click's target would show.
    public func mark(_ what: String, up isUp: Bool) {
        if isUp { up.insert(what) } else { up.remove(what) }
    }

    /// Starts watching, once.
    public func start() {
        guard monitor == nil else { return }
        monitor = NSEvent.addLocalMonitorForEvents(matching: .leftMouseDown) { [weak self] event in
            MainActor.assumeIsolated { self?.note(event) }
            return event
        }
    }

    private func note(_ event: NSEvent) {
        guard let window = event.window else { return }
        let at = event.locationInWindow
        // From the window's top-left, as the eye reads a screenshot.
        let point = CGPoint(x: at.x, y: window.frame.height - at.y)
        let what = Self.target(of: event, in: window) + (up.isEmpty ? "" : " {over the content: \(up.sorted().joined(separator: ", "))}")
        guard let earlier = gate.note(point, window: window.windowNumber, time: event.timestamp, what: what) else { return }
        Diagnostics.info("clicks", "Clicked again at \(Int(point.x)),\(Int(point.y)) after \(Int(earlier.gap * 1000)) ms. First: \(earlier.first). Now: \(what)")
    }

    /// What a click lands on, and how the app is at that moment.
    static func target(of event: NSEvent, in window: NSWindow) -> String {
        var chain: [String] = []
        var view = window.contentView?.superview?.hitTest(event.locationInWindow)
        while let v = view, chain.count < 4 {
            chain.append(String(String(describing: type(of: v)).prefix(40)))
            view = v.superview
        }
        var state: [String] = []
        if !NSApp.isActive { state.append("app not active") }
        if !window.isKeyWindow { state.append("window not key") }
        if NSApp.modalWindow != nil { state.append("modal") }
        if ScrollPointerPause.shared.isPaused(window) { state.append("scrolling") }
        if window.attachedSheet != nil { state.append("sheet") }
        let children = window.childWindows?.count ?? 0
        if children > 0 { state.append("\(children) child windows") }
        let size = "\(Int(window.frame.width))×\(Int(window.frame.height))"
        return "\(type(of: window)) \(size) → \(chain.isEmpty ? "no view" : chain.joined(separator: " < "))" + (state.isEmpty ? "" : " [\(state.joined(separator: ", "))]")
    }
}
