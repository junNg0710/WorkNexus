import Foundation

public enum SendState: String, Hashable, Sendable { case sent, pending, failed }

/// One message in a conversation. `gid` is the client-generated id; `serverId` is assigned by xxd once stored (nil while
/// pending). A reply points at its parent with `replyToId` (xxd's `data.replyTo`).
/// Ported from: lib/features/chat/domain/entities/chat_message.dart
public struct ChatMessage: Hashable, Sendable, Identifiable {
    public var accountId: String
    public var gid: String
    public var chatGid: String
    public var senderId: Int
    public var sentAt: Date
    public var content: MessageContent
    public var isMine: Bool
    public var sendState: SendState
    public var serverId: Int?
    /// Its place in the chat (1, 2, 3, …), from xxd; nil while pending.
    public var index: Int?
    /// Server id of the message this one replies to.
    public var replyToId: Int?
    public var deleted: Bool
    /// A notice the server posted about the chat (invites, renames), shown centered, not as a message from `senderId`.
    public var isNotice: Bool

    public var id: String { gid }

    public init(accountId: String, gid: String, chatGid: String, senderId: Int, sentAt: Date, content: MessageContent,
                isMine: Bool, sendState: SendState = .sent, serverId: Int? = nil, index: Int? = nil, replyToId: Int? = nil,
                deleted: Bool = false, isNotice: Bool = false) {
        self.accountId = accountId; self.gid = gid; self.chatGid = chatGid; self.senderId = senderId; self.sentAt = sentAt
        self.content = content; self.isMine = isMine; self.sendState = sendState; self.serverId = serverId
        self.index = index; self.replyToId = replyToId; self.deleted = deleted; self.isNotice = isNotice
    }

    /// A reaction is a reply whose whole content is one emoji: xxd has no reactions, so this app reads such a reply as
    /// "reacted with it" to the message it answers.
    public var isReaction: Bool { replyToId != nil && content.asEmoji != nil }
    /// The emoji of a reaction, else nil.
    public var reactionEmoji: String? { replyToId != nil ? content.asEmoji : nil }
}
