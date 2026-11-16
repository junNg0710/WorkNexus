import Foundation
import GRDB

/// Ported from: lib/shared/sync/data/source_list_cache.dart (the storage half). The last-fetched provider container lists
/// (ZenTao products / projects) per account and `kind`, as an opaque JSON payload in `sourceListSnapshots`.
///
/// That table is created by the ToolZenTao migration (it owns it), so it is touched defensively: where the module is not
/// registered a read is a cache miss and a write does nothing. `SharedKit.SourceListCache` keeps the payload format; the
/// composition root adapts this to its `SourceListSnapshotStore` port.
public final class GRDBSourceListSnapshots: Sendable {
    private let db: AppDatabase
    public init(db: AppDatabase) { self.db = db }

    public func read(accountId: String, kind: String) async -> String? {
        (try? await db.writer.read { d -> String? in
            guard try d.tableExists("sourceListSnapshots") else { return nil }
            return try String.fetchOne(d, sql: "SELECT json FROM sourceListSnapshots WHERE accountId = ? AND kind = ?",
                                       arguments: [accountId, kind])
        }) ?? nil
    }

    public func write(accountId: String, kind: String, json: String) async {
        try? await db.writer.write { d in
            guard try d.tableExists("sourceListSnapshots") else { return }
            try d.execute(sql: """
                INSERT INTO sourceListSnapshots (accountId, kind, json, fetchedAt) VALUES (?, ?, ?, ?)
                ON CONFLICT(accountId, kind) DO UPDATE SET json = excluded.json, fetchedAt = excluded.fetchedAt
                """, arguments: [accountId, kind, json, Date()])
        }
    }
}
