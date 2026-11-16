import CoreDomain
import GRDB

public final class GRDBCommentRepository: CommentRepository {
    private let db: AppDatabase
    public init(db: AppDatabase) { self.db = db }
    public func watchComments(ticketId: String) -> AsyncStream<[Comment]> {
        db.observe { try CommentRow.filter(Column("ticketId") == ticketId).order(Column("createdAt")).fetchAll($0).map(\.entity) }
    }
    public func upsertComments(_ comments: [Comment]) async -> Outcome<Void> {
        await guarded { try await self.db.writer.write { d in for c in comments { try CommentRow(c).save(d) } } }
    }
}
