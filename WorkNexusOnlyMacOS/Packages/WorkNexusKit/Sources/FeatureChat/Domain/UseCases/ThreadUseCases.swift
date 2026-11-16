import Foundation

public struct ReplyThread: Sendable { public var rootId: Int; public var replies: [ChatMessage] }
public struct ThreadSummary: Hashable, Sendable { public var count: Int; public var replierIds: [Int]; public var lastReplyAt: Date }

/// Reply threads: a thread is the tree of replies under a root message (xxd has only `replyTo`).
/// Ported from: lib/features/chat/domain/usecases/build_reply_thread.dart
public struct BuildReplyThread: Sendable {
    public init() {}

    /// The root of the thread `messageId` is in. A cycle in server data stops the walk.
    public func rootOf(_ messageId: Int, _ replies: [ChatMessage]) -> Int {
        var parentOf: [Int: Int] = [:]
        for r in replies { if let s = r.serverId, let p = r.replyToId { parentOf[s] = p } }
        var id = messageId
        var seen: Set<Int> = [id]
        while let parent = parentOf[id], seen.insert(parent).inserted { id = parent }
        return id
    }

    public func callAsFunction(_ messageId: Int, _ replies: [ChatMessage], reactions: Bool = true) -> ReplyThread {
        let root = rootOf(messageId, replies)
        let inThread = replies.filter { r in
            guard let p = r.replyToId else { return false }
            return !(reactions && r.isReaction) && rootOf(p, replies) == root
        }.sorted { $0.sentAt < $1.sentAt }
        return ReplyThread(rootId: root, replies: inThread)
    }

    public func countsByRoot(_ replies: [ChatMessage], reactions: Bool = true) -> [Int: Int] {
        var counts: [Int: Int] = [:]
        for r in replies {
            guard let p = r.replyToId, !(reactions && r.isReaction) else { continue }
            counts[rootOf(p, replies), default: 0] += 1
        }
        return counts
    }

    public func summariesByRoot(_ replies: [ChatMessage], reactions: Bool = true) -> [Int: ThreadSummary] {
        var byRoot: [Int: [ChatMessage]] = [:]
        for r in replies {
            guard let p = r.replyToId, !(reactions && r.isReaction) else { continue }
            byRoot[rootOf(p, replies), default: []].append(r)
        }
        return byRoot.mapValues { list in
            let newestFirst = list.sorted { $0.sentAt > $1.sentAt }
            var repliers: [Int] = []
            for m in newestFirst where !repliers.contains(m.senderId) { repliers.append(m.senderId) }
            return ThreadSummary(count: list.count, replierIds: repliers, lastReplyAt: newestFirst[0].sentAt)
        }
    }
}
