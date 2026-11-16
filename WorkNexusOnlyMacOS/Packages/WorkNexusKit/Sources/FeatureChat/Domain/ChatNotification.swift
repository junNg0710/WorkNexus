import Foundation

/// A new message worth telling the user about (decided by `ShouldNotifyChatMessage`); the host app shows it as a system
/// notification and routes a click back with `ChatFeature.open(accountId:chatGid:)`.
/// Ported from: lib/features/chat/presentation/widgets/chat_notification_listener.dart
public struct ChatNotification: Hashable, Sendable {
    public var accountId: String
    public var chatGid: String
    public var messageGid: String
    /// Chat title (the sender's name for a direct chat).
    public var title: String
    /// Sender name for groups, nil in direct chats.
    public var subtitle: String?
    /// One-line preview of the message ("Photo", "File: spec.pdf", the text…).
    public var body: String
    public init(accountId: String, chatGid: String, messageGid: String, title: String, subtitle: String? = nil, body: String) {
        self.accountId = accountId; self.chatGid = chatGid; self.messageGid = messageGid
        self.title = title; self.subtitle = subtitle; self.body = body
    }
}

/// Implemented by the host app (UserNotifications / dock badge). Chat never talks to the OS directly.
public protocol ChatNotificationSink: Sendable {
    func deliver(_ notification: ChatNotification)
    /// The user read the chat on another device or here: drop its delivered notifications.
    func clear(accountId: String, chatGid: String)
    /// Whether the app window is key and frontmost (suppresses notifications for the chat being looked at).
    var appIsFocused: Bool { get }
}

/// Total unread across an account's chats for a badge (`CountBadgeUnread`: hidden, archived and muted chats do not count).
public final class ChatUnreadCounter: @unchecked Sendable {
    private let repository: ChatRepository
    public init(repository: ChatRepository) { self.repository = repository }

    /// Emits the badge count now and whenever it changes.
    public func counts(accountId: String) -> AsyncStream<Int> {
        let source = repository.watchConversations(accountId: accountId)
        return AsyncStream { cont in
            let task = Task {
                var last: Int?
                for await chats in source {
                    let n = CountBadgeUnread()(chats)
                    if n != last { last = n; cont.yield(n) }
                }
                cont.finish()
            }
            cont.onTermination = { _ in task.cancel() }
        }
    }
}
