import CoreDomain
import Foundation

/// Ported from: lib/features/notifications/domain/usecases/group_notifications_by_day.dart
/// One calendar day of notifications; `day` is nil for undated ones.
public struct NotificationDay: Equatable, Sendable, Identifiable {
    public var day: Date?
    public var items: [ZenTaoNotification]
    public var id: String { day.map { "\($0.timeIntervalSince1970)" } ?? "undated" }
}

/// Groups notifications by local calendar day, newest day (and newest item) first, like ZenTao's bell menu. With
/// `unreadOnly`, read ones are left out.
public struct GroupNotificationsByDay: Sendable {
    public init() {}

    public func callAsFunction(_ notifications: [ZenTaoNotification], unreadOnly: Bool = false,
                               calendar: Calendar = .current) -> [NotificationDay] {
        let epoch = Date(timeIntervalSince1970: -62_135_596_800)   // Dart's DateTime(0)
        // Stable: equal times keep their input order (Dart's List.sort is not guaranteed stable, but ties are rare).
        let sorted = notifications.enumerated().filter { !unreadOnly || !$0.element.read }
            .sorted { a, b in
                let ta = a.element.createdAt ?? epoch, tb = b.element.createdAt ?? epoch
                return ta != tb ? ta > tb : a.offset < b.offset
            }.map(\.element)
        var days: [NotificationDay] = []
        for n in sorted {
            let day = n.createdAt.map { calendar.startOfDay(for: $0) }
            if let last = days.last, last.day == day { days[days.count - 1].items.append(n) }
            else { days.append(NotificationDay(day: day, items: [n])) }
        }
        return days
    }
}
