import CoreDomain
import Foundation

/// Ported from: lib/features/chat/domain/usecases/build_reactions.dart
public struct BuildReactions: Sendable {
    public init() {}
    /// Groups reaction replies by the message they answer: one entry per person per emoji (their latest wins).
    public func callAsFunction(_ replies: [ChatMessage]) -> [Int: [MessageReaction]] {
        let ordered = replies.filter { $0.isReaction && !$0.deleted && $0.sendState != .failed }.sorted { $0.sentAt < $1.sentAt }
        var targets: [Int] = []
        var byTarget: [Int: (order: [String], map: [String: [ChatMessage]])] = [:]
        for r in ordered {
            let target = r.replyToId!, emoji = r.reactionEmoji!
            if byTarget[target] == nil { byTarget[target] = ([], [:]); targets.append(target) }
            if byTarget[target]!.map[emoji] == nil { byTarget[target]!.order.append(emoji); byTarget[target]!.map[emoji] = [] }
            var people = byTarget[target]!.map[emoji]!
            if let at = people.firstIndex(where: { $0.senderId == r.senderId }) { people[at] = r } else { people.append(r) }
            byTarget[target]!.map[emoji] = people
        }
        var out: [Int: [MessageReaction]] = [:]
        for t in targets {
            let entry = byTarget[t]!
            out[t] = entry.order.map { emoji in
                let list = entry.map[emoji]!
                return MessageReaction(emoji: emoji, userIds: list.map(\.senderId), mine: list.first { $0.isMine })
            }
        }
        return out
    }
}

/// Ported from: lib/features/chat/domain/usecases/is_reaction_row.dart
public struct IsReactionRow: Sendable {
    public init() {}
    public func retracted(replyToId: Int?, deleted: Bool, contentType: String, content: String) -> Bool {
        deleted && replyToId != nil && content.isEmpty && contentType == "emotion"
    }
    public func callAsFunction(replyToId: Int?, deleted: Bool, contentType: String, content: String) -> Bool {
        guard replyToId != nil else { return false }
        return retracted(replyToId: replyToId, deleted: deleted, contentType: contentType, content: content)
            || ParseMessageContent()(contentType, content).asEmoji != nil
    }
}

/// Ported from: lib/features/chat/domain/usecases/retract_message.dart
public struct RetractMessage: Sendable {
    public static let window: TimeInterval = 120
    private let repository: ChatRepository
    private let now: @Sendable () -> Date
    public init(_ repository: ChatRepository, now: @escaping @Sendable () -> Date = Date.init) { self.repository = repository; self.now = now }

    public func canRetract(_ m: ChatMessage) -> Bool {
        m.isMine && !m.deleted && m.serverId != nil && m.sendState == .sent && now().timeIntervalSince(m.sentAt) <= Self.window
    }
    public func callAsFunction(_ m: ChatMessage) async -> Outcome<Void> {
        guard canRetract(m) else { return .failure(.unexpected("Only your own messages from the last 2 minutes")) }
        return await repository.retract(accountId: m.accountId, messageGid: m.gid)
    }
}

/// Ported from: lib/features/chat/domain/usecases/toggle_reaction.dart
public struct ToggleReaction: Sendable {
    private let repository: ChatRepository
    private let retract: RetractMessage
    public init(_ repository: ChatRepository, now: @escaping @Sendable () -> Date = Date.init) {
        self.repository = repository; retract = RetractMessage(repository, now: now)
    }

    public func canRemove(_ r: MessageReaction) -> Bool { r.mine.map(retract.canRetract) ?? false }

    /// Adds `emoji` as a reaction to `message`, or takes the current user's own back when they already used it.
    public func callAsFunction(_ message: ChatMessage, _ emoji: String, reactions: [MessageReaction]) async -> Outcome<Void> {
        guard let serverId = message.serverId, !message.deleted else { return .failure(.unexpected("Nothing to react to yet")) }
        if let existing = reactions.first(where: { $0.emoji == emoji }), let mine = existing.mine {
            // Still on its way: nothing to take back yet, and none to add again.
            if mine.sendState == .pending { return .success(()) }
            guard canRemove(existing) else { return .failure(.expired("Reaction can no longer be removed")) }
            return await retract(mine)
        }
        let code = EncodeEmoji()(emoji.trimmingCharacters(in: .whitespacesAndNewlines))
        guard !code.isEmpty else { return .failure(.unexpected("No emoji to send")) }
        return await repository.sendEmoji(accountId: message.accountId, chatGid: message.chatGid, code: code, replyToId: serverId)
    }
}
