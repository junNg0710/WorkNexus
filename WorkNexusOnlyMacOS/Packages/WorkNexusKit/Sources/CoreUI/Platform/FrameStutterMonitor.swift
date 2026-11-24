/// Not in the Flutter app.
import AppKit
import CoreDomain
import QuartzCore

/// Watches the screen's frames while the performance log is on: a frame the main thread held up (a stuttering scroll, a
/// slow redraw) is gathered into `FrameStutterWindow` and written with where it happened (`PerformanceLog`) and what the
/// main thread was seen running meanwhile (`MainThreadSampler`). It runs only while the app is in front; off, nothing ticks.
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
        MainThreadSampler.shared.start()
        // A click before the frames stopped (or at launch, before the window is in front) is not timed across the pause.
        PerformanceLog.cancelInteraction()
    }

    private func pause() {
        link?.invalidate(); link = nil; last = nil
        MainThreadSampler.shared.stop()
        if let line = window.close() { PerformanceLog.note(line) }
    }

    @objc private func tick(_ link: CADisplayLink) {
        defer { last = link.timestamp }
        let stacks = MainThreadSampler.shared.beat()
        guard let last else { return }
        let frame = link.duration > 0 ? link.duration : 1.0 / 60
        let gap = link.timestamp - last
        // What held a late frame up: the measured main-thread work between the two frames, and where the thread was seen.
        let late = gap - frame >= FrameStutterWindow.lateAfter
        let busy = late ? PerformanceLog.busy(from: last, to: link.timestamp) : [:]
        // The names of where the thread was seen are found off the main thread and join the line a moment later:
        // finding them here cost tens of milliseconds after a late frame and hundreds after a hang (3–4 % of the main
        // thread while moving between places), enough to make the next frame late too.
        let lateBy = gap - frame
        if lateBy >= FrameStutterWindow.hangAfter {
            MainThreadSampler.tallyLater(stacks) { seen in
                PerformanceLog.note(FrameStutterWindow.hangLine(late: lateBy, busy: busy, seen: seen))
            }
            // The window itself only moves on (a hang is written on its own, not counted among its late frames).
            if let line = window.add(gap: frame, frame: frame, now: link.timestamp) { PerformanceLog.note(line) }
        } else {
            if let line = window.add(gap: gap, frame: frame, now: link.timestamp, busy: busy) { PerformanceLog.note(line) }
            if late, !stacks.isEmpty {
                MainThreadSampler.tallyLater(stacks) { [weak self] seen in self?.window.note(seen: seen) }
            }
        }
        PerformanceLog.frameShown(at: link.timestamp)
    }
}
