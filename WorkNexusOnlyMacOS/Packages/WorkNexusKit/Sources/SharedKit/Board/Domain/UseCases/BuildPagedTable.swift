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
        let compare = byStatus ? CompareTickets.byIdDesc : CompareTickets.by(sort)
        var rows: [Ticket] = []
        for segment in segments {
            rows.append(contentsOf: segment.tickets.sorted { compare($0, $1) < 0 })
            if !segment.complete { return PagedTable(rows: rows, pending: segment.view) }
        }
        return PagedTable(rows: rows)
    }
}
