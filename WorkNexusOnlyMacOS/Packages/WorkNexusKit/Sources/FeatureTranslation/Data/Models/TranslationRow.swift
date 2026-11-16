import Foundation
import GRDB

/// DB row of the core `translations` table (CorePersistence `core_v1`); never leaves `Data/` (rule 3.3).
struct TranslationRow: Codable, FetchableRecord, PersistableRecord {
    static let databaseTableName = "translations"
    var ticketId: String
    var sourceHash: String
    var targetLang: String
    var translatedTitle: String
    var translatedBody: String
    var model: String
    var templateVersion: String
    var createdAt: Date
}
