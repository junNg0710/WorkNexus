import CoreDomain
import CoreUI
import Foundation

/// Ported from: lib/features/notifications/presentation/util/notification_event_text.dart (+ l10n keys)
/// UI strings of the notifications feature, resolved through `appString` (keys of `lib/l10n/*.arb`, English
/// fallback so tests and previews read correctly).
enum NotificationStrings {
    static var title: String { appString("notifications", "Notifications") }
    static var all: String { appString("notificationsAll", "All") }
    static var unreadTab: String { appString("notificationsUnreadTab", "Unread") }
    static var markAllRead: String { appString("notificationsMarkAllRead", "Mark all as read") }
    static var markRead: String { appString("notificationsMarkRead", "Mark as read") }
    static var markUnread: String { appString("notificationsMarkUnread", "Mark as unread") }
    static var delete: String { appString("notificationsDelete", "Delete") }
    static var deleteRead: String { appString("notificationsDeleteRead", "Delete read notifications") }
    static var deleteReadConfirm: String {
        appString("notificationsDeleteReadConfirm", "Delete every read notification? This also removes them on ZenTao.")
    }
    static var refresh: String { appString("refresh", "Refresh") }
    static var close: String { appString("close", "Close") }
    static var empty: String { appString("notificationsEmpty", "No notifications") }
    static var emptyUnread: String { appString("notificationsEmptyUnread", "You're all caught up") }
    static var loadFailed: String { appString("notificationsLoadFailed", "Couldn't load notifications") }
    static var refreshFailed: String {
        appString("notificationsRefreshFailed", "Couldn't refresh — showing the last saved notifications")
    }
    static var actionFailed: String { appString("notificationsActionFailed", "Couldn't update the notification on ZenTao") }
    static var openFailed: String { appString("notificationsOpenFailed", "Couldn't open this item") }
    static var today: String { appString("notificationsToday", "Today") }
    static var yesterday: String { appString("notificationsYesterday", "Yesterday") }
    static var undated: String { appString("notificationsUndated", "Undated") }
    static func newCount(_ n: Int) -> String { appFormat("notificationsNewCount", "%1$@ new ZenTao notifications", "\(n)") }

    /// The object kind in the app's language, nil for kinds the app has no word for.
    static func object(_ type: String?) -> String? {
        switch type {
        case "bug": appString("bugTag", "Bug")
        case "task": appString("taskTag", "Task")
        case "story": appString("storyTag", "Story")
        default: nil
        }
    }

    private static let en: [NotificationAction: String] = [
        .created: "created", .opened: "opened", .changed: "changed", .edited: "edited", .assigned: "assigned",
        .closed: "closed", .deleted: "deleted", .commented: "commented on", .activated: "activated",
        .resolved: "resolved", .reviewed: "reviewed", .confirmed: "confirmed", .started: "started",
        .restarted: "restarted", .finished: "finished", .paused: "paused", .canceled: "cancelled",
    ]
    private static let vi: [NotificationAction: String] = [
        .created: "đã tạo", .opened: "đã tạo", .changed: "đã thay đổi", .edited: "đã sửa", .assigned: "đã giao",
        .closed: "đã đóng", .deleted: "đã xoá", .commented: "đã bình luận", .activated: "đã kích hoạt lại",
        .resolved: "đã giải quyết", .reviewed: "đã duyệt", .confirmed: "đã xác nhận", .started: "đã bắt đầu",
        .restarted: "đã tiếp tục", .finished: "đã hoàn thành", .paused: "đã tạm dừng", .canceled: "đã huỷ",
    ]

    private static let zh: [NotificationAction: String] = [
        .created: "创建了", .opened: "创建了", .changed: "变更了", .edited: "编辑了", .assigned: "指派了",
        .closed: "关闭了", .deleted: "删除了", .commented: "评论了", .activated: "激活了",
        .resolved: "解决了", .reviewed: "评审了", .confirmed: "确认了", .started: "开始了",
        .restarted: "继续了", .finished: "完成了", .paused: "暂停了", .canceled: "取消了",
    ]

    /// `notificationAction` of the ARB (an ICU select the xcstrings catalog cannot hold): the verb per language.
    static func action(_ a: NotificationAction, language: String = Bundle.main.preferredLocalizations.first ?? "en") -> String {
        if language.hasPrefix("zh") { return zh[a] ?? "更新了" }
        return (language.hasPrefix("vi") ? vi : en)[a] ?? (language.hasPrefix("vi") ? "đã cập nhật" : "updated")
    }

    /// `n`'s "who did what" in the app's language ("JunNg đã giao Bug"), whatever language ZenTao wrote it in;
    /// ZenTao's own text when it names no known action or object.
    static func eventText(_ n: ZenTaoNotification, language: String = Bundle.main.preferredLocalizations.first ?? "en") -> String {
        guard let event = ParseNotificationEvent()(n.summary), let object = object(n.objectType) else { return n.summary }
        return "\(event.actor) \(action(event.action, language: language)) \(object)"
    }
}
