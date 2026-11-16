import CoreDomain
import CorePersistence
import Foundation
import SharedKit

// The composition root's adapters between SharedKit's persistence ports and CorePersistence's storage classes
// (CorePersistence cannot see SharedKit, and SharedKit must not see GRDB): each is a few lines that only translate.

/// Ported from: lib/shared/board/data/repositories/local_saved_filter_repository.dart. The board's filter presets in the
/// core `savedFilters` table, shared by every board (`SavedFilterStorage.install`).
final class DatabaseSavedFilterRepository: SavedFilterRepository, @unchecked Sendable {
    private let store: GRDBSavedFilterStore
    init(db: AppDatabase) { store = GRDBSavedFilterStore(db: db) }

    func watchSavedFilters() -> AsyncStream<[SavedFilter]> {
        let rows = store.watch()
        return AsyncStream { cont in
            let task = Task {
                for await list in rows {
                    cont.yield(list.map { SavedFilter(id: $0.id, name: $0.name, filter: SavedFilterMapper.decode($0.filterJson), createdAt: $0.createdAt) })
                }
                cont.finish()
            }
            cont.onTermination = { _ in task.cancel() }
        }
    }

    func upsert(_ f: SavedFilter) async -> Outcome<Void> {
        await store.upsert(SavedFilterRecord(id: f.id, name: f.name, filterJson: SavedFilterMapper.encode(f.filter), createdAt: f.createdAt))
    }

    func delete(id: String) async -> Outcome<Void> { await store.delete(id: id) }
}

/// Ported from: lib/shared/sync/data/source_list_cache.dart. The sidebar's product / project lists, kept in
/// `sourceListSnapshots` so the tree paints from disk on launch.
struct DatabaseSourceListStore: SourceListSnapshotStore {
    let snapshots: GRDBSourceListSnapshots
    init(db: AppDatabase) { snapshots = GRDBSourceListSnapshots(db: db) }
    func read(accountId: String, kind: String) async -> String? { await snapshots.read(accountId: accountId, kind: kind) }
    func write(accountId: String, kind: String, json: String) async { await snapshots.write(accountId: accountId, kind: kind, json: json) }
}

/// Ported from: lib/shared/sync/data/ticket_store.dart. A detail refresh replaces the comments and the activity of a ticket
/// in one transaction (deleted-on-server entries go, internal notes stay), and an optimistic update overwrites the row.
struct DatabaseDetailWriter: DetailWriting {
    let store: GRDBDetailStore
    init(db: AppDatabase) { store = GRDBDetailStore(db: db) }

    func replaceProviderComments(ticketId: String, comments: [Comment]) async -> Outcome<Void> {
        await store.replaceDetail(ticketId: ticketId, comments: comments, events: nil)
    }
    func replaceActivity(ticketId: String, events: [ActivityEvent]) async -> Outcome<Void> {
        await store.replaceDetail(ticketId: ticketId, comments: nil, events: events)
    }
    func replaceDetail(ticketId: String, comments: [Comment]?, events: [ActivityEvent]?) async -> Outcome<Void> {
        await store.replaceDetail(ticketId: ticketId, comments: comments, events: events)
    }
    func overwrite(ticket: Ticket) async -> Outcome<Void> { await store.overwrite(ticket) }
}
