import CoreDomain
import Foundation

/// Ported from: lib/features/chat/domain/usecases/load_older_messages.dart
public struct LoadOlderMessages: Sendable {
    public static let windowPage = 50
    private let repository: ChatRepository
    public init(_ repository: ChatRepository) { self.repository = repository }

    /// Reveals the next older page: from storage when it holds one, else from the server.
    public func callAsFunction(accountId: String, chatGid: String, oldestShown: ChatMessage? = nil, inWindow: Bool = false) async -> Outcome<Int> {
        if inWindow, let index = oldestShown?.index {
            switch await repository.countAdjacentMessages(accountId: accountId, chatGid: chatGid, index: index, older: true, limit: Self.windowPage) {
            case .success(let n) where n > 0: return .success(n)
            case .failure(let f): return .failure(f)
            default: break
            }
        }
        if let oldest = oldestShown, !inWindow {
            switch await repository.countOlderMessages(accountId: accountId, chatGid: chatGid, before: oldest.sentAt) {
            case .success(let n) where n > 0: return .success(n)
            case .failure(let f): return .failure(f)
            default: break
            }
        }
        return await repository.loadOlderMessages(accountId: accountId, chatGid: chatGid, beforeServerId: oldestShown?.serverId, inWindow: inWindow, pageSize: nil)
    }
}

public struct NewerMessages: Hashable, Sendable { public var added: Int; public var joined: Int? }

/// Ported from: lib/features/chat/domain/usecases/load_newer_messages.dart
public struct LoadNewerMessages: Sendable {
    public static let windowPage = 50
    private let repository: ChatRepository
    public init(_ repository: ChatRepository) { self.repository = repository }

    public func callAsFunction(accountId: String, chatGid: String, newestShown: ChatMessage, windowFrom: Int) async -> Outcome<NewerMessages> {
        guard let serverId = newestShown.serverId, let index = newestShown.index else { return .success(NewerMessages(added: 0, joined: nil)) }
        switch await repository.countAdjacentMessages(accountId: accountId, chatGid: chatGid, index: index, older: false, limit: Self.windowPage) {
        case .success(let n) where n > 0: return .success(NewerMessages(added: n, joined: nil))
        case .failure(let f): return .failure(f)
        default: break
        }
        // Reaching the timeline — which runs up to the newest message — joins it without asking the server for anything newer.
        switch await join(accountId, chatGid, windowFrom, index) {
        case .success(let r) where r.joined != nil: return .success(r)
        case .failure(let f): return .failure(f)
        default: break
        }
        switch await repository.loadNewerMessages(accountId: accountId, chatGid: chatGid, afterServerId: serverId) {
        case .failure(let f): return .failure(f)
        case .success(let n) where n > 0: return .success(NewerMessages(added: n, joined: nil))
        default: break
        }
        return await join(accountId, chatGid, windowFrom, index)
    }

    private func join(_ accountId: String, _ chatGid: String, _ from: Int, _ index: Int) async -> Outcome<NewerMessages> {
        switch await repository.joinWindowToTimeline(accountId: accountId, chatGid: chatGid, fromIndex: from, toIndex: index) {
        case .success(let v): return .success(NewerMessages(added: 0, joined: v))
        case .failure(let f): return .failure(f)
        }
    }
}

/// Downloads a chat's stored history page by page, reporting progress; back to `since` or to the first message.
/// Ported from: lib/features/chat/domain/usecases/download_chat_history.dart
public struct DownloadChatHistory: Sendable {
    public static let pageSize = 200
    private let repository: ChatRepository
    public init(_ repository: ChatRepository) { self.repository = repository }

    public func callAsFunction(accountId: String, chatGid: String, since: Date? = nil) -> AsyncStream<Outcome<ChatHistoryProgress>> {
        AsyncStream { cont in
            let task = Task { await run(accountId, chatGid, since) { cont.yield($0) }; cont.finish() }
            cont.onTermination = { _ in task.cancel() }
        }
    }

    private func run(_ accountId: String, _ chatGid: String, _ since: Date?, _ emit: (Outcome<ChatHistoryProgress>) -> Void) async {
        var extent = await repository.timelineExtent(accountId: accountId, chatGid: chatGid)
        if case .success(let v) = extent, v.reaches(since) { emit(.success(Self.complete(v.count, v.count))); return }
        // Back to a date, how many messages that is is unknown: the progress has no total then.
        var total = 0
        if since == nil {
            switch await repository.messageCount(accountId: accountId, chatGid: chatGid) {
            case .success(let n): total = n
            case .failure(let f): emit(.failure(f)); return
            }
        }
        if case .success(let v) = extent, v.oldestServerId == nil {
            // Nothing stored yet: start from the newest page.
            if case .failure(let f) = await repository.refreshMessages(accountId: accountId, chatGid: chatGid) { emit(.failure(f)); return }
            extent = await repository.timelineExtent(accountId: accountId, chatGid: chatGid)
        }
        while !Task.isCancelled {
            let current: ChatTimelineExtent
            switch extent { case .success(let v): current = v; case .failure(let f): emit(.failure(f)); return }
            guard let oldest = current.oldestServerId, !current.reaches(since) else { emit(.success(Self.complete(current.count, total))); return }
            emit(.success(ChatHistoryProgress(stored: current.count, total: total)))
            switch await repository.loadOlderMessages(accountId: accountId, chatGid: chatGid, beforeServerId: oldest, inWindow: false, pageSize: Self.pageSize) {
            case .failure(let f): emit(.failure(f)); return
            case .success(0): emit(.success(Self.complete(current.count, total))); return // the server has nothing older: this is the start
            case .success: extent = await repository.timelineExtent(accountId: accountId, chatGid: chatGid)
            }
            // A page that reached no further back would be asked for forever.
            if case .success(let v) = extent, (v.oldestServerId ?? oldest) >= oldest { emit(.success(Self.complete(v.count, total))); return }
        }
    }

    private static func complete(_ stored: Int, _ total: Int) -> ChatHistoryProgress {
        ChatHistoryProgress(stored: stored, total: max(stored, total), complete: true)
    }
}
