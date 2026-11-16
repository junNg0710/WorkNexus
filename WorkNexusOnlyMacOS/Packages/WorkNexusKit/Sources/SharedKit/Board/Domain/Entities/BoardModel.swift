import CoreDomain

/// Ported from: lib/shared/board/domain/entities/board_model.dart
/// One Kanban column: a status and the tickets currently in it (already filtered + ordered by `BuildBoard`).
public struct BoardColumn: Hashable, Sendable, Identifiable {
    public var status: UnifiedStatus
    public var tickets: [Ticket]
    public var id: UnifiedStatus { status }
    public var count: Int { tickets.count }
    public init(status: UnifiedStatus, tickets: [Ticket]) { self.status = status; self.tickets = tickets }
}

/// The full board: six columns in status order plus the total.
public struct BoardModel: Hashable, Sendable {
    public var columns: [BoardColumn]
    public var total: Int { columns.reduce(0) { $0 + $1.tickets.count } }
    public init(columns: [BoardColumn]) { self.columns = columns }
    public static let empty = BoardModel(columns: [])
}
