import CoreDomain
import GRDB

public final class GRDBTicketRepository: TicketRepository {
    private let db: AppDatabase
    private let keepsLabel: @Sendable (String) -> Bool

    /// - Parameter keepsLabel: labels a stored ticket keeps when a write does not carry them (the board-membership
    ///   markers each list sync stamps only its own of); the composition root passes the rule.
    public init(db: AppDatabase, keepsLabel: @escaping @Sendable (String) -> Bool = { _ in false }) {
        self.db = db; self.keepsLabel = keepsLabel
        allTickets = SharedObservation(throttle: .milliseconds(300), isSame: { $0 == $1 }) {
            db.observeConstantRegion { d in
                try PerformanceLog.measureSync("db: read every ticket", slowerThan: 0.3) { try TicketRow.fetchAll(d).compactMap(\.entity) }
            }
        }
    }

    /// Every ticket, read and decoded once per change for all the boards, counters and panes watching it (each used to
    /// run its own query: ten watchers decoded the whole table ten times on every write). A list equal to the last one
    /// is not sent, so a watcher is only ever handed a list that differs from the one it has.
    private let allTickets: SharedObservation<[Ticket]>

    public func watchTickets() -> AsyncStream<[Ticket]> { allTickets.stream() }
    public func ticket(id: String) async -> Outcome<Ticket?> {
        await guarded { try await self.db.writer.read { try TicketRow.fetchOne($0, key: id)?.entity } }
    }
    /// Inserts or replaces each ticket, as the Flutter store does (`insert ... onConflict: DoUpdate`). A ticket's status,
    /// assignee, priority or labels change without its title or body (its `sourceHash`) changing, so the hash alone
    /// must not decide. A row that already reads the same is left alone, so the watchers are not woken for nothing.
    /// The labels `keepsLabel` names are carried forward from the stored row: without that, a list that stamps only
    /// its own marker would take the ticket off every other board.
    public func upsertTickets(_ tickets: [Ticket]) async -> Outcome<Void> {
        let keepsLabel = self.keepsLabel
        return await PerformanceLog.measure("db: write \(tickets.count) tickets", slowerThan: 0.2) { await guarded {
            try await self.db.writer.write { d in
                for t in tickets {
                    let old = try TicketRow.fetchOne(d, key: t.id)
                    var merged = t
                    merged.labels += (old?.entity?.labels ?? []).filter { keepsLabel($0) && !t.labels.contains($0) }
                    let row = TicketRow(merged)
                    // Compared as the database stores them (dates at its precision).
                    if let old, try old.databaseDictionary == row.databaseDictionary { continue }
                    try row.save(d)
                }
            }
        } }
    }
    public func moveTicket(id: String, to status: UnifiedStatus) async -> Outcome<Void> {
        await guarded {
            try await self.db.writer.write { d in
                try d.execute(sql: "UPDATE tickets SET statusNorm = ? WHERE id = ?", arguments: [status.rawValue, id])
            }
        }
    }
}
