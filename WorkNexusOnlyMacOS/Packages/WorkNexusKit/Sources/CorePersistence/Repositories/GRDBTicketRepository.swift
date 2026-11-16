import CoreDomain
import GRDB

public final class GRDBTicketRepository: TicketRepository {
    private let db: AppDatabase
    public init(db: AppDatabase) { self.db = db }

    public func watchTickets() -> AsyncStream<[Ticket]> {
        db.observe { try TicketRow.fetchAll($0).compactMap(\.entity) }
    }
    public func ticket(id: String) async -> Outcome<Ticket?> {
        await guarded { try await self.db.writer.read { try TicketRow.fetchOne($0, key: id)?.entity } }
    }
    /// Writes only rows whose `sourceHash` changed (TicketStore behaviour in shared/sync).
    public func upsertTickets(_ tickets: [Ticket]) async -> Outcome<Void> {
        await guarded {
            try await self.db.writer.write { d in
                for t in tickets {
                    let old = try String.fetchOne(d, sql: "SELECT sourceHash FROM tickets WHERE id = ?", arguments: [t.id])
                    if old != t.sourceHash { try TicketRow(t).save(d) }
                }
            }
        }
    }
    public func moveTicket(id: String, to status: UnifiedStatus) async -> Outcome<Void> {
        await guarded {
            try await self.db.writer.write { d in
                try d.execute(sql: "UPDATE tickets SET statusNorm = ? WHERE id = ?", arguments: [status.rawValue, id])
            }
        }
    }
}
