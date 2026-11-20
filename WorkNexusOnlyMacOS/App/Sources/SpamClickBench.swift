import AppKit
import Foundation
import QuartzCore

#if DEBUG
/// DEBUG builds only: `WN_DEMO_SPAM=x,y;x,y;…` (window points from its top-left) clicks through those points in turn, one
/// every `WN_DEMO_SPAM_MS` (default 200), `WN_DEMO_SPAM_ROUNDS` times over (default 5), starting `WN_DEMO_SPAM_AFTER`
/// seconds in (default 9) — someone hammering the rail and a board's filters without waiting for anything to finish.
///
/// For each round it prints how late the clicks ran (the main thread still busy with the ones before), the main thread's
/// CPU time, the longest gap between frames, and how long after the last click the app came to rest: what the app does
/// with work nobody is waiting for any more.
@MainActor
enum SpamClickBench {
    static func start() {
        let env = ProcessInfo.processInfo.environment
        guard let spec = env["WN_DEMO_SPAM"] else { return }
        let points = spec.split(separator: ";").compactMap { p -> NSPoint? in
            let v = p.split(separator: ",").compactMap { Double($0) }
            return v.count == 2 ? NSPoint(x: v[0], y: v[1]) : nil
        }
        guard !points.isEmpty else { return }
        let gap = (env["WN_DEMO_SPAM_MS"].flatMap(Double.init) ?? 200) / 1000
        let rounds = env["WN_DEMO_SPAM_ROUNDS"].flatMap(Int.init) ?? 5
        let after = env["WN_DEMO_SPAM_AFTER"].flatMap(Double.init) ?? 9
        let frames = FrameGaps()
        // How late each click was handled: the time it spent waiting behind the ones before it.
        var handled = 0, worstLate = 0.0
        NSEvent.addLocalMonitorForEvents(matching: .leftMouseDown) { e in
            handled += 1
            worstLate = max(worstLate, ProcessInfo.processInfo.systemUptime - e.timestamp)
            return e
        }
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(after))
            for round in 0..<rounds {
                guard let w = NSApp.windows.first(where: { $0.canBecomeMain && $0.isVisible }) else { return }
                w.orderFrontRegardless()
                frames.reset(); handled = 0; worstLate = 0
                let cpu0 = threadCPU(), began = CACurrentMediaTime()
                // Posted to the app's event queue from another thread, on time whatever the main thread is doing — as a
                // hand on the mouse does — so clicks pile up behind a busy main thread exactly as real ones would.
                let number = w.windowNumber, height = w.frame.height
                for (i, p) in points.enumerated() {
                    DispatchQueue.global(qos: .userInteractive).asyncAfter(deadline: .now() + Double(i) * gap) {
                        post(NSPoint(x: p.x, y: height - p.y), window: number)
                    }
                }
                let lastPosted = began + Double(points.count - 1) * gap
                while handled < points.count, CACurrentMediaTime() - began < 60 { try? await Task.sleep(for: .milliseconds(20)) }
                let rest = await atRest(since: lastPosted)
                print("BENCH spam \(round): \(points.count) clicks \(Int(gap * 1000)) ms apart, latest ran \(Int(worstLate * 1000)) ms late, "
                      + "main cpu \(Int(threadCPU() - cpu0)) ms, \(frames.summary), at rest \(Int(rest * 1000)) ms after the last click")
                fflush(stdout)
                try? await Task.sleep(for: .milliseconds(800))
            }
            print("BENCH spam done"); fflush(stdout)
        }
    }

    /// Seconds from `since` until the main thread went quiet: three 100 ms stretches in a row with under 15 ms of work.
    private static func atRest(since: CFTimeInterval) async -> Double {
        var quiet = 0, quietFrom = CACurrentMediaTime()
        while CACurrentMediaTime() - since < 15 {
            let cpu = threadCPU(), at = CACurrentMediaTime()
            try? await Task.sleep(for: .milliseconds(100))
            if threadCPU() - cpu < 15 {
                if quiet == 0 { quietFrom = at }
                quiet += 1
                if quiet == 3 { return max(0, quietFrom - since) }
            } else {
                quiet = 0
            }
        }
        return 15
    }

    /// The main thread's CPU time so far, in ms.
    private static func threadCPU() -> Double {
        var t = timespec(); clock_gettime(CLOCK_THREAD_CPUTIME_ID, &t)
        return Double(t.tv_sec) * 1000 + Double(t.tv_nsec) / 1_000_000
    }

    /// A click at `at` (window coordinates), put on the app's event queue.
    private nonisolated static func post(_ at: NSPoint, window: Int) {
        for type in [NSEvent.EventType.leftMouseDown, .leftMouseUp] {
            if let e = NSEvent.mouseEvent(with: type, location: at, modifierFlags: [], timestamp: ProcessInfo.processInfo.systemUptime,
                                          windowNumber: window, context: nil, eventNumber: 0, clickCount: 1,
                                          pressure: type == .leftMouseDown ? 1 : 0) {
                NSApplication.shared.postEvent(e, atStart: false)
            }
        }
    }
}
#endif
