import CoreDomain
import CorePersistence
import Foundation
import GRDB

/// Fetches the raw ZenTao `GET /user?fields=...` reply of an account. Injected by the composition root, which
/// routes it through the account's pooled client.
public typealias ZenTaoUserInfoFetcher = @Sendable (_ accountId: String, _ fields: String, _ limit: Int) async -> Outcome<ZenTaoRawReply>
/// Syncs every ticket assigned to an account's user into the ticket store.
public typealias ZenTaoAssignedWorkSyncer = @Sendable (String) async -> Outcome<Int>

/// Ported from: lib/features/workspace_overview/data/repositories/zentao_dashboard_repository.dart
/// `ZenTaoDashboardRepository` over ZenTao: stores the raw reply in `dashboardSnapshots` and parses it on read,
/// so a better parser also applies to an already-stored snapshot.
public final class GRDBZenTaoDashboardRepository: ZenTaoDashboardRepository, @unchecked Sendable {
    private let db: AppDatabase
    private let fetch: ZenTaoUserInfoFetcher
    private let syncAssigned: ZenTaoAssignedWorkSyncer
    private let now: @Sendable () -> Date

    public init(db: AppDatabase, fetch: @escaping ZenTaoUserInfoFetcher, syncAssigned: @escaping ZenTaoAssignedWorkSyncer,
                now: @escaping @Sendable () -> Date = { Date() }) {
        self.db = db; self.fetch = fetch; self.syncAssigned = syncAssigned; self.now = now
    }

    /// A snapshot that no longer decodes is treated as absent (refetched).
    private static func parse(_ row: DashboardSnapshotRow?) -> ZenTaoDashboard? {
        guard let row, let json = asMap(try? jsonDecode(row.json)) else { return nil }
        return zenTaoDashboardFromJson(json, accountId: row.accountId, fetchedAt: row.fetchedAt)
    }

    public func watch(accountId: String) -> AsyncStream<ZenTaoDashboard?> {
        db.observe { Self.parse(try DashboardSnapshotRow.fetchOne($0, key: accountId)) }
    }

    public func cached(accountId: String) async -> ZenTaoDashboard? {
        (try? await db.writer.read { Self.parse(try DashboardSnapshotRow.fetchOne($0, key: accountId)) }) ?? nil
    }

    public func refresh(accountId: String) async -> Outcome<Void> {
        switch await fetch(accountId, kZenTaoDashboardFields, kZenTaoDashboardListLimit) {
        case .failure(let f): return .failure(f)
        case .success(let reply):
            let row = DashboardSnapshotRow(accountId: accountId, json: jsonEncode(reply.json), fetchedAt: now())
            do { try await db.writer.write { try row.save($0) }; return .success(()) }
            catch { return .failure(.storage("Could not store the dashboard")) }
        }
    }

    public func syncAssignedWork(accountId: String) async -> Outcome<Void> {
        (await syncAssigned(accountId)).map { _ in () }
    }
}
