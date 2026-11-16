import CoreDomain
import Foundation

/// Ported from: lib/features/chat/domain/usecases/send_text_message.dart
public struct SendTextMessage: Sendable {
    private let repository: ChatRepository
    public init(_ repository: ChatRepository) { self.repository = repository }

    /// Trims, tidies Markdown emphasis and encodes 4-byte emoji for xxd (see `EncodeEmoji`) before sending.
    public func callAsFunction(accountId: String, chatGid: String, text: String, replyToId: Int? = nil, markdown: Bool = false) async -> Outcome<Void> {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return .failure(.unexpected("Cannot send an empty message")) }
        return await repository.sendText(accountId: accountId, chatGid: chatGid,
                                         text: EncodeEmoji()(markdown ? TidyMarkdownEmphasis()(trimmed) : trimmed),
                                         replyToId: replyToId, markdown: markdown)
    }
}

/// Ported from: lib/features/chat/domain/usecases/send_code_message.dart
public struct SendCodeMessage: Sendable {
    public static let maxLength = 20000
    public static let plainText = "text"
    public static let languages = [plainText, "bash", "c", "cpp", "csharp", "css", "dart", "go", "html", "java", "javascript", "json",
                                   "kotlin", "markdown", "php", "python", "ruby", "rust", "sql", "swift", "typescript", "xml", "yaml"]
    private let repository: ChatRepository
    public init(_ repository: ChatRepository) { self.repository = repository }

    public func callAsFunction(accountId: String, chatGid: String, code: String, language: String = plainText, name: String? = nil, replyToId: Int? = nil) async -> Outcome<Void> {
        if code.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { return .failure(.validation("Cannot send empty code")) }
        if code.count > Self.maxLength { return .failure(.validation("Code is too long")) }
        let n = name?.trimmingCharacters(in: .whitespacesAndNewlines)
        return await repository.sendCode(accountId: accountId, chatGid: chatGid, code: code, language: language,
                                         name: (n?.isEmpty ?? true) ? nil : n, replyToId: replyToId)
    }
}

/// Ported from: lib/features/chat/domain/usecases/send_chat_file.dart
public struct SendChatFile: Sendable {
    private let repository: ChatRepository
    public init(_ repository: ChatRepository) { self.repository = repository }

    public func callAsFunction(accountId: String, chatGid: String, name: String, bytes: Data, mimeType: String? = nil, replyToId: Int? = nil) async -> Outcome<Void> {
        guard !bytes.isEmpty else { return .failure(.unexpected("Cannot send an empty file")) }
        let n = name.trimmingCharacters(in: .whitespacesAndNewlines)
        return await repository.sendFile(accountId: accountId, chatGid: chatGid, name: n.isEmpty ? "file" : n, bytes: bytes, mimeType: mimeType, replyToId: replyToId)
    }
}

/// Ported from: lib/features/chat/domain/usecases/send_sticker.dart
public struct SendSticker: Sendable {
    private let chats: ChatRepository, stickers: StickerRepository
    public init(_ chats: ChatRepository, _ stickers: StickerRepository) { self.chats = chats; self.stickers = stickers }

    public func callAsFunction(accountId: String, chatGid: String, sticker: ChatSticker, replyToId: Int? = nil) async -> Outcome<Void> {
        switch await stickers.bytes(sticker) {
        case .success(let bytes): return await chats.sendFile(accountId: accountId, chatGid: chatGid, name: sticker.name, bytes: bytes, mimeType: nil, replyToId: replyToId)
        case .failure(let f): return .failure(f)
        }
    }
}

public struct SendLargeEmoji: Sendable {
    private let chats: ChatRepository
    public init(_ chats: ChatRepository) { self.chats = chats }
    public func callAsFunction(accountId: String, chatGid: String, emoji: String) async -> Outcome<Void> {
        let code = EncodeEmoji()(emoji.trimmingCharacters(in: .whitespacesAndNewlines))
        guard !code.isEmpty else { return .failure(.unexpected("No emoji to send")) }
        return await chats.sendEmoji(accountId: accountId, chatGid: chatGid, code: code, replyToId: nil)
    }
}

/// Ported from: lib/features/chat/domain/usecases/send_typing_status.dart
public struct SendTypingStatus: Sendable {
    private let repository: ChatRepository
    public init(_ repository: ChatRepository) { self.repository = repository }

    public func callAsFunction(chat: ChatConversation, typing: Bool) async -> Outcome<Void> {
        let supported: Bool
        switch chat.type { case .one2one: supported = !chat.isMyCloud; case .group: supported = true; case .bot, .system, .other: supported = false }
        guard supported else { return .success(()) }
        return await repository.sendTyping(accountId: chat.accountId, chatGid: chat.gid, typing: typing)
    }
}

/// Ported from: lib/features/chat/domain/usecases/forward_chat_message.dart
public struct ForwardChatMessage: Sendable {
    private let repository: ChatRepository
    public init(_ repository: ChatRepository) { self.repository = repository }

    public func canForward(_ m: ChatMessage) -> Bool {
        guard !m.deleted, !m.isNotice, m.serverId != nil, m.sendState == .sent else { return false }
        switch m.content { case .notification, .unsupported: return false; default: return true }
    }

    /// Forwards to each chat; every chat is tried, the first failure is reported.
    public func callAsFunction(_ m: ChatMessage, toChatGids: [String]) async -> Outcome<Void> {
        guard canForward(m) else { return .failure(.unexpected("This message cannot be forwarded")) }
        guard !toChatGids.isEmpty else { return .failure(.unexpected("Pick a chat to forward to")) }
        var first: CoreDomain.Failure?
        for gid in toChatGids {
            if case .failure(let f) = await repository.forwardMessage(accountId: m.accountId, messageGid: m.gid, toChatGid: gid) { first = first ?? f }
        }
        return first.map { .failure($0) } ?? .success(())
    }
}

/// Ported from: lib/features/chat/domain/usecases/create_group_chat.dart
public struct CreateGroupChat: Sendable {
    private let repository: ChatRepository
    public init(_ repository: ChatRepository) { self.repository = repository }

    public func callAsFunction(accountId: String, name: String, memberIds: [Int]) async -> Outcome<String> {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return .failure(.unexpected("A group needs a name")) }
        var seen = Set<Int>(), unique: [Int] = []
        for id in memberIds where seen.insert(id).inserted { unique.append(id) }
        guard unique.count >= 2 else { return .failure(.unexpected("A group needs at least two people")) }
        return await repository.createGroupChat(accountId: accountId, name: trimmed, memberIds: unique)
    }
}
