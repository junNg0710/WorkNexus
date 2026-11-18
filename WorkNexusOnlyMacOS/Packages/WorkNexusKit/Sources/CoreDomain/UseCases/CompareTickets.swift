/// Ported from: lib/shared/board/domain/usecases/compare_tickets.dart
/// Lives in the shared kernel (not SharedKit) so the GitLab / GitHub board builders, whose domain stays free of SharedKit,
/// order their columns with the same comparator as the shared board, the ZenTao boards and the paged tables.
import Foundation

public extension TicketSortField {
    /// What a Kanban board offers to sort its cards by. Status is left out: the columns already are the status.
    static let boardFields: [TicketSortField] = [.priority, .updated, .id, .title, .assignee]
    /// `boardFields` plus severity, for boards whose tickets carry one (bugs).
    static let boardFieldsWithSeverity: [TicketSortField] = [.priority, .severity, .updated, .id, .title, .assignee]
}

/// Ticket orderings shared by the boards and the tables. A comparator returns < 0 when `a` comes first.
public enum CompareTickets {
    public typealias Comparator = (Ticket, Ticket) -> Int

    /// Orders tickets by `sort`'s field, falling back to `tieBreak` among equals. Missing values sort first ascending
    /// (last descending), as ZenTao's empty fields do.
    public static func by(_ sort: TicketSort, tieBreak: @escaping Comparator = byIdDesc) -> Comparator {
        { a, b in
            let c = compareKeys(key(sort.field, a), key(sort.field, b))
            if c != 0 { return sort.descending ? -c : c }
            return tieBreak(a, b)
        }
    }

    /// A board column's order: `sort`, then most recently updated, then newest. Deadline (macOS-only on the ZenTao
    /// boards) keeps cards without one last either way, then orders equals by priority, so the most overdue lead.
    public static func board(_ sort: TicketSort) -> Comparator {
        guard sort.field == .deadline else { return by(sort, tieBreak: byUpdatedThenId) }
        let byPriority = by(.boardDefault, tieBreak: byUpdatedThenId)
        return { a, b in
            switch (key(.deadline, a), key(.deadline, b)) {
            case (nil, nil): return byPriority(a, b)
            case (nil, _): return 1
            case (_, nil): return -1
            case (let x, let y):
                let c = compareKeys(x, y)
                return c != 0 ? (sort.descending ? -c : c) : byPriority(a, b)
            }
        }
    }

    /// `tickets` in a board column's order (`board(sort)`).
    public static func boardOrdered(_ tickets: [Ticket], by sort: TicketSort) -> [Ticket] {
        let compare = board(sort)
        return tickets.sorted { compare($0, $1) < 0 }
    }

    /// Higher ids first; a non-numeric key falls back to text order.
    public static func byIdDesc(_ a: Ticket, _ b: Ticket) -> Int {
        if let ai = Int(a.externalKey), let bi = Int(b.externalKey) { return bi < ai ? -1 : (bi > ai ? 1 : 0) }
        return b.externalKey < a.externalKey ? -1 : (b.externalKey > a.externalKey ? 1 : 0)
    }

    static func byUpdatedThenId(_ a: Ticket, _ b: Ticket) -> Int {
        let au = a.updatedAt ?? Date(timeIntervalSince1970: 0), bu = b.updatedAt ?? Date(timeIntervalSince1970: 0)
        if au != bu { return bu < au ? -1 : 1 }
        return byIdDesc(a, b)
    }

    /// Sort key of a ticket for one field; nil is a missing value.
    enum Key: Comparable {
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

    static func key(_ field: TicketSortField, _ t: Ticket) -> Key? {
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
        case .deadline:
            // ZenTao sends a deadline as `yyyy-MM-dd`, which orders as text.
            switch t.providerEntity {
            case .zentaoTask(let e)?: return (e.deadline ?? "").isEmpty ? nil : .string(e.deadline!)
            case .zentaoBug(let e)?: return (e.deadline ?? "").isEmpty ? nil : .string(e.deadline!)
            default: return nil
            }
        }
    }

    static func compareKeys(_ a: Key?, _ b: Key?) -> Int {
        switch (a, b) {
        case (nil, nil): return 0
        case (nil, _): return -1
        case (_, nil): return 1
        case (let x?, let y?): return x < y ? -1 : (y < x ? 1 : 0)
        }
    }
}
