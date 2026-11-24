/// Not in the Flutter app.
import AppKit
import QuartzCore

/// The clicks the user has made that the app has not got to yet: they wait in the event queue while the main thread is
/// busy with the one before.
///
/// It does not look into the event queue: asking AppKit for the next event runs a turn of the run loop, and with it a
/// whole layout and drawing of the window, in the middle of handling the click being asked about (7 % of the main thread
/// while clicking through places). The system keeps the time of the last press of the mouse button, whoever it was
/// for; a press later than the last one this app was handed is one still waiting.
@MainActor
public enum ClickBacklog {
    /// Where the time of the last press and the pointer's place come from: the system, or a run that posts its own
    /// clicks (the system knows nothing of those).
    public struct Source {
        /// When the mouse button was last pressed, on the clock events are stamped with (seconds since startup).
        public var lastPress: () -> TimeInterval
        /// The pointer in the app's window, from the top-left corner of its content; nil when it is not over it.
        public var pointer: () -> CGPoint?
        public init(lastPress: @escaping () -> TimeInterval, pointer: @escaping () -> CGPoint?) {
            self.lastPress = lastPress; self.pointer = pointer
        }

        @MainActor public static let system = Source(
            lastPress: {
                ProcessInfo.processInfo.systemUptime - CGEventSource.secondsSinceLastEventType(.combinedSessionState, eventType: .leftMouseDown)
            },
            pointer: {
                guard let app = NSApp, app.isActive, let window = app.keyWindow ?? app.mainWindow, let content = window.contentView else { return nil }
                let pointer = NSEvent.mouseLocation
                // A press on another app's window lying over this one is not this app's to wait for.
                guard NSWindow.windowNumber(at: pointer, belowWindowWithWindowNumber: 0) == window.windowNumber else { return nil }
                let at = window.convertPoint(fromScreen: pointer)
                return CGPoint(x: at.x, y: content.bounds.height - at.y)
            })
    }

    public static var source = Source.system
    private static var seen = ClickTimes()
    private static var monitor: Any?

    /// Starts noting the presses handed to the app (once; `hasClick` does it too, and says "none" until one is noted).
    public static func start() {
        guard monitor == nil else { return }
        monitor = NSEvent.addLocalMonitorForEvents(matching: .leftMouseDown) { event in
            seen.handed(at: event.timestamp, lastPress: source.lastPress())
            return event
        }
    }

    /// Whether a click is waiting behind the one being handled, with the pointer where `matches` says: a point of the
    /// window's content from its top-left corner, as SwiftUI's global frames are. (Where the pointer is now stands for
    /// where the waiting click landed: someone clicking down a list keeps the pointer on it.)
    public static func hasClick(where matches: (CGPoint) -> Bool = { _ in true }) -> Bool {
        start()
        guard seen.isBehind(lastPress: source.lastPress()), let at = source.pointer() else { return false }
        return matches(at)
    }
}

/// The presses of the mouse button handed to the app, against the system's "last press": tells when a later one waits.
struct ClickTimes {
    /// A second press cannot follow the first sooner.
    static let apart: TimeInterval = 0.02
    /// Nobody waits this long on a click: a gap this size is the two clocks having moved apart (sleep), not a backlog.
    static let tooLong: TimeInterval = 10
    /// The stamp of the last press handed to the app.
    private(set) var handed: TimeInterval?
    /// How far the system's "last press" runs ahead of an event's own stamp when nothing waits: the smallest seen.
    private(set) var lead = TimeInterval.infinity

    /// A press stamped `stamp` was handed to the app while the system's last press was at `lastPress`.
    mutating func handed(at stamp: TimeInterval, lastPress: TimeInterval) {
        handed = stamp
        let gap = lastPress - stamp
        // The press handed is the last one unless others wait behind it, which only makes the gap longer.
        if gap < lead || gap - lead > Self.tooLong { lead = gap }
    }

    /// Whether the system has seen a press later than the last one handed to the app.
    func isBehind(lastPress: TimeInterval) -> Bool {
        guard let handed, lead.isFinite else { return false }
        let later = lastPress - handed - lead
        return later > Self.apart && later < Self.tooLong
    }
}

/// Runs only the last of the jobs handed to it while the user is ahead of the app.
///
/// Someone clicking through places faster than the app can show them leaves clicks waiting, and each one used to build its
/// whole screen before the next was even looked at: the window stood still for seconds and then played the clicks back
/// one by one. With this, a job handed in while `isBehind` says another such click is waiting is only kept; the click
/// behind it replaces it, and what gets built is where the user ended up. With nothing waiting — every click of ordinary
/// use — the job runs at once, as if this were not here.
@MainActor
public final class CatchUpGate {
    private var job: (() -> Void)?
    private var waiting = false
    private var keptSince: CFTimeInterval?
    private let isBehind: () -> Bool
    private let recheck: TimeInterval
    private let patience: TimeInterval

    /// `recheck`: how soon a kept job is looked at again, in case the click that was waiting handed in nothing.
    /// `patience`: how long a job is kept at most; `isBehind` being wrong must never leave a click without its effect.
    public init(recheck: TimeInterval = 0.02, patience: TimeInterval = 0.4, isBehind: @escaping () -> Bool) {
        self.recheck = recheck; self.patience = patience; self.isBehind = isBehind
    }

    /// A job is being kept for later.
    public var hasPending: Bool { job != nil }

    public func run(_ job: @escaping () -> Void) {
        self.job = job
        // A newer job is the user still clicking: the wait starts over.
        keptSince = nil
        if !waiting { attempt() }
    }

    /// Drops the job being kept, if any.
    public func cancel() { job = nil; keptSince = nil }

    private func attempt() {
        waiting = false
        guard let job else { return }
        let now = CACurrentMediaTime()
        if isBehind(), now - (keptSince ?? now) < patience {
            if keptSince == nil { keptSince = now }
            waiting = true
            DispatchQueue.main.asyncAfter(deadline: .now() + recheck) { [weak self] in
                MainActor.assumeIsolated { self?.attempt() }
            }
            return
        }
        self.job = nil
        keptSince = nil
        job()
    }
}
