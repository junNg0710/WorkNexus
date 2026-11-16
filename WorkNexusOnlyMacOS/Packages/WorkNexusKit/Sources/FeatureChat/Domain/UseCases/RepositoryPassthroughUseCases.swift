import CoreDomain
import Foundation

/// One-line use cases the presentation layer calls instead of the repository (rule 2.4); each mirrors a Dart file of the same name
/// under lib/features/chat/domain/usecases/.
public struct ConnectChat: Sendable {
    let r: ChatRepository; public init(_ r: ChatRepository) { self.r = r }
    public func callAsFunction(_ accountId: String) async -> Outcome<Void> { await r.connect(accountId: accountId) }
}
public struct TrustChatCertificate: Sendable {
    let r: ChatRepository; public init(_ r: ChatRepository) { self.r = r }
    public func callAsFunction(accountId: String, fingerprint: String) async -> Outcome<Void> { await r.trustCertificate(accountId: accountId, fingerprint: fingerprint) }
}
public struct FetchChatMessages: Sendable {
    let r: ChatRepository; public init(_ r: ChatRepository) { self.r = r }
    public func callAsFunction(accountId: String, chatGid: String, serverIds: [Int]) async -> Outcome<Void> { await r.fetchMessages(accountId: accountId, chatGid: chatGid, serverIds: serverIds) }
}
public struct LoadMessagesAround: Sendable {
    let r: ChatRepository; public init(_ r: ChatRepository) { self.r = r }
    public func callAsFunction(accountId: String, chatGid: String, serverId: Int) async -> Outcome<(from: Int, to: Int)?> { await r.loadMessagesAround(accountId: accountId, chatGid: chatGid, serverId: serverId) }
}
public struct MarkChatRead: Sendable {
    let r: ChatRepository; public init(_ r: ChatRepository) { self.r = r }
    public func callAsFunction(accountId: String, chatGid: String) async -> Outcome<Void> { await r.markRead(accountId: accountId, chatGid: chatGid) }
}
public struct OpenDirectChat: Sendable {
    let r: ChatRepository; public init(_ r: ChatRepository) { self.r = r }
    public func callAsFunction(accountId: String, userId: Int) async -> Outcome<String> { await r.openDirectChat(accountId: accountId, userId: userId) }
}
public struct RefreshChatMessages: Sendable {
    let r: ChatRepository; public init(_ r: ChatRepository) { self.r = r }
    public func callAsFunction(accountId: String, chatGid: String) async -> Outcome<Void> { await r.refreshMessages(accountId: accountId, chatGid: chatGid) }
}
public struct RetrySendMessage: Sendable {
    let r: ChatRepository; public init(_ r: ChatRepository) { self.r = r }
    public func callAsFunction(accountId: String, messageGid: String) async -> Outcome<Void> { await r.retrySend(accountId: accountId, messageGid: messageGid) }
}
public struct LoadChatAttachment: Sendable {
    let r: ChatRepository; public init(_ r: ChatRepository) { self.r = r }
    public func callAsFunction(accountId: String, content: MessageContent, thumbnail: Bool = false) async -> Outcome<Data> { await r.loadAttachment(accountId: accountId, content: content, thumbnail: thumbnail) }
}
public struct OpenChatAttachment: Sendable {
    let r: ChatRepository; public init(_ r: ChatRepository) { self.r = r }
    public func callAsFunction(accountId: String, content: MessageContent) async -> Outcome<String> { await r.attachmentFile(accountId: accountId, content: content) }
}
public struct LoadVideoThumbnail: Sendable {
    let r: ChatRepository; public init(_ r: ChatRepository) { self.r = r }
    public func callAsFunction(accountId: String, video: MessageContent) async -> Outcome<Data> { await r.videoThumbnail(accountId: accountId, video: video) }
}
public struct LoadLinkPreview: Sendable {
    let r: LinkPreviewRepository; public init(_ r: LinkPreviewRepository) { self.r = r }
    public func callAsFunction(_ url: String) async -> Outcome<LinkPreview?> { await r.preview(url: url) }
}
