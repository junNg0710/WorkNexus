import CoreDomain
import Foundation

/// Ported from: lib/shared/board/domain/usecases/{scope_paged_view_tickets,scope_provider_tickets,search_local_tickets,switch_board_filter}.dart

public struct PagedViewScopeQuery<V: Hashable & Sendable> {
    public var tickets: [Ticket]
    public var loads: PagedViewLoads<V>
    public var viewOf: (Ticket) -> V
    public var columnOf: (Ticket) -> AnyHashable?
    public init(tickets: [Ticket], loads: PagedViewLoads<V>, viewOf: @escaping (Ticket) -> V,
                columnOf: ((Ticket) -> AnyHashable?)? = nil) {
        self.tickets = tickets; self.loads = loads; self.viewOf = viewOf
        self.columnOf = columnOf ?? { AnyHashable(viewOf($0)) }
    }
}

/// Keeps the tickets a paged board's loaded views hold, plus cached ones of views not (fully) loaded yet.
public struct ScopePagedViewTickets<V: Hashable & Sendable> {
    public init() {}
    public func callAsFunction(_ q: PagedViewScopeQuery<V>) -> [Ticket] {
        var loaded = Set<String>()
        var unloaded = Set<V>()
        for (k, v) in q.loads.ids { if let ids = v { loaded.formUnion(ids) } else { unloaded.insert(k) } }
        // The columns of each partial view that its loaded pages reach.
        var reached: [V: Set<AnyHashable?>] = [:]
        for t in q.tickets {
            let view = q.viewOf(t)
            if loaded.contains(t.id), q.loads.partial.contains(view) { reached[view, default: []].insert(q.columnOf(t)) }
        }
        func keepsCached(_ t: Ticket) -> Bool {
            let view = q.viewOf(t)
            if unloaded.contains(view) { return true }
            return q.loads.partial.contains(view) && !(reached[view]?.contains(q.columnOf(t)) ?? false)
        }
        return q.tickets.filter { loaded.contains($0.id) || keepsCached($0) }
    }
}

/// A provider board's tickets: one account + provider + external type (+ optional membership label / id slice).
public struct ScopeProviderTickets: Sendable {
    public init() {}
    public func callAsFunction(tickets: [Ticket], accountId: String, providerType: ProviderType, externalType: String,
                               slice: Set<String>?, membershipLabel: String? = nil) -> [Ticket] {
        let type = externalType.lowercased()
        return tickets.filter {
            $0.accountId == accountId && $0.providerType == providerType && ($0.externalType ?? "").lowercased() == type
                && (membershipLabel == nil || $0.labels.contains(membershipLabel!))
                && (slice == nil || slice!.contains($0.id))
        }
    }
}

/// Quick search over cached tickets: id exact, id prefix, title word prefix, title substring (best tier first, max 8).
public struct SearchLocalTickets: Sendable {
    public init() {}
    public func callAsFunction(tickets: [Ticket], query: String, accountId: String? = nil) -> [Ticket] {
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if q.isEmpty { return [] }
        let candidates = accountId == nil ? tickets : tickets.filter { $0.accountId == accountId }
        var matches: [(tier: Int, ticket: Ticket)] = []
        for t in candidates {
            let key = t.externalKey.lowercased(), title = t.title.lowercased()
            if key == q { matches.append((0, t)) }
            else if key.hasPrefix(q) { matches.append((1, t)) }
            else if title.split(whereSeparator: { $0.isWhitespace }).contains(where: { $0.hasPrefix(q) }) { matches.append((2, t)) }
            else if title.contains(q) { matches.append((3, t)) }
        }
        return matches.enumerated().sorted { a, b in
            a.element.tier != b.element.tier ? a.element.tier < b.element.tier : a.offset < b.offset
        }.prefix(8).map(\.element.ticket)
    }
}

/// Remembers each board's filter when you leave it and restores it on return (a re-select is a no-op).
public struct SwitchBoardFilter: Sendable {
    public struct Result: Sendable { public var memory: [String: FilterState]; public var filter: FilterState }
    public init() {}
    public func callAsFunction(memory: [String: FilterState], fromKey: String?, toKey: String, current: FilterState,
                               initial: FilterState) -> Result {
        var next = memory
        if let fromKey { next[fromKey] = current }
        if fromKey == toKey { return Result(memory: next, filter: current) }
        return Result(memory: next, filter: next[toKey] ?? initial)
    }
}
