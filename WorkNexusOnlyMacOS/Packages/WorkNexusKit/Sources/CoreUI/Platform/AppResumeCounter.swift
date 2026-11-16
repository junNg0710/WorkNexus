import AppKit
import Observation

/// Ported from: lib/core/platform/app_resume.dart
/// Counts the times the user comes back to the app (the app becoming active), so on-screen data fetched elsewhere — e.g.
/// a merge request just merged in the browser — can refresh then. Flipping between windows must not refetch every time,
/// so returns within `minGap` of the last counted one are ignored.
@MainActor @Observable
public final class AppResumeCounter {
    public private(set) var count = 0
    @ObservationIgnored private var last: Date?
    @ObservationIgnored private var token: NSObjectProtocol?
    @ObservationIgnored private let minGap: TimeInterval
    @ObservationIgnored private let now: () -> Date

    public init(minGap: TimeInterval = 10, center: NotificationCenter = .default,
                name: Notification.Name = NSApplication.didBecomeActiveNotification, now: @escaping () -> Date = Date.init) {
        self.minGap = minGap; self.now = now
        token = center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.resumed() }
        }
    }

    deinit { if let token { NotificationCenter.default.removeObserver(token) } }

    func resumed() {
        let t = now()
        if let last, t.timeIntervalSince(last) < minGap { return }
        last = t
        count += 1
    }
}
