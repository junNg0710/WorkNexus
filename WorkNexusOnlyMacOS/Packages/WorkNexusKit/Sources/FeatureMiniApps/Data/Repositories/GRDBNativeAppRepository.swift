import CoreDomain
import CorePersistence
import GRDB

/// New feature, no Dart counterpart. `NativeAppRepository` over the local database (table `nativeApps`, migration `miniapps_v2`).
public final class GRDBNativeAppRepository: NativeAppRepository, @unchecked Sendable {
    private let db: AppDatabase
    private static let failure = "Could not keep the Mac app"

    public init(database: AppDatabase) { db = database }

    public func watchAll() -> AsyncStream<[NativeApp]> {
        db.observe { try NativeAppRow.order(Column("position")).fetchAll($0).map(NativeApp.init(row:)) }
    }

    public func save(_ app: NativeApp) async -> Outcome<Void> {
        await write { try NativeAppRow(app: app).save($0) }
    }

    /// Gives each app in `ids` its index as position, in one write.
    public func saveOrder(_ ids: [String]) async -> Outcome<Void> {
        await write { db in
            for (i, id) in ids.enumerated() { try db.execute(sql: "UPDATE nativeApps SET position = ? WHERE id = ?", arguments: [i, id]) }
        }
    }

    public func delete(id: String) async -> Outcome<Void> {
        await write { try $0.execute(sql: "DELETE FROM nativeApps WHERE id = ?", arguments: [id]) }
    }

    private func write(_ body: @escaping @Sendable (Database) throws -> Void) async -> Outcome<Void> {
        do { try await db.writer.write(body); return .success(()) }
        catch { return .failure(.storage(Self.failure)) }
    }
}
