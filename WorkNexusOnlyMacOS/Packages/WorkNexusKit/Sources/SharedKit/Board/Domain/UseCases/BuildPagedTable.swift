import CoreDomain
import Foundation

/// Ported from: lib/shared/board/domain/usecases/build_paged_table.dart
/// One server view's loaded rows; `complete` once every page of it is loaded.
public struct PagedTableSegment<V: Hashable & Sendable>: Sendable {
    public var view: V
    public var tickets: [Ticket]
    public var complete: Bool
    public init(view: V, tickets: [Ticket], complete: Bool) { self.view = view; self.tickets = tickets; self.complete = complete }
}

public struct PagedTableQuery<V: Hashable & Sendable>: Sendable {
    public var segments: [PagedTableSegment<V>]
    public var sort: TicketSort
    public init(segments: [PagedTableSegment<V>], sort: TicketSort = .newest) { self.segments = segments; self.sort = sort }
}

public struct PagedTable<V: Hashable & Sendable>: Sendable {
    public var rows: [Ticket]
    /// The first segment that is not fully loaded (rows stop there), if any.
    public var pending: V?
    public init(rows: [Ticket], pending: V? = nil) { self.rows = rows; self.pending = pending }
}

/// Orders a paged table: segments in order (reversed for a descending status sort), rows within a segment by the
/// sort column; stops at the first incomplete segment so a later segment never shows before an earlier one is whole.
public struct BuildPagedTable<V: Hashable & Sendable>: Sendable {
    public init() {}

    public func callAsFunction(_ q: PagedTableQuery<V>) -> PagedTable<V> {
        let sort = q.sort
        let byStatus = sort.field == .status
        let segments = byStatus && sort.descending ? Array(q.segments.reversed()) : q.segments
        let compare: (Ticket, Ticket) -> Int = byStatus ? Self.byId : Self.comparator(sort)
        var rows: [Ticket] = []
        for segment in segments {
            rows.append(contentsOf: segment.tickets.sorted { compare($0, $1) < 0 })
            if !segment.complete { return PagedTable(rows: rows, pending: segment.view) }
        }
        return PagedTable(rows: rows)
    }

    /// Sort key of a ticket for one column; nil sorts first (ascending).
    private enum Key: Comparable {
        case int(Int), double(Double), string(String), date(Date)
        static func < (a: Key, b: Key) -> Bool {
            switch (a, b) {
            case (.int(let x), .int(let y)): x < y
            case (.double(let x), .double(let y)): x < y
            case (.string(let x), .string(let y)): x < y
            case (.date(let x), .date(let y)): x < y
            default: false
            }
        }
    }

    private static func key(_ field: TicketSortField, _ t: Ticket) -> Key? {
        switch field {
        case .id: return Int(t.externalKey).map(Key.int)
        case .title: return .string(t.title.lowercased())
        case .priority: return .int(t.priority.level)
        case .severity: return t.severity.map(Key.int)
        case .status: return nil
        case .assignee: return t.assignee.map { .string($0.lowercased()) }
        case .estimate: if case .zentaoTask(let e) = t.providerEntity { return e.estimate.map(Key.double) }; return nil
        case .left: if case .zentaoTask(let e) = t.providerEntity { return e.left.map(Key.double) }; return nil
        case .resolution: if case .zentaoBug(let e) = t.providerEntity { return e.resolution.map(Key.string) }; return nil
        case .updated: return t.updatedAt.map(Key.date)
        }
    }

    private static func compareKeys(_ a: Key?, _ b: Key?) -> Int {
        switch (a, b) {
        case (nil, nil): return 0
        case (nil, _): return -1
        case (_, nil): return 1
        case (let x?, let y?): return x < y ? -1 : (y < x ? 1 : 0)
        }
    }

    private static func comparator(_ sort: TicketSort) -> (Ticket, Ticket) -> Int {
        { a, b in
            let c = compareKeys(key(sort.field, a), key(sort.field, b))
            if c != 0 { return sort.descending ? -c : c }
            return byId(a, b)
        }
    }

    /// Newest id first; numeric keys compare as numbers.
    static func byId(_ a: Ticket, _ b: Ticket) -> Int {
        if let ai = Int(a.externalKey), let bi = Int(b.externalKey) { return bi < ai ? -1 : (bi > ai ? 1 : 0) }
        return b.externalKey < a.externalKey ? -1 : (b.externalKey > a.externalKey ? 1 : 0)
    }
}
