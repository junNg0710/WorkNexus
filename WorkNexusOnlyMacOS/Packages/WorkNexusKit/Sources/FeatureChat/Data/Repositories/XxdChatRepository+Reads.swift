import CoreDomain
import Foundation

/// Reads (database watches), history paging, read state and runtime settings.
extension XxdChatRepository {
    public static let pageSize = ChatHistorySync.pageSize

    // MARK: watches

    public func watchConversations(accountId: String) -> AsyncStream<[ChatConversation]> { local.watchConversations(accountId) }

    public func watchMessages(accountId: String, chatGid: String, limit: Int, reactions: Bool) -> AsyncStream<[ChatMessage]> {
        local.watchMessages(accountId, chatGid, limit: limit, reactions: reactions)
    }

    public func watchMessage(accountId: String, chatGid: String, serverId: Int) -> AsyncStream<ChatMessage?> {
        local.watchMessageByServerId(accountId, chatGid, serverId)
    }

    public func watchReplies(accountId: String, chatGid: String) -> AsyncStream<[ChatMessage]> { local.watchReplies(accountId, chatGid) }

    public func watchReactions(accountId: String, chatGid: String) -> AsyncStream<[Int: [MessageReaction]]> {
        local.watchReplies(accountId, chatGid).mapped { BuildReactions()($0) }.removingDuplicates()
    }

    public func watchAttachments(accountId: String, chatGid: String) -> AsyncStream<[ChatMessage]> { local.watchAttachments(accountId, chatGid) }
    public func watchUsers(accountId: String) -> AsyncStream<[ChatUser]> { local.watchUsers(accountId) }
    public func watchSelfUserId(accountId: String) -> AsyncStream<Int?> { local.watchSelfUserId(accountId) }

    public func watchMessagesInRange(accountId: String, chatGid: String, fromIndex: Int, toIndex: Int, reactions: Bool) -> AsyncStream<[ChatMessage]> {
        local.watchMessagesInRange(accountId, chatGid, from: fromIndex, to: toIndex, reactions: reactions)
    }

    public func watchTyping(accountId: String) -> AsyncStream<ChatTypingSignal> { typing.watch(accountId) }

    // MARK: history

    public func refreshMessages(accountId: String, chatGid: String) async -> Outcome<Void> {
        await history.refresh(session(accountId), accountId, chatGid)
    }

    public func loadOlderMessages(accountId: String, chatGid: String, beforeServerId: Int?, inWindow: Bool, pageSize: Int?) async -> Outcome<Int> {
        await history.loadOlder(session(accountId), accountId, chatGid, before: beforeServerId, inWindow: inWindow, pageSize: pageSize)
    }

    public func loadMessagesAround(accountId: String, chatGid: String, serverId: Int) async -> Outcome<(from: Int, to: Int)?> {
        await history.loadAround(session(accountId), accountId, chatGid, serverId)
    }

    public func loadNewerMessages(accountId: String, chatGid: String, afterServerId: Int) async -> Outcome<Int> {
        await history.loadNewer(session(accountId), accountId, chatGid, after: afterServerId)
    }

    public func fetchMessages(accountId: String, chatGid: String, serverIds: [Int]) async -> Outcome<Void> {
        await history.fetchByIds(session(accountId), accountId, chatGid, serverIds)
    }

    public func messageCount(accountId: String, chatGid: String) async -> Outcome<Int> { await history.messageCount(session(accountId), chatGid) }

    private func storage<T>(_ what: String, _ body: () async throws -> T) async -> Outcome<T> {
        do { return .success(try await body()) } catch { return .failure(.storage("\(what): \(error.localizedDescription)")) }
    }

    public func joinWindowToTimeline(accountId: String, chatGid: String, fromIndex: Int, toIndex: Int) async -> Outcome<Int?> {
        await storage("Could not join the messages") { try await local.timeline.joinWindow(accountId, chatGid, from: fromIndex, to: toIndex) }
    }

    public func countOlderMessages(accountId: String, chatGid: String, before: Date) async -> Outcome<Int> {
        await storage("Could not read stored messages") { try await local.countOlder(accountId, chatGid, before: before) }
    }

    public func countAdjacentMessages(accountId: String, chatGid: String, index: Int, older: Bool, limit: Int) async -> Outcome<Int> {
        await storage("Could not read stored messages") { try await local.timeline.countAdjacent(accountId, chatGid, index: index, older: older, limit: limit) }
    }

    public func timelineExtent(accountId: String, chatGid: String) async -> Outcome<ChatTimelineExtent> {
        await storage("Could not read stored messages") {
            let e = try await local.timeline.extent(accountId, chatGid)
            return ChatTimelineExtent(count: e.count, oldestServerId: e.oldestServerId, oldestSentAt: e.oldestSentAt, reachesStart: e.reachesStart)
        }
    }

    public func searchMessages(accountId: String, chatGid: String?, query: String, since: Date?, limit: Int?) async -> Outcome<[ChatMessage]> {
        await storage("Could not search messages") { try await local.searchMessages(accountId, cgid: chatGid, query: query, since: since, limit: limit) }
    }

    /// Marks the chat read up to its last message: locally at once, on the server when online.
    public func markRead(accountId: String, chatGid: String) async -> Outcome<Void> {
        let row: ChatConversationRow
        do {
            guard let r = try await local.conversation(accountId, chatGid), r.lastReadIndex < r.lastMessageIndex else { return .success(()) }
            row = r
            try await local.setLastReadIndex(accountId, chatGid, r.lastMessageIndex)
        } catch { return .failure(.storage("Could not mark the chat read: \(error.localizedDescription)")) }
        // Offline: read locally now; the server keeps its own value until the chat is read again while connected.
        guard let session = session(accountId), await session.isOnline() else { return .success(()) }
        switch await session.connection.request(XxdRequest("chatSetLastReadMessageByIndex", params: [.string(chatGid), .int(row.lastMessageIndex)])) {
        case .success: return .success(())
        case .failure(let f): return .failure(f)
        }
    }

    // MARK: runtime settings

    public func setCacheLimit(bytes: Int) { cacheManager.setLimit(bytes) }
    public func setVideoAutoDownloadLimit(bytes: Int) { videoAutoDownloadBytes.with { $0 = bytes } }
    public func setReactions(_ on: Bool) { ingestor.reactions = on }
}
