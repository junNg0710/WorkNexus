import Foundation

public enum ChatType: String, Hashable, Sendable { case group, one2one, bot, system, other }

/// A chat the account belongs to. One-to-one chats have no `name`; their title comes from `peerUserId` (see `ResolveChatTitle`).
/// Ported from: lib/features/chat/domain/entities/chat_conversation.dart
public struct ChatConversation: Hashable, Sendable, Identifiable {
    public var accountId: String
    public var gid: String
    public var type: ChatType
    public var name: String
    public var unreadCount: Int
    public var lastActiveAt: Date?
    public var lastMessage: ChatMessage?
    public var peerUserId: Int?
    /// The one-to-one chat with yourself ("My Cloud").
    public var isMyCloud: Bool
    public var hidden: Bool
    public var archived: Bool
    /// Pinned to the top of the chat list.
    public var starred: Bool
    /// Notifications silenced (kept on this device only).
    public var muted: Bool
    /// Server ids of pinned messages, oldest pin first.
    public var pinnedMessageIds: [Int]
    /// User ids of the group's admins (they and the owner may pin).
    public var adminIds: [Int]
    /// Who may send, as xxd stores it; see `CanSendToChat`.
    public var committers: String
    public var ownerAccount: String?
    /// The group's avatar as stored (xxd JSON); see `ChatGroupAvatar`.
    public var avatarJson: String?
    public var createdAt: Date?

    public var id: String { gid }

    public init(accountId: String, gid: String, type: ChatType, name: String, unreadCount: Int = 0, lastActiveAt: Date? = nil,
                lastMessage: ChatMessage? = nil, peerUserId: Int? = nil, isMyCloud: Bool = false, hidden: Bool = false,
                archived: Bool = false, starred: Bool = false, muted: Bool = false, pinnedMessageIds: [Int] = [],
                adminIds: [Int] = [], committers: String = "", ownerAccount: String? = nil, avatarJson: String? = nil,
                createdAt: Date? = nil) {
        self.accountId = accountId; self.gid = gid; self.type = type; self.name = name; self.unreadCount = unreadCount
        self.lastActiveAt = lastActiveAt; self.lastMessage = lastMessage; self.peerUserId = peerUserId
        self.isMyCloud = isMyCloud; self.hidden = hidden; self.archived = archived; self.starred = starred
        self.muted = muted; self.pinnedMessageIds = pinnedMessageIds; self.adminIds = adminIds
        self.committers = committers; self.ownerAccount = ownerAccount; self.avatarJson = avatarJson; self.createdAt = createdAt
    }
}
