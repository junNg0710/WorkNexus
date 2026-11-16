/// Ported from: lib/features/notifications/domain/value_objects/notification_action.dart
/// What a ZenTao notification says was done to its object.
public enum NotificationAction: String, CaseIterable, Sendable, Hashable {
    case created, opened, changed, edited, assigned, closed, deleted, commented, activated, resolved
    case reviewed, confirmed, started, restarted, finished, paused, canceled
}
