import CoreDomain
import Foundation

/// A category the user files chats under, with the unread messages of its listed chats.
public struct ChatCategory: Hashable, Sendable {
    public var name: String
    public var unread: Int
    public init(name: String, unread: Int) { self.name = name; self.unread = unread }
}

/// The categories the user files chats under, A–Z (ignoring case), with the unread messages of the listed chats (not
/// hidden or archived) in each.
/// Ported from: lib/features/chat/domain/usecases/list_chat_categories.dart
public struct ListChatCategories: Sendable {
    public init() {}
    public func callAsFunction(_ chats: [ChatConversation]) -> [ChatCategory] {
        var unread: [String: Int] = [:]
        for c in chats where !c.category.isEmpty && !c.hidden && !c.archived { unread[c.category, default: 0] += c.unreadCount }
        return unread.keys.sorted { $0.lowercased() < $1.lowercased() }.map { ChatCategory(name: $0, unread: unread[$0]!) }
    }
}

/// Files a chat under a category of the user's own (synced by the server to their other clients), or under none with an
/// empty `category`.
/// Ported from: lib/features/chat/domain/usecases/set_chat_category.dart
public struct SetChatCategory: Sendable {
    private let repository: ChatRepository
    public init(_ repository: ChatRepository) { self.repository = repository }

    public func callAsFunction(_ chat: ChatConversation, _ category: String) async -> Outcome<Void> {
        let name = category.trimmingCharacters(in: .whitespacesAndNewlines)
        if name == chat.category { return .success(()) }
        return await repository.setChatCategory(accountId: chat.accountId, chatGids: [chat.gid], category: name)
    }
}

/// Renames a category by refiling every chat in it, as xxd keeps a category only as a name on each chat. An empty `to`
/// deletes the category: its chats are left uncategorised.
/// Ported from: lib/features/chat/domain/usecases/rename_chat_category.dart
public struct RenameChatCategory: Sendable {
    private let repository: ChatRepository
    public init(_ repository: ChatRepository) { self.repository = repository }

    public func callAsFunction(accountId: String, chats: [ChatConversation], from: String, to: String) async -> Outcome<Void> {
        let name = to.trimmingCharacters(in: .whitespacesAndNewlines)
        if name == from { return .success(()) }
        let gids = chats.filter { $0.category == from }.map(\.gid)
        guard !gids.isEmpty else { return .failure(.unexpected("No chat is in this category")) }
        return await repository.setChatCategory(accountId: accountId, chatGids: gids, category: name)
    }
}
