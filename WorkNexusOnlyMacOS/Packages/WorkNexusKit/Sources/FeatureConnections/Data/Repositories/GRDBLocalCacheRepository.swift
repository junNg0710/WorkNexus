import CoreDomain
import CorePersistence
import Foundation
import GRDB

/// Ported from: lib/features/connections/data/repositories/drift_local_cache_repository.dart
/// Clears cached tables in one transaction, so a failure leaves the cache as it was rather than half-emptied.
/// The tables are named, not imported: they belong to the core, ZenTao and chat modules. One that is not
/// registered in this database (a module not installed) is skipped.
public final class GRDBLocalCacheRepository: LocalCacheRepository {
    private let db: AppDatabase
    public init(db: AppDatabase) { self.db = db }

    /// The tables each section owns (same lists as the Flutter app; accounts, workspaces, settings, saved filters
    /// and chat sign-ins are never in them).
    public static func tables(of section: CacheSection) -> [String] {
        switch section {
        case .tickets: ["comments", "activities", "tickets", "projects", "sourceListSnapshots"]
        case .dashboard: ["dashboardSnapshots", "zenTaoNotifications", "zenTaoProfiles"]
        case .chat: ["chatMessages", "chatConversations", "chatUsers", "chatLinkPreviews", "chatSavedFiles"]
        case .translations: ["translations", "chatMessageTranslations"]
        }
    }

    public func clear(_ sections: Set<CacheSection>) async -> Outcome<Void> {
        let ordered = CacheSection.allCases.filter(sections.contains)
        let result: Outcome<Void> = await guarded {
            try await self.db.writer.write { d in
                for section in ordered {
                    for table in Self.tables(of: section) where try d.tableExists(table) {
                        try d.execute(sql: "DELETE FROM \"\(table)\"")
                    }
                }
            }
        }
        if case .failure(let f) = result { return .failure(.storage("Could not clear the cache: \(f.message)")) }
        return result
    }
}
