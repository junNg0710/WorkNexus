import Foundation

/// Who is typing in which chat, each entry valid until its expiry. A peer's client repeats "typing" every few seconds but
/// may never say it stopped, so an entry lapses on its own after `ttl` unless refreshed.
/// Ported from: lib/features/chat/domain/value_objects/typing_roster.dart
public struct TypingRoster: Hashable, Sendable {
    /// chat gid → user id → when that user's typing lapses.
    public var expiries: [String: [Int: Date]] = [:]
    public static let ttl: TimeInterval = 5

    public init(expiries: [String: [Int: Date]] = [:]) { self.expiries = expiries }

    /// The roster after `signal` arrived at `now`. Signals about `selfUserId` (the server may echo our own) are ignored.
    public func apply(_ signal: ChatTypingSignal, now: Date, selfUserId: Int? = nil) -> TypingRoster {
        if signal.userId == selfUserId { return self }
        var chat = expiries[signal.chatGid] ?? [:]
        if signal.typing { chat[signal.userId] = now.addingTimeInterval(Self.ttl) }
        else if chat.removeValue(forKey: signal.userId) == nil { return self }
        var next = expiries
        next[signal.chatGid] = chat.isEmpty ? nil : chat
        return TypingRoster(expiries: next)
    }

    /// The roster without the entries lapsed by `now`.
    public func prune(_ now: Date) -> TypingRoster {
        var next: [String: [Int: Date]] = [:]
        var changed = false
        for (gid, users) in expiries {
            let live = users.filter { $0.value > now }
            if live.count != users.count { changed = true }
            if !live.isEmpty { next[gid] = live }
        }
        return changed ? TypingRoster(expiries: next) : self
    }

    /// Users typing in `chatGid`, earliest to start first.
    public func typing(in chatGid: String) -> [Int] {
        (expiries[chatGid] ?? [:]).sorted { $0.value < $1.value }.map(\.key)
    }

    /// The soonest moment an entry lapses, or nil when nobody is typing.
    public var nextExpiry: Date? { expiries.values.flatMap { $0.values }.min() }
}
