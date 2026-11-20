/// Not in the Flutter app: handing tickets out in one click (the quick Assign menu, a card dropped on a person).
import Foundation

/// `login` becomes the most recent person handed tickets; the list keeps `cap` people.
public struct RememberRecentAssignee: Sendable {
    public static let cap = 5
    public init() {}
    public func callAsFunction(_ recent: [String], _ login: String) -> [String] {
        guard !login.isEmpty else { return recent }
        return Array(([login] + recent.filter { $0 != login }).prefix(Self.cap))
    }
}

/// The people the quick Assign menu offers: the pinned ones in the leader's order, then those handed tickets lately,
/// each once, at most `limit`.
public struct ListQuickAssignees: Sendable {
    public static let limit = 8
    public init() {}
    public func callAsFunction(pinned: [String], recent: [String]) -> [String] {
        var seen: Set<String> = []
        return Array((pinned + recent).filter { !$0.isEmpty && seen.insert($0).inserted }.prefix(Self.limit))
    }
}

/// What a card dropped on a person hands over: the whole pick when the card is part of it, else that card alone.
public struct DroppedTicketIds: Sendable {
    public init() {}
    public func callAsFunction(dropped: String, picked: Set<String>) -> Set<String> {
        picked.contains(dropped) ? picked : [dropped]
    }
}
