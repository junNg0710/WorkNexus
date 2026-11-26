/// Not in the Flutter app.
import AppKit

/// When a mouse move may be handled: `interval` after the last one that was.
struct PointerMoveGate {
    let interval: TimeInterval
    private var last = -TimeInterval.infinity

    init(interval: TimeInterval) { self.interval = interval }

    /// A move at `time`: nil when it is handled now, else how long it has to wait for its turn.
    mutating func wait(at time: TimeInterval) -> TimeInterval? {
        let due = last + interval
        if time >= due { last = time; return nil }
        return due - time
    }

    /// The move that was waiting got handled at `time`.
    mutating func handled(at time: TimeInterval) { last = time }
}

/// Hands the app's windows at most `rate` mouse moves a second.
///
/// On every mouse move AppKit and SwiftUI work out again what the pointer is over, three times - the window's own hit
/// test, the hover handlers', the pointer shape's - each a walk through the window's whole view tree: close to a
/// millisecond together with a chat open (measured), and moves come as often as the screen refreshes. In the installed
/// app that was a quarter of the main thread's work while the mouse moved. What lies under the pointer is worth knowing
/// some thirty times a second, not a hundred: a move that comes sooner after the last one handled waits for its turn,
/// and what is handled then is where the pointer is at that moment - so the place the pointer comes to rest at is always
/// seen, at most a thirtieth of a second late. Clicks, drags and scrolling are not moves and pass as they come.
///
/// Off with `defaults write com.worknexus.macos experiments.fullPointerRate -bool YES` (read once, at launch).
@MainActor
public final class PointerMovePace {
    public static let shared = PointerMovePace()

    private var gate: PointerMoveGate
    private let send: (NSEvent) -> Void
    private var monitor: Any?
    /// The window of the move that is waiting for its turn.
    private weak var waiting: NSWindow?
    private var turnPending = false
    /// A move of ours is on its way through the app: the monitor lets it by.
    private var passing = false
    /// Moves handled as they came, and moves that waited (several may share one turn), since launch - for diagnostics.
    public private(set) var handledAtOnce = 0
    public private(set) var waited = 0
    /// Turns taken: the moves handled in place of those that waited.
    public private(set) var turns = 0

    /// `send` hands a move to the app (the app's own `sendEvent` when not given).
    init(rate: Double = 30, send: ((NSEvent) -> Void)? = nil) {
        gate = PointerMoveGate(interval: 1 / rate)
        self.send = send ?? { NSApp.sendEvent($0) }
    }

    /// Starts pacing, once.
    public func start() {
        guard monitor == nil, !UserDefaults.standard.bool(forKey: "experiments.fullPointerRate") else { return }
        monitor = NSEvent.addLocalMonitorForEvents(matching: .mouseMoved) { [weak self] event in
            let handledNow = MainActor.assumeIsolated { () -> Bool in
                guard let self, !self.passing, let window = event.window else { return true }
                return self.admits(moveAt: event.timestamp, in: window)
            }
            return handledNow ? event : nil
        }
    }

    /// Whether a move in `window` at `time` (seconds since the Mac started, as events carry) is handled now. When not,
    /// the pointer's place is handled when its turn comes.
    func admits(moveAt time: TimeInterval, in window: NSWindow) -> Bool {
        guard let wait = gate.wait(at: time) else {
            waiting = nil
            handledAtOnce += 1
            return true
        }
        waiting = window
        waited += 1
        if !turnPending {
            turnPending = true
            DispatchQueue.main.asyncAfter(deadline: .now() + wait) { [weak self] in
                MainActor.assumeIsolated { self?.takeTurn() }
            }
        }
        return false
    }

    private func takeTurn() {
        turnPending = false
        // A move handled since then took the turn (the main thread was busy past it).
        guard let window = waiting else { return }
        waiting = nil
        let now = ProcessInfo.processInfo.systemUptime
        // Where the pointer is now, not where the move that waited was: it may have gone on since, out of the window too
        // (then this is what tells the views it left).
        guard let event = NSEvent.mouseEvent(with: .mouseMoved, location: window.mouseLocationOutsideOfEventStream,
                                             modifierFlags: NSEvent.modifierFlags, timestamp: now, windowNumber: window.windowNumber,
                                             context: nil, eventNumber: 0, clickCount: 0, pressure: 0) else { return }
        gate.handled(at: now)
        turns += 1
        passing = true
        send(event)
        passing = false
    }
}
