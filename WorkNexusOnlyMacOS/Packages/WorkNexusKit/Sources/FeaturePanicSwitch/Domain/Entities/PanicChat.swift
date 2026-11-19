import Foundation

/// What the panic switch needs to know of chat, in its own words: the chat feature is reached only through
/// `PanicChatGateway`, which the composition root adapts from the chat repository (features never import each other).
/// Ported from: lib/features/chat/domain/entities/chat_conversation.dart (the fields the panic switch reads)
public struct PanicChatRef: Hashable, Sendable, Identifiable {
    public enum Kind: Hashable, Sendable { case group, direct, other }

    public var gid: String
    public var kind: Kind
    /// The group's name; empty for a one-to-one chat (its title is the peer's name).
    public var name: String
    public var peerUserId: Int?
    /// The one-to-one chat with yourself ("My Cloud").
    public var isMyCloud: Bool
    public var hidden: Bool

    public var id: String { gid }

    public init(gid: String, kind: Kind, name: String, peerUserId: Int? = nil, isMyCloud: Bool = false, hidden: Bool = false) {
        self.gid = gid; self.kind = kind; self.name = name; self.peerUserId = peerUserId; self.isMyCloud = isMyCloud
        self.hidden = hidden
    }
}

/// Someone in chat. Ported from: lib/features/chat/domain/entities/chat_user.dart (the fields the panic switch reads)
public struct PanicPerson: Hashable, Sendable, Identifiable {
    public var userId: Int
    public var account: String
    public var realname: String

    public var id: Int { userId }
    /// The real name, or the account when there is none.
    public var displayName: String { realname.isEmpty ? account : realname }

    public init(userId: Int, account: String, realname: String) {
        self.userId = userId; self.account = account; self.realname = realname
    }
}

/// A message that arrived live from someone else, as the panic switch reads it.
/// Ported from: lib/features/chat/domain/entities/chat_message.dart (the fields the panic switch reads)
public struct PanicIncomingMessage: Hashable, Sendable {
    public var accountId: String
    public var chatGid: String
    public var senderId: Int
    public var sentAt: Date
    public var isMine: Bool
    public var deleted: Bool
    /// The file name of an image message; nil for any other content.
    public var imageName: String?

    public init(accountId: String, chatGid: String, senderId: Int, sentAt: Date, isMine: Bool = false, deleted: Bool = false,
                imageName: String?) {
        self.accountId = accountId; self.chatGid = chatGid; self.senderId = senderId; self.sentAt = sentAt
        self.isMine = isMine; self.deleted = deleted; self.imageName = imageName
    }
}

/// A chat the sticker can go to, with the title to show for it.
/// Ported from: lib/features/panic_switch/domain/usecases/list_panic_chats.dart (`PanicChat`)
public struct PanicChat: Hashable, Sendable, Identifiable {
    public var chat: PanicChatRef
    public var title: String

    public var id: String { chat.gid }

    public init(chat: PanicChatRef, title: String) { self.chat = chat; self.title = title }
}
