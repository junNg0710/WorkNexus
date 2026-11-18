import CoreDomain
import Foundation

/// Stores one more page of a chat's history, before the oldest message of its stored timeline — for a local AI tool that
/// reads the stored history and found too little of it.
///
/// Pages back from the oldest *timeline* message, not the oldest stored one (see `DownloadChatHistory`): stored history may
/// have gaps. With nothing stored yet it fetches the newest page instead.
/// Ported from: lib/features/chat/domain/usecases/load_older_timeline_page.dart
public struct LoadOlderTimelinePage: Sendable {
    /// The largest page a caller may ask for.
    public static let maxPageSize = 200
    private let repository: ChatRepository
    public init(_ repository: ChatRepository) { self.repository = repository }

    public func callAsFunction(accountId: String, chatGid: String, pageSize: Int = 100) async -> Outcome<ChatHistoryStep> {
        let before: ChatTimelineExtent
        switch await repository.timelineExtent(accountId: accountId, chatGid: chatGid) {
        case .success(let v): before = v
        case .failure(let f): return .failure(f)
        }
        if before.reachesStart { return .success(ChatHistoryStep(loaded: 0, reachesStart: true)) }
        guard let oldest = before.oldestServerId else {
            if case .failure(let f) = await repository.refreshMessages(accountId: accountId, chatGid: chatGid) { return .failure(f) }
            return await repository.timelineExtent(accountId: accountId, chatGid: chatGid).map {
                ChatHistoryStep(loaded: $0.count, reachesStart: $0.reachesStart || $0.count == 0)
            }
        }
        let arrived: Int
        switch await repository.loadOlderMessages(accountId: accountId, chatGid: chatGid, beforeServerId: oldest, inWindow: false,
                                                  pageSize: min(max(pageSize, 1), Self.maxPageSize)) {
        case .success(let n): arrived = n
        case .failure(let f): return .failure(f)
        }
        return await repository.timelineExtent(accountId: accountId, chatGid: chatGid).map {
            // Nothing older, or a page that reached no further back: asking again would get the same, so the caller stops.
            ChatHistoryStep(loaded: arrived, reachesStart: $0.reachesStart || arrived == 0 || ($0.oldestServerId ?? oldest) >= oldest)
        }
    }
}

/// Downloads the file or image of one message to a local file — for a local AI tool that reads the stored history, where
/// attachments are only named. A message not stored yet is fetched from the server first.
/// Ported from: lib/features/chat/domain/usecases/fetch_message_attachment.dart
public struct FetchMessageAttachment: Sendable {
    private let repository: ChatRepository
    public init(_ repository: ChatRepository) { self.repository = repository }

    public func callAsFunction(accountId: String, chatGid: String, messageId: Int) async -> Outcome<ChatAttachmentFile> {
        var message = await stored(accountId, chatGid, messageId)
        if message == nil {
            if case .failure(let f) = await repository.fetchMessages(accountId: accountId, chatGid: chatGid, serverIds: [messageId]) {
                return .failure(f)
            }
            message = await stored(accountId, chatGid, messageId)
        }
        guard let message else { return .failure(.notFound("Message \(messageId) not found in this chat")) }
        if message.deleted { return .failure(.notFound("Message \(messageId) was recalled")) }
        let meta: (name: String, size: Int, mimeType: String?, isImage: Bool)
        switch message.content {
        case .image(let i): meta = (i.name, i.size, i.mimeType, true)
        case .file(let f): meta = (f.name, f.size, f.mimeType, false)
        default: return .failure(.validation("Message \(messageId) has no file or image"))
        }
        return await repository.attachmentFile(accountId: accountId, content: message.content).map {
            ChatAttachmentFile(path: $0, name: meta.name, size: meta.size, mimeType: meta.mimeType, isImage: meta.isImage)
        }
    }

    private func stored(_ accountId: String, _ chatGid: String, _ messageId: Int) async -> ChatMessage? {
        var it = repository.watchMessage(accountId: accountId, chatGid: chatGid, serverId: messageId).makeAsyncIterator()
        return await it.next() ?? nil
    }
}

public extension ChatLocalApiHandlers {
    /// The handlers the local API runs with: messages go through `SendTextMessage`, as if typed in the composer.
    /// Ported from: lib/features/chat/presentation/providers/chat_local_api_providers.dart (`chatLocalApiRunnerProvider`)
    static func using(_ repository: ChatRepository) -> ChatLocalApiHandlers {
        let send = SendTextMessage(repository), older = LoadOlderTimelinePage(repository), attachment = FetchMessageAttachment(repository)
        return ChatLocalApiHandlers(
            send: { await send(accountId: $0, chatGid: $1, text: $2, markdown: $3) },
            loadOlder: { await older(accountId: $0, chatGid: $1, pageSize: $2) },
            attachment: { await attachment(accountId: $0, chatGid: $1, messageId: $2) })
    }
}
