import CoreDomain
import CorePersistence
import GRDB

/// New feature, no Dart counterpart. `NativeAppRepository` over the local database (table `nativeApps`, migration `miniapps_v2`).
public final class GRDBNativeAppRepository: NativeAppRepository, @unchecked Sendable {
    private let db: AppDatabase
    private let icons: MiniAppIconStore?
    private static let failure = "Could not keep the Mac app"

    /// `icons`: where the icons the user picks are kept (none: an icon cannot be picked).
    public init(database: AppDatabase, icons: MiniAppIconStore? = nil) { db = database; self.icons = icons }

    public func watchAll() -> AsyncStream<[NativeApp]> {
        db.observe { try NativeAppRow.order(Column("position")).fetchAll($0).map(NativeApp.init(row:)) }
    }

    public func save(_ app: NativeApp) async -> Outcome<Void> {
        await write { try NativeAppRow(app: app).save($0) }
    }

    public func delete(id: String) async -> Outcome<Void> {
        await write { try $0.execute(sql: "DELETE FROM nativeApps WHERE id = ?", arguments: [id]) }
    }

    public func importIcon(id: String, sourcePath: String) async -> Outcome<String> {
        guard let icons else { return .failure(.storage(Self.failure)) }
        do { return .success(try icons.importFile(id: id, sourcePath: sourcePath)) }
        catch { return .failure(.storage(Self.failure)) }
    }

    public func deleteIcon(id: String) async { icons?.delete(id: id) }

    private func write(_ body: @escaping @Sendable (Database) throws -> Void) async -> Outcome<Void> {
        do { try await db.writer.write(body); return .success(()) }
        catch { return .failure(.storage(Self.failure)) }
    }
}
