import CoreDomain
import Foundation
import GRDB

public final class GRDBSettingsRepository: SettingsRepository {
    private struct Row: Codable, FetchableRecord, PersistableRecord { static let databaseTableName = "settings"; var id = 0; var json: String }
    private let db: AppDatabase
    public init(db: AppDatabase) { self.db = db }

    private static func decode(_ row: Row?) -> AppSettings {
        row.flatMap { $0.json.data(using: .utf8) }.flatMap { try? JSONDecoder().decode(AppSettings.self, from: $0) } ?? AppSettings()
    }
    public func load() async -> AppSettings { (try? await db.writer.read { Self.decode(try Row.fetchOne($0, key: 0)) }) ?? AppSettings() }
    public func save(_ s: AppSettings) async -> Outcome<Void> {
        await guarded {
            let json = String(data: try JSONEncoder().encode(s), encoding: .utf8) ?? "{}"
            try await self.db.writer.write { try Row(json: json).save($0) }
        }
    }
    public func watch() -> AsyncStream<AppSettings> { db.observe { Self.decode(try Row.fetchOne($0, key: 0)) } }
}
