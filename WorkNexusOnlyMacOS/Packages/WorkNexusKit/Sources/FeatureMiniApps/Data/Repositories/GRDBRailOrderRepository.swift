import CoreDomain
import CorePersistence
import GRDB

/// Not in the Flutter app. `RailOrderRepository` over the local database: the `position` of `miniApps` and of `nativeApps`
/// count in one sequence (since migration `miniapps_v5`).
public final class GRDBRailOrderRepository: RailOrderRepository, @unchecked Sendable {
    private let db: AppDatabase
    private static let failure = "Could not keep the order of the rail"

    public init(database: AppDatabase) { db = database }

    /// Gives each entry of `refs` its index as position, in one write.
    public func saveOrder(_ refs: [RailAppRef]) async -> Outcome<Void> {
        do {
            try await db.writer.write { db in
                for (i, ref) in refs.enumerated() {
                    try db.execute(sql: "UPDATE \(Self.table(ref.kind)) SET position = ? WHERE id = ?", arguments: [i, ref.appId])
                }
            }
            return .success(())
        } catch { return .failure(.storage(Self.failure)) }
    }

    public func nextPosition() async -> Outcome<Int> {
        do {
            let last = try await db.writer.read { db in
                try Int.fetchOne(db, sql: "SELECT MAX(position) FROM (SELECT position FROM miniApps UNION ALL SELECT position FROM nativeApps)")
            }
            return .success((last ?? -1) + 1)
        } catch { return .failure(.storage(Self.failure)) }
    }

    private static func table(_ kind: RailAppRef.Kind) -> String {
        switch kind {
        case .miniApp: "miniApps"
        case .nativeApp: "nativeApps"
        }
    }
}
