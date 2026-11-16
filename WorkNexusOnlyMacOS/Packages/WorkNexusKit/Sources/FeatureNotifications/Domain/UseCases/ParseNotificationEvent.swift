import Foundation

/// Ported from: lib/features/notifications/domain/usecases/parse_notification_event.dart
/// Who did what, read out of a notification's text.
public struct NotificationEvent: Equatable, Sendable {
    public var actor: String
    public var action: NotificationAction
    public init(actor: String, action: NotificationAction) { self.actor = actor; self.action = action }
}

/// Reads "who did what" out of ZenTao's notification text, so it can be shown in the app's language whatever
/// language ZenTao wrote it in: `JunNg assigned Bug` (English) or `Thanh指派了Bug` (Chinese) for the same action.
/// Nil when the text holds no known action - it is then shown as ZenTao wrote it.
public struct ParseNotificationEvent: Sendable {
    public init() {}

    /// ZenTao's action labels (`module/action/lang/{en,zh-cn}.php`): English words stand between spaces, Chinese
    /// ones follow the name directly. An array, not a dictionary: on equal positions the first entry wins.
    static let labels: [(NotificationAction, [String])] = [
        (.created, ["created", "创建了"]), (.opened, ["opened"]), (.changed, ["changed", "变更了"]),
        (.edited, ["edited", "编辑了"]), (.assigned, ["assigned", "指派了"]), (.closed, ["closed", "关闭了"]),
        (.deleted, ["deleted", "删除了"]), (.commented, ["commented", "评论了"]), (.activated, ["activated", "激活了"]),
        (.resolved, ["resolved", "解决了"]), (.reviewed, ["reviewed", "评审了"]), (.confirmed, ["confirmed", "确认了"]),
        (.started, ["started", "开始了"]), (.restarted, ["restarted", "继续了"]), (.finished, ["finished", "完成了"]),
        (.paused, ["paused", "暂停了"]), (.canceled, ["cancelled", "canceled", "取消了"]),
    ]

    private static func isAscii(_ s: String) -> Bool { s.unicodeScalars.allSatisfy { $0.value >= 97 && $0.value <= 122 } }

    public func callAsFunction(_ text: String) -> NotificationEvent? {
        let summary = text.trimmingCharacters(in: .whitespacesAndNewlines)
        let ns = summary as NSString
        var first: (at: Int, actor: String, action: NotificationAction)?
        for (action, labels) in Self.labels {
            for label in labels {
                let pattern = Self.isAscii(label) ? "\\s\(label)\\s" : NSRegularExpression.escapedPattern(for: label)
                guard let re = try? NSRegularExpression(pattern: pattern),
                      let m = re.firstMatch(in: summary, range: NSRange(location: 0, length: ns.length)) else { continue }
                let actor = ns.substring(to: m.range.location).trimmingCharacters(in: .whitespacesAndNewlines)
                // An action needs someone doing it and something it was done to.
                if actor.isEmpty || m.range.location + m.range.length >= ns.length { continue }
                if first == nil || m.range.location < first!.at { first = (m.range.location, actor, action) }
            }
        }
        return first.map { NotificationEvent(actor: $0.actor, action: $0.action) }
    }
}
