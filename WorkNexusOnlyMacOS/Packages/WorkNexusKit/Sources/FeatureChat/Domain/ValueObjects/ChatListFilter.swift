import Foundation

/// What the chat list shows, beyond the search text: a tab's slice, only chats with unread messages, and only chats under
/// the picked categories (none picked: any).
/// Ported from: lib/features/chat/domain/value_objects/chat_list_filter.dart
public struct ChatListFilter: Hashable, Sendable {
    public var tab: ChatListTab
    public var unreadOnly: Bool
    public var categories: Set<String>

    public init(tab: ChatListTab = .all, unreadOnly: Bool = false, categories: Set<String> = []) {
        self.tab = tab; self.unreadOnly = unreadOnly; self.categories = categories
    }

    /// Whether the "Categorize" filter narrows the list at all.
    public var isNarrowed: Bool { unreadOnly || !categories.isEmpty }

    public func matches(_ chat: ChatConversation) -> Bool {
        !chat.hidden && !chat.archived && tab.matches(chat) && (!unreadOnly || chat.unreadCount > 0)
            && (categories.isEmpty || categories.contains(chat.category))
    }
}
