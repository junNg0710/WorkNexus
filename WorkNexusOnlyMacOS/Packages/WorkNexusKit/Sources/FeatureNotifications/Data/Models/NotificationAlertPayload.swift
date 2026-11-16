import Foundation

/// Ported from: lib/features/notifications/presentation/widgets/notification_alerts.dart (the JSON payload)
/// What a desktop notification carries so a click can find its way back: `{"zn": id, "a": accountId}` for one
/// ZenTao notification, `{"zn": null}` for the one that counts several (a click opens the list).
public struct NotificationAlertPayload: Equatable, Sendable {
    /// The ZenTao notification id; nil for the counting notification.
    public var notificationId: String?
    public var accountId: String?

    public init(notificationId: String?, accountId: String? = nil) {
        self.notificationId = notificationId; self.accountId = accountId
    }

    public var json: String {
        var map: [String: Any] = ["zn": notificationId ?? NSNull()]
        if let accountId { map["a"] = accountId }
        let data = (try? JSONSerialization.data(withJSONObject: map, options: [.sortedKeys])) ?? Data("{}".utf8)
        return String(decoding: data, as: UTF8.self)
    }

    /// Nil when `payload` is not ours (another feature's notification, or not JSON).
    public init?(json payload: String) {
        guard let object = try? JSONSerialization.jsonObject(with: Data(payload.utf8)) as? [String: Any],
              object.keys.contains("zn") else { return nil }
        notificationId = object["zn"] as? String
        accountId = object["a"] as? String
    }
}
