/// Ported from: lib/features/chat/presentation/widgets/message_list_item.dart (chatListItems, _sameRun)
import Foundation

/// A row of the message list, oldest first (the Flutter list is newest first and reversed).
enum ChatListItem: Hashable, Identifiable {
    case message(ChatMessage)
    /// A day divider above the first message of a day.
    case day(Date)
    /// A time marker after a pause (WeChat ~5 min).
    case marker(Date)
    /// The "someone is typing" bubble under the newest message.
    case typing

    var id: String {
        switch self {
        case .message(let m): m.gid
        case .day(let d): "#day-\(d.timeIntervalSince1970)"
        case .marker(let d): "#time-\(d.timeIntervalSince1970)"
        case .typing: "#typing"
        }
    }

    var message: ChatMessage? { if case .message(let m) = self { m } else { nil } }
}

/// One list row with the place of its message in a run of one sender's messages.
struct ChatListRow: Hashable, Identifiable {
    var item: ChatListItem
    var firstOfRun = true
    var lastOfRun = true
    var id: String { item.id }
}

enum ChatListRows {
    /// How far apart two messages of one sender may be to share a run.
    static let runWindow: TimeInterval = 5 * 60

    /// The rows for `messages` (oldest first): a day divider before the first message of each day and, for styles
    /// without per-message times, a time marker after a pause of `markerGap`.
    static func items(_ messages: [ChatMessage], markerGap: TimeInterval?, calendar: Calendar = .current) -> [ChatListItem] {
        var items: [ChatListItem] = []
        items.reserveCapacity(messages.count + 4)
        for (i, message) in messages.enumerated() {
            let previous = i > 0 ? messages[i - 1] : nil
            if let previous, calendar.isDate(previous.sentAt, inSameDayAs: message.sentAt) {
                if let gap = markerGap, message.sentAt.timeIntervalSince(previous.sentAt) >= gap { items.append(.marker(message.sentAt)) }
            } else {
                items.append(.day(calendar.startOfDay(for: message.sentAt)))
            }
            items.append(.message(message))
        }
        return items
    }

    /// Consecutive messages from one sender within a few minutes form a run: one name, one avatar, one timestamp,
    /// tighter spacing. A server notice stands apart, so the sender's next message still shows who sent it.
    static func sameRun(_ other: ChatListItem?, _ message: ChatMessage) -> Bool {
        guard let o = other?.message, !o.isNotice, !message.isNotice, o.senderId == message.senderId else { return false }
        return abs(o.sentAt.timeIntervalSince(message.sentAt)) <= runWindow
    }

    /// `items` with each message's run position; `typing` appends the typing row.
    static func rows(_ messages: [ChatMessage], markerGap: TimeInterval?, typing: Bool, calendar: Calendar = .current) -> [ChatListRow] {
        let items = items(messages, markerGap: markerGap, calendar: calendar)
        var rows: [ChatListRow] = []
        rows.reserveCapacity(items.count + 1)
        for (i, item) in items.enumerated() {
            guard let m = item.message else { rows.append(ChatListRow(item: item)); continue }
            let older = i > 0 ? items[i - 1] : nil
            let newer = i + 1 < items.count ? items[i + 1] : nil
            rows.append(ChatListRow(item: item, firstOfRun: !sameRun(older, m), lastOfRun: !sameRun(newer, m)))
        }
        if typing { rows.append(ChatListRow(item: .typing)) }
        return rows
    }
}
