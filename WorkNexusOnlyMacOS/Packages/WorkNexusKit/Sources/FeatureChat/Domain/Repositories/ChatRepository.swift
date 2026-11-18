import CoreDomain
import Foundation

/// Settings the chat runtime reads live (the host app pushes them from `AppSettings`).
/// Ported from: lib/features/chat/domain/repositories/chat_runtime_settings.dart
public protocol ChatRuntimeSettings: Sendable {
    func setCacheLimit(bytes: Int)
    func setVideoAutoDownloadLimit(bytes: Int)
    func setReactions(_ on: Bool)
}

/// Everything presentation and use cases need from chat; implemented by `XxdChatRepository` (Data). Local-first: reads
/// come from the database, `connect` and the senders write into it.
/// Ported from: lib/features/chat/domain/repositories/chat_repository.dart
public protocol ChatRepository: ChatRuntimeSettings {
    // MARK: connection
    func watchStatus(accountId: String) -> AsyncStream<ChatConnectionStatus>
    func connect(accountId: String) async -> Outcome<Void>
    func disconnect(accountId: String) async
    /// Trusts the certificate with `fingerprint` for this account (TOFU) and reconnects.
    func trustCertificate(accountId: String, fingerprint: String) async -> Outcome<Void>
    /// Every message that arrives live (not history), for notifications.
    func watchIncoming() -> AsyncStream<ChatMessage>

    // MARK: reads
    func watchConversations(accountId: String) -> AsyncStream<[ChatConversation]>
    /// The newest `limit` messages of a chat, oldest first. `reactions: false` leaves reaction rows out.
    func watchMessages(accountId: String, chatGid: String, limit: Int, reactions: Bool) -> AsyncStream<[ChatMessage]>
    func watchUsers(accountId: String) -> AsyncStream<[ChatUser]>
    func watchMessagesInRange(accountId: String, chatGid: String, fromIndex: Int, toIndex: Int, reactions: Bool) -> AsyncStream<[ChatMessage]>
    func watchMessage(accountId: String, chatGid: String, serverId: Int) -> AsyncStream<ChatMessage?>
    func watchReplies(accountId: String, chatGid: String) -> AsyncStream<[ChatMessage]>
    func watchReactions(accountId: String, chatGid: String) -> AsyncStream<[Int: [MessageReaction]]>
    func watchAttachments(accountId: String, chatGid: String) -> AsyncStream<[ChatMessage]>
    func watchSelfUserId(accountId: String) -> AsyncStream<Int?>
    func watchTyping(accountId: String) -> AsyncStream<ChatTypingSignal>

    // MARK: paging / history
    func refreshMessages(accountId: String, chatGid: String) async -> Outcome<Void>
    /// Loads a page older than `beforeServerId` (or the oldest stored) into the timeline; returns how many messages arrived.
    func loadOlderMessages(accountId: String, chatGid: String, beforeServerId: Int?, inWindow: Bool, pageSize: Int?) async -> Outcome<Int>
    /// Loads the messages around `serverId` as a detached window; returns its (from, to) index range, nil when unknown.
    func loadMessagesAround(accountId: String, chatGid: String, serverId: Int) async -> Outcome<(from: Int, to: Int)?>
    func loadNewerMessages(accountId: String, chatGid: String, afterServerId: Int) async -> Outcome<Int>
    func joinWindowToTimeline(accountId: String, chatGid: String, fromIndex: Int, toIndex: Int) async -> Outcome<Int?>
    func countAdjacentMessages(accountId: String, chatGid: String, index: Int, older: Bool, limit: Int) async -> Outcome<Int>
    func countOlderMessages(accountId: String, chatGid: String, before: Date) async -> Outcome<Int>
    func timelineExtent(accountId: String, chatGid: String) async -> Outcome<ChatTimelineExtent>
    func messageCount(accountId: String, chatGid: String) async -> Outcome<Int>
    func searchMessages(accountId: String, chatGid: String?, query: String, since: Date?, limit: Int?) async -> Outcome<[ChatMessage]>
    func fetchMessages(accountId: String, chatGid: String, serverIds: [Int]) async -> Outcome<Void>

    // MARK: sending
    func sendText(accountId: String, chatGid: String, text: String, replyToId: Int?, markdown: Bool) async -> Outcome<Void>
    func sendEmoji(accountId: String, chatGid: String, code: String, replyToId: Int?) async -> Outcome<Void>
    func sendCode(accountId: String, chatGid: String, code: String, language: String, name: String?, replyToId: Int?) async -> Outcome<Void>
    func sendFile(accountId: String, chatGid: String, name: String, bytes: Data, mimeType: String?, replyToId: Int?) async -> Outcome<Void>
    func watchUploadProgress(messageGid: String) -> AsyncStream<Double>
    func pendingUploadBytes(messageGid: String) -> Data?
    func cancelUpload(accountId: String, messageGid: String) async -> Outcome<Void>
    func retrySend(accountId: String, messageGid: String) async -> Outcome<Void>
    func retract(accountId: String, messageGid: String) async -> Outcome<Void>
    func forwardMessage(accountId: String, messageGid: String, toChatGid: String) async -> Outcome<Void>
    func sendTyping(accountId: String, chatGid: String, typing: Bool) async -> Outcome<Void>

