/// Not in the Flutter app.
import Foundation

/// The people strip's order: the pinned people first, in the order the leader gave them, then everyone else as they came
/// (most work first). Pinned people with nothing on this board are not listed.
public struct OrderWorkload: Sendable {
    public init() {}
    public func callAsFunction(_ rows: [ZenTaoWorkload], pinned: [String]) -> [ZenTaoWorkload] {
        let byLogin = Dictionary(rows.map { ($0.login, $0) }, uniquingKeysWith: { a, _ in a })
        let front = pinned.compactMap { byLogin[$0] }
        let set = Set(pinned)
        return front + rows.filter { !set.contains($0.login) }
    }
}

/// Pins a person at the end of the pinned ones, or unpins them. "Unassigned" (no login) cannot be pinned.
public struct TogglePinnedPerson: Sendable {
    public init() {}
    public func callAsFunction(_ pinned: [String], _ login: String) -> [String] {
        guard !login.isEmpty else { return pinned }
        return pinned.contains(login) ? pinned.filter { $0 != login } : pinned + [login]
    }
}

/// A person dragged onto another: they are pinned and placed just before the one they were dropped on when that one is
/// pinned, else at the end of the pinned people (so dragging always lands them at the front of the strip).
public struct MovePinnedPerson: Sendable {
    public init() {}
    public func callAsFunction(_ pinned: [String], move login: String, before target: String) -> [String] {
        guard !login.isEmpty, login != target else { return pinned }
        var out = pinned.filter { $0 != login }
        if let at = out.firstIndex(of: target) { out.insert(login, at: at) } else { out.append(login) }
        return out
    }
}
