import CoreDomain
import CorePersistence
import Foundation
import GRDB

/// Fetches the raw ZenTao notification-menu view of an account.
public typealias ZenTaoMessagesFetcher = @Sendable (String) async -> Outcome<ZenTaoRawReply>
/// Runs a ZenTao message action (e.g. `ajaxMarkRead-12`) for an account.
public typealias ZenTaoMessageActionRunner = @Sendable (String, String) async -> Outcome<Void>

/// Ported from: lib/features/notifications/data/repositories/zentao_notification_repository.dart
/// `ZenTaoNotificationRepository` over ZenTao's classic message actions, stored in `zenTaoNotifications`.
/// Commands update the store first so the UI reacts at once; when the server refuses, the account is refetched
/// to undo the optimistic change.
public final class GRDBZenTaoNotificationRepository: ZenTaoNotificationRepository, @unchecked Sendable {
    private let db: AppDatabase
    private let fetch: ZenTaoMessagesFetcher
    private let run: ZenTaoMessageActionRunner

    public init(db: AppDatabase, fetch: @escaping ZenTaoMessagesFetcher, run: @escaping ZenTaoMessageActionRunner) {
        self.db = db; self.fetch = fetch; self.run = run
    }

    public func watchAll() -> AsyncStream<[ZenTaoNotification]> {
        db.observe { d in
            try ZenTaoNotificationRow.order(Column("createdAt").desc).fetchAll(d).map(\.entity)
        }
    }

    /// Realnames from stored ZenTao profiles, keyed by accountId.
    public func watchAccountRealnames() -> AsyncStream<[String: String]> {
        db.observe { d in
            var names: [String: String] = [:]
            for row in try ZenTaoProfileRow.fetchAll(d) {
                guard let any = try? jsonDecode(row.profileJson), let profile = asMap(any)?["profile"].flatMap(asMap),
                      let name = str(profile["realname"])?.trimmingCharacters(in: .whitespacesAndNewlines), !name.isEmpty else { continue }
                names[row.accountId] = name
            }
            return names
        }.removingDuplicates()
    }

    public func refresh(accountId: String) async -> Outcome<Void> {
        switch await fetch(accountId) {
        case .failure(let f): return .failure(f)
        case .success(let reply):
            let items = zenTaoNotificationsFromView(reply.json, accountId: accountId)
            return await store {
                // Every two minutes, for every account: only a changed set is written, so the rail badge and
                // the panel stay quiet otherwise.
                let stored = try await self.db.writer.read { d in
                    try ZenTaoNotificationRow.filter(Column("accountId") == accountId).fetchAll(d).map(\.entity)
                }
                if Dictionary(stored.map { ($0.id, $0) }, uniquingKeysWith: { $1 }) == Dictionary(items.map { ($0.id, $0) }, uniquingKeysWith: { $1 }) { return }
                try await self.db.writer.write { d in
                    try ZenTaoNotificationRow.filter(Column("accountId") == accountId).deleteAll(d)
                    for n in items { try ZenTaoNotificationRow(n).save(d) }
                }
            }
        }
    }

    public func markRead(accountId: String, id: String?) async -> Outcome<Void> {
        await command(accountId, { try await self.setRead(accountId, id: id, read: true) }, "ajaxMarkRead-\(id ?? "all")")
    }

    public func markUnread(accountId: String, id: String) async -> Outcome<Void> {
        await command(accountId, { try await self.setRead(accountId, id: id, read: false) }, "ajaxMarkUnread-\(id)")
    }

    public func delete(accountId: String, id: String) async -> Outcome<Void> {
        await command(accountId, { try await self.delete(accountId, id: id, readOnly: false) }, "ajaxDelete-\(id)")
    }

    public func deleteRead(accountId: String) async -> Outcome<Void> {
        await command(accountId, { try await self.delete(accountId, id: nil, readOnly: true) }, "ajaxDelete-allread")
    }

    // MARK: Local store

    /// Sets `read` on one notification, or with a nil `id` on all of `accountId`'s.
    private func setRead(_ accountId: String, id: String?, read: Bool) async throws {
        try await db.writer.write { d in
            var request = ZenTaoNotificationRow.filter(Column("accountId") == accountId)
            if let id { request = request.filter(Column("id") == id) }
            try request.updateAll(d, Column("read").set(to: read))
        }
    }

    /// Deletes one notification, or with `readOnly` all read ones of `accountId`.
    private func delete(_ accountId: String, id: String?, readOnly: Bool) async throws {
        try await db.writer.write { d in
            var request = ZenTaoNotificationRow.filter(Column("accountId") == accountId)
            if let id { request = request.filter(Column("id") == id) }
            if readOnly { request = request.filter(Column("read") == true) }
            try request.deleteAll(d)
        }
    }

    private func command(_ accountId: String, _ apply: @escaping () async throws -> Void, _ action: String) async -> Outcome<Void> {
        let stored = await store(apply)
        if case .failure = stored { return stored }
        if case .failure(let f) = await run(accountId, action) {
            _ = await refresh(accountId: accountId)
            return .failure(f)
        }
        return .success(())
    }

    private func store(_ write: () async throws -> Void) async -> Outcome<Void> {
        do { try await write(); return .success(()) } catch { return .failure(.storage("Could not store notifications")) }
    }
}
