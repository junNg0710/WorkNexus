import CoreDomain
import Foundation

/// Ported from: lib/features/notifications/presentation/widgets/notification_alerts.dart (the "how many" rule)
/// What to raise on the desktop for the notifications a refresh brought in.
public enum DesktopAlertPlan: Equatable, Sendable {
    case none
    /// One desktop notification per ZenTao notification.
    case each([ZenTaoNotification])
    /// More than `maxEach` at once: a single notification counting them (`first` is the newest).
    case count(Int, first: ZenTaoNotification)
}

public struct PlanDesktopAlerts: Sendable {
    /// Above this many at once, one notification counts them instead.
    public static let maxEach = 3
    public init() {}

    /// - Parameter fresh: newest first, as `FindNewNotifications` returns it.
    public func callAsFunction(_ fresh: [ZenTaoNotification]) -> DesktopAlertPlan {
        guard let first = fresh.first else { return .none }
        return fresh.count > Self.maxEach ? .count(fresh.count, first: first) : .each(fresh)
    }
}
