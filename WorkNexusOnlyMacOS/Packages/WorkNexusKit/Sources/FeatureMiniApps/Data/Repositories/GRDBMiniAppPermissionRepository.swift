import CoreDomain
import CorePersistence
import GRDB

/// Ported from: lib/features/mini_apps/data/repositories/local_mini_app_permission_repository.dart
public final class GRDBMiniAppPermissionRepository: MiniAppPermissionRepository, @unchecked Sendable {
    private let db: AppDatabase
    public init(database: AppDatabase) { db = database }

    public func watch(miniAppId: String) -> AsyncStream<[MiniAppPermissionGrant]> {
        db.observe { db in
            try MiniAppPermissionRow.filter(Column("miniAppId") == miniAppId).fetchAll(db).compactMap(MiniAppPermissionGrant.init(row:))
        }
    }

    public func decision(miniAppId: String, kind: MiniAppPermissionKind) async -> Outcome<MiniAppPermissionDecision?> {
        do {
            let row = try await db.writer.read {
                try MiniAppPermissionRow.filter(Column("miniAppId") == miniAppId && Column("kind") == kind.rawValue).fetchOne($0)
            }
            return .success(row.map { $0.allowed ? .allow : .block })
        } catch { return .failure(.storage("Could not read the permission")) }
    }

    public func save(_ grant: MiniAppPermissionGrant) async -> Outcome<Void> {
        do { try await db.writer.write { try MiniAppPermissionRow(grant: grant).save($0) }; return .success(()) }
        catch { return .failure(.storage("Could not keep the permission")) }
    }

    public func clear(miniAppId: String, kind: MiniAppPermissionKind) async -> Outcome<Void> {
        do {
            try await db.writer.write {
                try $0.execute(sql: "DELETE FROM miniAppPermissions WHERE miniAppId = ? AND kind = ?", arguments: [miniAppId, kind.rawValue])
            }
            return .success(())
        } catch { return .failure(.storage("Could not forget the permission")) }
    }
}
