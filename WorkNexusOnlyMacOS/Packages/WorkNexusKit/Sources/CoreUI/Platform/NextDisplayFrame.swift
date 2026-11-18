/// Not in the Flutter app.
import AppKit
import QuartzCore

/// Waits for the screen's next frame: work started after it lands in a frame of its own, so a view that is heavy to
/// show can come in over two frames instead of holding up one. (A timer is not that: one started while the frame was
/// still being built runs out before it is on screen.) A screen that draws no frames (asleep, the window hidden) ends
/// the wait after `timeout`.
@MainActor
public enum NextDisplayFrame {
    public static let timeout: TimeInterval = 0.1

    public static func wait() async {
        guard let screen = NSApp?.keyWindow?.screen ?? NSScreen.main else {
            try? await Task.sleep(for: .milliseconds(17))
            return
        }
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            let waiter = Waiter(continuation)
            let link = screen.displayLink(target: waiter, selector: #selector(Waiter.tick(_:)))
            waiter.link = link
            link.add(to: .main, forMode: .common)
            DispatchQueue.main.asyncAfter(deadline: .now() + timeout) { MainActor.assumeIsolated { waiter.finish() } }
        }
    }

    /// The display link's target. It holds the link (nothing else does) until the first tick or the timeout stops it.
    private final class Waiter: NSObject {
        private var continuation: CheckedContinuation<Void, Never>?
        var link: CADisplayLink?
        init(_ continuation: CheckedContinuation<Void, Never>) { self.continuation = continuation }

        @objc func tick(_ link: CADisplayLink) { finish() }

        func finish() {
            link?.invalidate()
            link = nil
            continuation?.resume()
            continuation = nil
        }
    }
}
