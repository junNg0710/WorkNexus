/// Ported from: lib/app/shell/viewport.dart `_updateCache` / tool_pane_host.dart `_remember`.
/// Which sections / panes the shell keeps mounted: the last `limit` places used. Touching a key that is not kept makes room
/// by evicting the least recently used one (the caller unmounts it). Pure value logic, so it is unit-tested without a view.
public struct KeepAliveLRU: Equatable, Sendable {
    public let limit: Int
    /// Least recently used first.
    public private(set) var keys: [String] = []

    public init(limit: Int = 5) { self.limit = max(limit, 1) }

    /// Marks `key` as the one on screen. Returns the key that had to go, if any.
    @discardableResult
    public mutating func touch(_ key: String) -> String? {
        if let i = keys.firstIndex(of: key) { keys.remove(at: i); keys.append(key); return nil }
        keys.append(key)
        guard keys.count > limit else { return nil }
        return keys.removeFirst()
    }

    public mutating func remove(_ key: String) { keys.removeAll { $0 == key } }

    /// Drops every key `keep` refuses (an account that is gone, a workspace that was left).
    public mutating func retain(_ keep: (String) -> Bool) { keys.removeAll { !keep($0) } }

    public mutating func removeAll() { keys = [] }

    public func contains(_ key: String) -> Bool { keys.contains(key) }
}