    // MARK: attachments
    /// Local path of the attachment, downloading it first when needed.
    func attachmentFile(accountId: String, content: MessageContent) async -> Outcome<String>
    func loadAttachment(accountId: String, content: MessageContent, thumbnail: Bool) async -> Outcome<Data>
    /// How to play a video: its cached file, or — while it is not cached — a source of its bytes in ranges, playable before the
    /// download completes (and kept in the file cache once seen whole).
    func videoPlayback(accountId: String, content: MessageContent) async -> Outcome<ChatVideoPlayback>
    func saveAttachmentCopy(accountId: String, content: MessageContent, targetPath: String) async -> Outcome<Void>
    func savedAttachmentCopy(accountId: String, content: MessageContent) async -> String?
    func cancelDownload(accountId: String, content: MessageContent)
    func watchDownloadProgress(accountId: String, content: MessageContent) -> AsyncStream<Double>
    func isAttachmentCached(accountId: String, content: MessageContent) async -> Bool
    func videoDuration(accountId: String, video: MessageContent) async -> Outcome<TimeInterval>
    func videoThumbnail(accountId: String, video: MessageContent) async -> Outcome<Data>
    func pendingVideoThumbnail(messageGid: String, fileName: String) async -> Outcome<Data>
    func cacheUsage() async -> Outcome<ChatCacheUsage>
    func clearCache(accountId: String?, chatGid: String?) async -> Outcome<Void>

    // MARK: people / groups
    func roleNames(accountId: String) async -> Outcome<[String: String]>
    func memberCount(accountId: String, chatGid: String) async -> Outcome<Int>
    func members(accountId: String, chatGid: String) async -> Outcome<[Int]>
    func openDirectChat(accountId: String, userId: Int) async -> Outcome<String>
    func refreshUsers(accountId: String) async -> Outcome<Void>
    /// Creates a group named `name` with `memberIds` (the signed-in user is added), `isPublic` to let anyone find and join
    /// it; returns its gid.
    func createGroupChat(accountId: String, name: String, memberIds: [Int], isPublic: Bool) async -> Outcome<String>
    /// Files chats `chatGids` under `category` ("" for none).
    func setChatCategory(accountId: String, chatGids: [String], category: String) async -> Outcome<Void>
    /// Sets a group's settings: public, admin-only invites and who may post (`committers`, as xxd stores it).
    func setGroupSettings(accountId: String, chatGid: String, isPublic: Bool, adminInvite: Bool, committers: String) async -> Outcome<Void>
    /// Makes `userIds` admins of a group (`admin`) or plain members again.
    func setGroupAdmins(accountId: String, chatGid: String, userIds: [Int], admin: Bool) async -> Outcome<Void>
    /// Hands a group over to `userId`, its new owner.
    func transferGroupOwnership(accountId: String, chatGid: String, userId: Int) async -> Outcome<Void>
    /// Renames a group for every member.
    func renameGroupChat(accountId: String, chatGid: String, name: String) async -> Outcome<Void>
    /// Dismisses (disbands) a group for every member; only its owner may.
    func dismissGroupChat(accountId: String, chatGid: String) async -> Outcome<Void>
    /// Leaves a group (its owner dismisses it instead).
    func leaveGroupChat(accountId: String, chatGid: String) async -> Outcome<Void>
    func addGroupMembers(accountId: String, chatGid: String, userIds: [Int]) async -> Outcome<Void>
    /// Removes `userIds` from a group; only its owner may.
    func removeGroupMembers(accountId: String, chatGid: String, userIds: [Int]) async -> Outcome<Void>
    func setGroupAvatar(accountId: String, chatGid: String, text: String?, color: String?, image: Data?) async -> Outcome<Void>
    func setMyAvatar(accountId: String, image: Data, crop: ChatAvatarCrop?) async -> Outcome<Void>
    func setMyPresence(accountId: String, presence: ChatPresence) async -> Outcome<Void>
    func setChatStarred(accountId: String, chatGid: String, starred: Bool) async -> Outcome<Void>
    func setChatMuted(accountId: String, chatGid: String, muted: Bool) async -> Outcome<Void>
    func setMessagePinned(accountId: String, chatGid: String, serverId: Int, pinned: Bool) async -> Outcome<Void>
    func markRead(accountId: String, chatGid: String) async -> Outcome<Void>
}

public extension ChatRepository {
    func watchMessages(accountId: String, chatGid: String) -> AsyncStream<[ChatMessage]> {
        watchMessages(accountId: accountId, chatGid: chatGid, limit: 50, reactions: true)
    }
}
