import CoreDomain
import Foundation

/// Ported from: lib/features/notifications/domain/usecases/find_new_notifications.dart
/// What `FindNewNotifications` reports: the unread notifications that were not there before (`fresh`, newest
/// first) and every notification there now (`seen`), to compare the next list with.
public struct NewNotifications: Equatable, Sendable {
    public var fresh: [ZenTaoNotification]
    public var seen: Set<String>
}

/// The unread notifications a refresh brought in, to raise on the desktop. The first list is the backlog, not
/// news: it only becomes what has been seen. So is the first list of an account none of whose notifications has
/// been seen yet (the first list comes from the local database, which a fresh install, a cleared cache or an
/// account just added does not fill until the first fetch). A notification read elsewhere before it was seen
/// here is not raised.
public struct FindNewNotifications: Sendable {
    public init() {}

    /// One notification's key across accounts.
    public static func keyOf(_ n: ZenTaoNotification) -> String { "\(n.accountId):\(n.id)" }

    /// - Parameters: `seen` is nil before the first list; `current` the list now.
    public func callAsFunction(seen before: Set<String>?, current: [ZenTaoNotification]) -> NewNotifications {
        let seenNow = Set(current.map(Self.keyOf))
        guard let before else { return NewNotifications(fresh: [], seen: seenNow) }
        let known = Set(before.map(Self.accountOf))
        let fresh = current
            .filter { !$0.read && !before.contains(Self.keyOf($0)) && known.contains($0.accountId) }
            .sorted { Self.time($0) > Self.time($1) }
        // Kept once seen: a notification that drops off the list and comes back is not news either.
        return NewNotifications(fresh: fresh, seen: before.union(seenNow))
    }

    /// The account of a `keyOf` key; notification ids hold no colon.
    static func accountOf(_ key: String) -> String {
        guard let i = key.lastIndex(of: ":") else { return key }
        return String(key[..<i])
    }

    private static func time(_ n: ZenTaoNotification) -> Date { n.createdAt ?? Date(timeIntervalSince1970: 0) }
}
