import Foundation

/// What a shared web page says about itself (OpenGraph / oEmbed), shown as a card under the message that links to it.
/// Ported from: lib/features/chat/domain/entities/link_preview.dart
public struct LinkPreview: Hashable, Sendable {
    public var url: String
    public var siteName: String?
    public var title: String?
    public var description: String?
    public var imageUrl: String?
    public init(url: String, siteName: String? = nil, title: String? = nil, description: String? = nil, imageUrl: String? = nil) {
        self.url = url; self.siteName = siteName; self.title = title; self.description = description; self.imageUrl = imageUrl
    }
}

/// Everyone who reacted to one message with the same `emoji`.
/// Ported from: lib/features/chat/domain/entities/message_reaction.dart
public struct MessageReaction: Hashable, Sendable {
    public var emoji: String
    /// Who reacted, oldest first.
    public var userIds: [Int]
    /// The reaction message the current user sent, when they did — what removing their reaction retracts.
    public var mine: ChatMessage?
    public init(emoji: String, userIds: [Int], mine: ChatMessage? = nil) { self.emoji = emoji; self.userIds = userIds; self.mine = mine }
    public var count: Int { userIds.count }
}

/// A message's text translated into `targetLang`.
/// Ported from: lib/features/chat/domain/entities/chat_message_translation.dart
public struct ChatMessageTranslation: Hashable, Sendable {
    public var accountId: String
    public var gid: String
    public var targetLang: String
    public var text: String
    /// The model that produced `text`; nil when OpenCode's own default ran.
    public var model: String?
    public var createdAt: Date
    /// Whether it is shown under the message (hiding keeps it stored).
    public var visible: Bool
    public init(accountId: String, gid: String, targetLang: String, text: String, model: String? = nil, createdAt: Date, visible: Bool = true) {
        self.accountId = accountId; self.gid = gid; self.targetLang = targetLang; self.text = text
        self.model = model; self.createdAt = createdAt; self.visible = visible
    }
}

/// The attachments of one chat on disk.
public struct ChatCacheChatUsage: Hashable, Sendable {
    public var accountId: String
    public var chatGid: String
    public var bytes: Int
    /// `bytes` split by attachment kind (previews count with their file).
    public var imageBytes: Int
    public var videoBytes: Int
    public var fileBytes: Int
    public init(accountId: String, chatGid: String, bytes: Int, imageBytes: Int = 0, videoBytes: Int = 0, fileBytes: Int = 0) {
        self.accountId = accountId; self.chatGid = chatGid; self.bytes = bytes
        self.imageBytes = imageBytes; self.videoBytes = videoBytes; self.fileBytes = fileBytes
    }
}

/// Disk space used by downloaded chat attachments.
/// Ported from: lib/features/chat/domain/entities/chat_cache_usage.dart
public struct ChatCacheUsage: Hashable, Sendable {
    public var totalBytes: Int
    public var limitBytes: Int
    /// Per chat, largest first. Files whose message is not stored locally are only in `otherBytes`.
    public var chats: [ChatCacheChatUsage]
    public init(totalBytes: Int, limitBytes: Int, chats: [ChatCacheChatUsage] = []) {
        self.totalBytes = totalBytes; self.limitBytes = limitBytes; self.chats = chats
    }
    public var otherBytes: Int { totalBytes - chats.reduce(0) { $0 + $1.bytes } }
}
