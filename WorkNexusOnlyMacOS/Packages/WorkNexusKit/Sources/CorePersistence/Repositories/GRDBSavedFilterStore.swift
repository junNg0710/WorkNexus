import CoreDomain
import Foundation
import GRDB

/// One row of the core `savedFilters` table: a named filter preset, its filter as the JSON `SavedFilterMapper` writes.
public struct SavedFilterRecord: Equatable, Sendable {
    public var id: String
    public var name: String
    public var filterJson: String
    public var createdAt: Date
    public init(id: String, name: String, filterJson: String, createdAt: Date) {
        self.id = id; self.name = name; self.filterJson = filterJson; self.createdAt = createdAt
    }
}

private struct SavedFilterRow: Codable, FetchableRecord, PersistableRecord {
    static let databaseTableName = "savedFilters"
    var id: String, name: String, filterJson: String, createdAt: Date
}

/// Ported from: lib/shared/board/data/repositories/local_saved_filter_repository.dart (the storage half). The board's
/// presets live in the local database (rule 16): the popover watches them and every board shares them. `SharedKit` owns the
/// `SavedFilterRepository` port and its JSON mapper; the composition root adapts this store to it (CorePersistence cannot see
/// SharedKit). Writes map database errors to a `Failure`.
public final class GRDBSavedFilterStore: Sendable {
    private let db: AppDatabase
    public init(db: AppDatabase) { self.db = db }

    /// Every preset, newest first, re-emitted on each change.
    public func watch() -> AsyncStream<[SavedFilterRecord]> {
        db.observe { d in
            try SavedFilterRow.order(Column("createdAt").desc).fetchAll(d)
                .map { SavedFilterRecord(id: $0.id, name: $0.name, filterJson: $0.filterJson, createdAt: $0.createdAt) }
        }
    }

    public func upsert(_ r: SavedFilterRecord) async -> Outcome<Void> {
        await guarded {
            try await self.db.writer.write { d in
                try SavedFilterRow(id: r.id, name: r.name, filterJson: r.filterJson, createdAt: r.createdAt).save(d)
            }
        }
    }

    public func delete(id: String) async -> Outcome<Void> {
        await guarded {
            try await self.db.writer.write { d in _ = try SavedFilterRow.deleteOne(d, key: id) }
        }
    }
}
