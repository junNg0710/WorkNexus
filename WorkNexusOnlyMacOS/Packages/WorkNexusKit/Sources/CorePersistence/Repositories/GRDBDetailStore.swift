import CoreDomain
import Foundation
import GRDB

/// Ported from: lib/shared/sync/data/ticket_store.dart (the writes that need a transaction).
/// What a detail refresh writes: the server's comments and activity *replace* the stored ones (deleted-on-server entries
/// go; the user's own notes stay) and the ticket row is overwritten even when its hash is unchanged. `replaceDetail` does
/// both lists in ONE transaction, so a watcher never sees new comments next to the old activity. `SharedKit` adapts this to
/// its `DetailWriting` port at the composition root.
public final class GRDBDetailStore: Sendable {
    private let db: AppDatabase
    public init(db: AppDatabase) { self.db = db }

    /// Replaces the provider's comments (`origin = provider`) and/or the activity of `ticketId`; nil leaves a list alone.
    public func replaceDetail(ticketId: String, comments: [Comment]?, events: [ActivityEvent]?) async -> Outcome<Void> {
        await guarded {
            try await self.db.writer.write { d in
                if let comments {
                    try d.execute(sql: "DELETE FROM comments WHERE ticketId = ? AND origin = ?",
                                  arguments: [ticketId, CommentOrigin.provider.rawValue])
                    for c in comments { try CommentRow(c).save(d) }
                }
                if let events {
                    try d.execute(sql: "DELETE FROM activities WHERE ticketId = ?", arguments: [ticketId])
                    for e in events { try ActivityRow(e).save(d) }
                }
            }
        }
    }

    /// Writes `ticket` over its stored row whatever its `sourceHash` (an optimistic update and its rollback).
    public func overwrite(_ ticket: Ticket) async -> Outcome<Void> {
        await guarded { try await self.db.writer.write { d in try TicketRow(ticket).save(d) } }
    }
}
