/// Ported from: lib/shared/board/domain/value_objects/paged_view_loads.dart
/// What a paged board's views have loaded, and nothing else of their state: the ids a started view holds, or `nil`
/// for a view that has not loaded its first page yet, and which started views still have pages to load (`partial`).
/// Compares by value, so a page starting/failing/retrying — which does not change what is loaded — does not re-scope the board.
public struct PagedViewLoads<V: Hashable & Sendable>: Hashable, Sendable {
    public var ids: [V: Set<String>?]
    public var partial: Set<V>
    public init(_ ids: [V: Set<String>?], partial: Set<V> = []) { self.ids = ids; self.partial = partial }

    /// Projects the views' states down to what each has loaded.
    public static func of(_ views: [V: PagedViewState]) -> PagedViewLoads<V> {
        var ids: [V: Set<String>?] = [:]
        var partial: Set<V> = []
        for (k, v) in views {
            ids[k] = .some(v.started ? v.ids : nil)
            if v.started && v.hasMore { partial.insert(k) }
        }
        return PagedViewLoads(ids, partial: partial)
    }

    /// Set equality for `[V: Set<String>?]` (nested optionals make the synthesized one unavailable).
    public static func == (a: Self, b: Self) -> Bool {
        guard a.partial == b.partial, Set(a.ids.keys) == Set(b.ids.keys) else { return false }
        for (k, v) in a.ids where b.ids[k]! != v { return false }
        return true
    }
    public func hash(into h: inout Hasher) {
        h.combine(partial)
        for k in ids.keys.sorted(by: { "\($0)" < "\($1)" }) { h.combine(k); h.combine(ids[k]!) }
    }
}
