import CoreDomain
import Foundation
@testable import FeatureChat

/// Every `ChatRepository` method answers "unstubbed"; tests subclass and override what they exercise.
class StubChatRepository: ChatRepository, @unchecked Sendable {
    func unstubbed<T>() -> Outcome<T> { .failure(.unexpected("unstubbed")) }
    func empty<T>() -> AsyncStream<T> { AsyncStream { $0.finish() } }

    func setCacheLimit(bytes: Int) {}
    func setVideoAutoDownloadLimit(bytes: Int) {}
    func setReactions(_ on: Bool) {}
    func watchStatus(accountId: String) -> AsyncStream<ChatConnectionStatus> { empty() }
    func connect(accountId: String) async -> Outcome<Void> { unstubbed() }
    func disconnect(accountId: String) async {}
    func trustCertificate(accountId: String, fingerprint: String) async -> Outcome<Void> { unstubbed() }
    func watchIncoming() -> AsyncStream<ChatMessage> { empty() }
    func watchConversations(accountId: String) -> AsyncStream<[ChatConversation]> { empty() }
    func watchMessages(accountId: String, chatGid: String, limit: Int, reactions: Bool) -> AsyncStream<[ChatMessage]> { empty() }
    func watchUsers(accountId: String) -> AsyncStream<[ChatUser]> { empty() }
    func watchMessagesInRange(accountId: String, chatGid: String, fromIndex: Int, toIndex: Int, reactions: Bool) -> AsyncStream<[ChatMessage]> { empty() }
    func watchMessage(accountId: String, chatGid: String, serverId: Int) -> AsyncStream<ChatMessage?> { empty() }
    func watchReplies(accountId: String, chatGid: String) -> AsyncStream<[ChatMessage]> { empty() }
    func watchReactions(accountId: String, chatGid: String) -> AsyncStream<[Int: [MessageReaction]]> { empty() }
    func watchAttachments(accountId: String, chatGid: String) -> AsyncStream<[ChatMessage]> { empty() }
    func watchSelfUserId(accountId: String) -> AsyncStream<Int?> { empty() }
    func watchTyping(accountId: String) -> AsyncStream<ChatTypingSignal> { empty() }
    func refreshMessages(accountId: String, chatGid: String) async -> Outcome<Void> { unstubbed() }
    func loadOlderMessages(accountId: String, chatGid: String, beforeServerId: Int?, inWindow: Bool, pageSize: Int?) async -> Outcome<Int> { unstubbed() }
    func loadMessagesAround(accountId: String, chatGid: String, serverId: Int) async -> Outcome<(from: Int, to: Int)?> { unstubbed() }
    func loadNewerMessages(accountId: String, chatGid: String, afterServerId: Int) async -> Outcome<Int> { unstubbed() }
    func joinWindowToTimeline(accountId: String, chatGid: String, fromIndex: Int, toIndex: Int) async -> Outcome<Int?> { unstubbed() }
    func countAdjacentMessages(accountId: String, chatGid: String, index: Int, older: Bool, limit: Int) async -> Outcome<Int> { unstubbed() }
    func countOlderMessages(accountId: String, chatGid: String, before: Date) async -> Outcome<Int> { unstubbed() }
    func timelineExtent(accountId: String, chatGid: String) async -> Outcome<ChatTimelineExtent> { unstubbed() }
    func messageCount(accountId: String, chatGid: String) async -> Outcome<Int> { unstubbed() }
    func searchMessages(accountId: String, matching search: ChatMessageSearch) async -> Outcome<[ChatMessage]> { unstubbed() }
    func fetchMessages(accountId: String, chatGid: String, serverIds: [Int]) async -> Outcome<Void> { unstubbed() }
    func sendText(accountId: String, chatGid: String, text: String, replyToId: Int?, markdown: Bool) async -> Outcome<Void> { unstubbed() }
    func sendEmoji(accountId: String, chatGid: String, code: String, replyToId: Int?) async -> Outcome<Void> { unstubbed() }
    func sendCode(accountId: String, chatGid: String, code: String, language: String, name: String?, replyToId: Int?) async -> Outcome<Void> { unstubbed() }
    func sendFile(accountId: String, chatGid: String, name: String, bytes: Data, mimeType: String?, replyToId: Int?) async -> Outcome<Void> { unstubbed() }
    func watchUploadProgress(messageGid: String) -> AsyncStream<Double> { empty() }
    func pendingUploadBytes(messageGid: String) -> Data? { nil }
    func cancelUpload(accountId: String, messageGid: String) async -> Outcome<Void> { unstubbed() }
    func retrySend(accountId: String, messageGid: String) async -> Outcome<Void> { unstubbed() }
    func retract(accountId: String, messageGid: String) async -> Outcome<Void> { unstubbed() }
    func forwardMessage(accountId: String, messageGid: String, toChatGid: String) async -> Outcome<Void> { unstubbed() }
    func sendTyping(accountId: String, chatGid: String, typing: Bool) async -> Outcome<Void> { unstubbed() }
    func attachmentFile(accountId: String, content: MessageContent) async -> Outcome<String> { unstubbed() }
    func loadAttachment(accountId: String, content: MessageContent, thumbnail: Bool) async -> Outcome<Data> { unstubbed() }
    func videoPlayback(accountId: String, content: MessageContent) async -> Outcome<ChatVideoPlayback> { unstubbed() }
    func saveAttachmentCopy(accountId: String, content: MessageContent, targetPath: String) async -> Outcome<Void> { unstubbed() }
    func savedAttachmentCopy(accountId: String, content: MessageContent) async -> String? { nil }
    func cancelDownload(accountId: String, content: MessageContent) {}
    func watchDownloadProgress(accountId: String, content: MessageContent) -> AsyncStream<Double> { empty() }
    func isAttachmentCached(accountId: String, content: MessageContent) async -> Bool { false }
    func videoDuration(accountId: String, video: MessageContent) async -> Outcome<TimeInterval> { unstubbed() }
    func videoThumbnail(accountId: String, video: MessageContent) async -> Outcome<Data> { unstubbed() }
    func pendingVideoThumbnail(messageGid: String, fileName: String) async -> Outcome<Data> { unstubbed() }
    func cacheUsage() async -> Outcome<ChatCacheUsage> { unstubbed() }
    func clearCache(accountId: String?, chatGid: String?) async -> Outcome<Void> { unstubbed() }
    func roleNames(accountId: String) async -> Outcome<[String: String]> { unstubbed() }
    func memberCount(accountId: String, chatGid: String) async -> Outcome<Int> { unstubbed() }
    func members(accountId: String, chatGid: String) async -> Outcome<[Int]> { unstubbed() }
    func openDirectChat(accountId: String, userId: Int) async -> Outcome<String> { unstubbed() }
    func refreshUsers(accountId: String) async -> Outcome<Void> { unstubbed() }
    func createGroupChat(accountId: String, name: String, memberIds: [Int], isPublic: Bool) async -> Outcome<String> { unstubbed() }
    func setChatCategory(accountId: String, chatGids: [String], category: String) async -> Outcome<Void> { unstubbed() }
    func setGroupSettings(accountId: String, chatGid: String, isPublic: Bool, adminInvite: Bool, committers: String) async -> Outcome<Void> { unstubbed() }
    func setGroupAdmins(accountId: String, chatGid: String, userIds: [Int], admin: Bool) async -> Outcome<Void> { unstubbed() }
    func transferGroupOwnership(accountId: String, chatGid: String, userId: Int) async -> Outcome<Void> { unstubbed() }
    func renameGroupChat(accountId: String, chatGid: String, name: String) async -> Outcome<Void> { unstubbed() }
    func dismissGroupChat(accountId: String, chatGid: String) async -> Outcome<Void> { unstubbed() }
    func leaveGroupChat(accountId: String, chatGid: String) async -> Outcome<Void> { unstubbed() }
    func addGroupMembers(accountId: String, chatGid: String, userIds: [Int]) async -> Outcome<Void> { unstubbed() }
    func removeGroupMembers(accountId: String, chatGid: String, userIds: [Int]) async -> Outcome<Void> { unstubbed() }
    func setGroupAvatar(accountId: String, chatGid: String, text: String?, color: String?, image: Data?) async -> Outcome<Void> { unstubbed() }
    func setMyAvatar(accountId: String, image: Data, crop: ChatAvatarCrop?) async -> Outcome<Void> { unstubbed() }
    func setMyPresence(accountId: String, presence: ChatPresence) async -> Outcome<Void> { unstubbed() }
    func setChatStarred(accountId: String, chatGid: String, starred: Bool) async -> Outcome<Void> { unstubbed() }
    func setChatMuted(accountId: String, chatGid: String, muted: Bool) async -> Outcome<Void> { unstubbed() }
    func setMessagePinned(accountId: String, chatGid: String, serverId: Int, pinned: Bool) async -> Outcome<Void> { unstubbed() }
    func markRead(accountId: String, chatGid: String) async -> Outcome<Void> { unstubbed() }
}

enum Make {
    static let t0 = Date(timeIntervalSince1970: 1_790_000_000)

    static func message(_ gid: String = "m1", chat: String = "g", sender: Int = 7, at: Date = t0, content: MessageContent = .text("hi"),
                        mine: Bool = false, state: SendState = .sent, serverId: Int? = nil, index: Int? = nil, replyTo: Int? = nil,
                        deleted: Bool = false, notice: Bool = false) -> ChatMessage {
        ChatMessage(accountId: "a", gid: gid, chatGid: chat, senderId: sender, sentAt: at, content: content, isMine: mine,
                    sendState: state, serverId: serverId, index: index, replyToId: replyTo, deleted: deleted, isNotice: notice)
    }

    static func chat(_ gid: String = "g", type: ChatType = .group, name: String = "Team", unread: Int = 0, hidden: Bool = false,
                     archived: Bool = false, muted: Bool = false) -> ChatConversation {
        ChatConversation(accountId: "a", gid: gid, type: type, name: name, unreadCount: unread, hidden: hidden, archived: archived, muted: muted)
    }
}
