/// Not in the Flutter app.
import AppKit
import CoreDomain
import QuartzCore

/// Watches the screen's frames while the performance log is on: a frame the main thread held up (a stuttering scroll, a
/// slow redraw) is gathered into `FrameStutterWindow` and written with where it happened (`PerformanceLog`). It runs only
/// while the app is in front; off, nothing ticks.
@MainActor
public final class FrameStutterMonitor: NSObject {
    public static let shared = FrameStutterMonitor()
    private var link: CADisplayLink?
    private var last: CFTimeInterval?
    private var window = FrameStutterWindow()
    private var observers: [NSObjectProtocol] = []
    private var wanted = false

    /// Starts or stops watching (the performance log's switch).
    public func setRunning(_ on: Bool) {
        wanted = on
        if on {
            if observers.isEmpty {
                let center = NotificationCenter.default
                observers = [
                    center.addObserver(forName: NSApplication.didBecomeActiveNotification, object: nil, queue: .main) { [weak self] _ in
                        MainActor.assumeIsolated { self?.resume() }
                    },
                    center.addObserver(forName: NSApplication.didResignActiveNotification, object: nil, queue: .main) { [weak self] _ in
                        MainActor.assumeIsolated { self?.pause() }
                    },
                ]
            }
            if NSApp?.isActive ?? true { resume() }
        } else {
            pause()
            observers.forEach(NotificationCenter.default.removeObserver)
            observers = []
        }
    }

    private func resume() {
        guard wanted, link == nil, let screen = NSScreen.main else { return }
        let l = screen.displayLink(target: self, selector: #selector(tick(_:)))
        l.add(to: .main, forMode: .common)
        link = l; last = nil
    }

    private func pause() {
        link?.invalidate(); link = nil; last = nil
        if let line = window.close() { PerformanceLog.note(line) }
    }

    @objc private func tick(_ link: CADisplayLink) {
        defer { last = link.timestamp }
        guard let last else { return }
        let frame = link.duration > 0 ? link.duration : 1.0 / 60
        let gap = link.timestamp - last
        // What held a late frame up: the measured main-thread work between the two frames.
        let busy = gap - frame >= FrameStutterWindow.lateAfter ? PerformanceLog.busy(from: last, to: link.timestamp) : [:]
        if let line = window.add(gap: gap, frame: frame, now: link.timestamp, busy: busy) { PerformanceLog.note(line) }
        PerformanceLog.frameShown(at: link.timestamp)
    }
}
