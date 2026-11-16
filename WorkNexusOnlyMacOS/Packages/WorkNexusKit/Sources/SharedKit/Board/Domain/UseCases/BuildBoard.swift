import CoreDomain
import Foundation

/// Ported from: lib/shared/board/domain/usecases/build_board.dart
/// Filters tickets and groups them into the six status columns (priority first, then most recently updated).
public struct BuildBoard: Sendable {
    public var filter = FilterTickets()
    public init() {}
    public func callAsFunction(_ q: BoardQuery) -> BoardModel {
        var byStatus: [UnifiedStatus: [Ticket]] = [:]
        for t in filter(q) { byStatus[t.status, default: []].append(t) }
        return BoardModel(columns: UnifiedStatus.columns.map { s in
            BoardColumn(status: s, tickets: (byStatus[s] ?? []).sorted(by: Self.byPriorityThenUpdated))
        })
    }
    /// Stable sort: lower priority level first, then newest `updatedAt`.
    static func byPriorityThenUpdated(_ a: Ticket, _ b: Ticket) -> Bool {
        if a.priority.level != b.priority.level { return a.priority.level < b.priority.level }
        return (a.updatedAt ?? .distantPast) > (b.updatedAt ?? .distantPast)
    }
}
