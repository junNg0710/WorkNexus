import CoreDomain
import CorePersistence
import Foundation
import GRDB

/// Ported from: lib/features/translation/data/repositories/local_translation_repository.dart
/// GRDB-backed `TranslationRepository` — the persisted translation per ticket, in the core `translations` table.
/// Owned by the translation feature (single consumer).
public final class GRDBTranslationRepository: TranslationRepository, @unchecked Sendable {
    private let db: AppDatabase
    public init(database: AppDatabase) { db = database }

    public func watchTranslation(ticketId: String) -> AsyncStream<TranslationRecord?> {
        db.observe { db in
            try TranslationRow.fetchOne(db, key: ticketId).map(TranslationRecord.init(row:))
        }
    }

    public func translation(ticketId: String) async -> Outcome<TranslationRecord?> {
        do {
            let row = try await db.writer.read { try TranslationRow.fetchOne($0, key: ticketId) }
            return .success(row.map(TranslationRecord.init(row:)))
        } catch { return .failure(.storage("Could not read the translation: \(error)")) }
    }

    public func saveTranslation(_ record: TranslationRecord) async -> Outcome<Void> {
        do {
            try await db.writer.write { try TranslationRow(record: record).save($0) }
            return .success(())
        } catch { return .failure(.storage("Could not save the translation: \(error)")) }
    }
}
