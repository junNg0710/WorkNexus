import CoreDomain
import GRDB

public final class GRDBActivityRepository: ActivityRepository {
    private let db: AppDatabase
    public init(db: AppDatabase) { self.db = db }
    public func watchActivity(ticketId: String) -> AsyncStream<[ActivityEvent]> {
        db.observe { try ActivityRow.filter(Column("ticketId") == ticketId).order(Column("at").desc).fetchAll($0).map(\.entity) }
    }
    public func upsertActivity(_ events: [ActivityEvent]) async -> Outcome<Void> {
        await guarded { try await self.db.writer.write { d in for e in events { try ActivityRow(e).save(d) } } }
    }
}
