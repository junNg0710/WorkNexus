/// Not in the Flutter app (its title bar had no search).
import CoreDomain
import Foundation

/// One thing the title bar's search found in chat: a conversation by its name, or a stored message.
public struct ChatSearchHit: Identifiable, Hashable, Sendable {
    public enum Kind: Hashable, Sendable { case chat, message }
    public var id: String
    public var kind: Kind
    /// The conversation's name.
    public var title: String
    /// What the message says (with its sender), or the conversation's last message.
    public var subtitle: String
    public var date: Date?
    public var chatGid: String
    /// The message to jump to; nil for a conversation.
    public var serverId: Int?
}

/// The search of the title bar on the Chat page: conversations whose name matches, then the stored messages of every chat
/// that do (newest first). Messages are searched on this Mac only, as the in-chat search is.
@MainActor
public struct ChatGlobalSearch {
    public static let chatLimit = 6
    public static let messageLimit = 30
    private let repository: ChatRepository
    private let accountId: String

    public init(repository: ChatRepository, accountId: String) { self.repository = repository; self.accountId = accountId }

    public func search(_ query: String) async -> [ChatSearchHit] {
        let fold = FoldSearchText()
        let q = fold(query.trimmingCharacters(in: .whitespacesAndNewlines))
        guard !q.isEmpty else { return [] }
        var chatsIt = repository.watchConversations(accountId: accountId).makeAsyncIterator()
        var usersIt = repository.watchUsers(accountId: accountId).makeAsyncIterator()
        let chats = await chatsIt.next() ?? []
        let users = Dictionary((await usersIt.next() ?? []).map { ($0.userId, $0) }, uniquingKeysWith: { a, _ in a })
        let titles = Dictionary(chats.map { ($0.gid, ChatShellLabels.title($0, users)) }, uniquingKeysWith: { a, _ in a })
        let named = chats.filter { !$0.archived && fold(titles[$0.gid] ?? "").contains(q) }.prefix(Self.chatLimit).map { c in
            ChatSearchHit(id: "chat:\(c.gid)", kind: .chat, title: titles[c.gid] ?? c.gid,
                          subtitle: c.lastMessage.map { ChatShellLabels.preview($0) } ?? "", date: c.lastMessage?.sentAt,
                          chatGid: c.gid, serverId: nil)
        }
        let found = (await repository.searchMessages(accountId: accountId, chatGid: nil, query: query, since: nil,
                                                     limit: Self.messageLimit)).value ?? []
        let messages = found.compactMap { m -> ChatSearchHit? in
            guard let serverId = m.serverId else { return nil }
            let who = ChatTextLabels.userName(users, m.senderId)
            return ChatSearchHit(id: "msg:\(m.gid)", kind: .message, title: titles[m.chatGid] ?? m.chatGid,
                                 subtitle: "\(who): \(ChatShellLabels.preview(m))", date: m.sentAt, chatGid: m.chatGid, serverId: serverId)
        }
        return Array(named) + messages
    }
}
