import Foundation

public struct ReplyThread: Sendable { public var rootId: Int; public var replies: [ChatMessage] }
public struct ThreadSummary: Hashable, Sendable { public var count: Int; public var replierIds: [Int]; public var lastReplyAt: Date }

/// Reply threads: a thread is the tree of replies under a root message (xxd has only `replyTo`).
/// Ported from: lib/features/chat/domain/usecases/build_reply_thread.dart
public struct BuildReplyThread: Sendable {
    public init() {}

    /// The root of the thread `messageId` is in. A cycle in server data stops the walk.
    public func rootOf(_ messageId: Int, _ replies: [ChatMessage]) -> Int { Roots(replies).root(of: messageId) }

    public func callAsFunction(_ messageId: Int, _ replies: [ChatMessage], reactions: Bool = true) -> ReplyThread {
        let roots = Roots(replies)
        let root = roots.root(of: messageId)
        let inThread = replies.filter { r in
            guard let p = r.replyToId else { return false }
            return !(reactions && r.isReaction) && roots.root(of: p) == root
        }.sorted { $0.sentAt < $1.sentAt }
        return ReplyThread(rootId: root, replies: inThread)
    }

    public func countsByRoot(_ replies: [ChatMessage], reactions: Bool = true) -> [Int: Int] {
        let roots = Roots(replies)
        var counts: [Int: Int] = [:]
        for r in replies {
            guard let p = r.replyToId, !(reactions && r.isReaction) else { continue }
            counts[roots.root(of: p), default: 0] += 1
        }
        return counts
    }

    public func summariesByRoot(_ replies: [ChatMessage], reactions: Bool = true) -> [Int: ThreadSummary] {
        let roots = Roots(replies)
        var byRoot: [Int: [ChatMessage]] = [:]
        for r in replies {
            guard let p = r.replyToId, !(reactions && r.isReaction) else { continue }
            byRoot[roots.root(of: p), default: []].append(r)
        }
        return byRoot.mapValues { list in
            let newestFirst = list.sorted { $0.sentAt > $1.sentAt }
            var repliers: [Int] = []
            for m in newestFirst where !repliers.contains(m.senderId) { repliers.append(m.senderId) }
            return ThreadSummary(count: list.count, replierIds: repliers, lastReplyAt: newestFirst[0].sentAt)
        }
    }

    /// Who each reply answers, read once for a whole list (it was re-read for every reply: quadratic in a chat with
    /// hundreds of replies, on the main thread whenever they changed).
    /// Walks that reach a message answering nothing are remembered for every message on the way, so a long chain is
    /// walked once (a walk stopped by a cycle is not: where it stops depends on where it started).
    private final class Roots {
        private var parentOf: [Int: Int] = [:]
        private var known: [Int: Int] = [:]

        init(_ replies: [ChatMessage]) {
            parentOf.reserveCapacity(replies.count)
            for r in replies { if let s = r.serverId, let p = r.replyToId { parentOf[s] = p } }
        }

        func root(of messageId: Int) -> Int {
            var id = messageId
            var path = [id]
            var seen: Set<Int> = [id]
            while let parent = parentOf[id] {
                if let root = known[parent] { id = root; break }
                guard seen.insert(parent).inserted else { return id }
                id = parent
                path.append(id)
            }
            for p in path { known[p] = id }
            return id
        }
    }
}
