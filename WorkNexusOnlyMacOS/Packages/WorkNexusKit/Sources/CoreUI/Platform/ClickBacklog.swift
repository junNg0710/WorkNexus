/// Not in the Flutter app.
import AppKit

/// The clicks the user has made that the app has not got to yet: they wait in the event queue while the main thread is
/// busy with the one before.
@MainActor
public enum ClickBacklog {
    /// Whether a click is waiting behind the one being handled, landing where `matches` says: a point of the window's
    /// content from its top-left corner, as SwiftUI's global frames are.
    public static func hasClick(where matches: (CGPoint) -> Bool = { _ in true }) -> Bool {
        guard let app = NSApp, let next = app.nextEvent(matching: .leftMouseDown, until: nil, inMode: .default, dequeue: false) else {
            return false
        }
        let at = next.locationInWindow, height = next.window?.contentView?.bounds.height ?? 0
        return matches(CGPoint(x: at.x, y: height - at.y))
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
    private let isBehind: () -> Bool
    private let recheck: TimeInterval

    /// `recheck`: how soon a kept job is looked at again, in case the click that was waiting handed in nothing.
    public init(recheck: TimeInterval = 0.02, isBehind: @escaping () -> Bool) {
        self.recheck = recheck; self.isBehind = isBehind
    }

    /// A job is being kept for later.
    public var hasPending: Bool { job != nil }

    public func run(_ job: @escaping () -> Void) {
        self.job = job
        if !waiting { attempt() }
    }

    /// Drops the job being kept, if any.
    public func cancel() { job = nil }

    private func attempt() {
        waiting = false
        guard let job else { return }
        if isBehind() {
            waiting = true
            DispatchQueue.main.asyncAfter(deadline: .now() + recheck) { [weak self] in
                MainActor.assumeIsolated { self?.attempt() }
            }
            return
        }
        self.job = nil
        job()
    }
}
