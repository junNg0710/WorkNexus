import CoreDomain
import Foundation

/// Ported from: lib/shared/board/domain/usecases/build_board.dart
/// Filters tickets and groups them into the six status columns, ordering each column by the query's sort (urgent first,
/// then most recently updated, by default).
public struct BuildBoard: Sendable {
    public var filter = FilterTickets()
    public init() {}
    public func callAsFunction(_ q: BoardQuery) -> BoardModel {
        var byStatus: [UnifiedStatus: [Ticket]] = [:]
        for t in filter(q) { byStatus[t.status, default: []].append(t) }
        return BoardModel(columns: UnifiedStatus.columns.map { s in
            BoardColumn(status: s, tickets: CompareTickets.boardOrdered(byStatus[s] ?? [], by: q.sort))
        })
    }
}
