import CoreDomain
import Foundation
import GRDB

/// Ported from: lib/core/data/repositories/settings_sync_status_repository.dart
/// The sync status stream of every account (syncing / offline / auth expired / error live in memory) with the one part
/// that must outlive a launch: `lastSyncedAt`, kept in `accountSyncState` (migration `core_v2`). A fresh launch starts each
/// account at `.idle(lastSyncedAt: <the stored time>)`, so "synced 3 h ago" survives a restart.
public final class GRDBSyncStatusRepository: SyncStatusRepository, @unchecked Sendable {
    private let db: AppDatabase
    private let lock = NSLock()
    private var statuses: [String: AccountSyncStatus] = [:]
    private var listeners: [String: [UUID: AsyncStream<AccountSyncStatus>.Continuation]] = [:]

    public init(db: AppDatabase) { self.db = db }

    public func watch(accountId: String) -> AsyncStream<AccountSyncStatus> {
        AsyncStream { cont in
            let id = UUID()
            lock.lock(); listeners[accountId, default: [:]][id] = cont; lock.unlock()
            cont.onTermination = { [weak self] _ in
                self?.lock.lock(); self?.listeners[accountId]?[id] = nil; self?.lock.unlock()
            }
            Task { [weak self] in
                guard let self else { return }
                cont.yield(await self.status(accountId: accountId))
            }
        }
    }

    public func status(accountId: String) async -> AccountSyncStatus {
        if let known = lock.withLock({ statuses[accountId] }) { return known }
        let stored = await storedDate(accountId)
        return lock.withLock {
            if let known = statuses[accountId] { return known }
            let s = AccountSyncStatus.idle(lastSyncedAt: stored)
            statuses[accountId] = s
            return s
        }
    }

    public func report(accountId: String, status: AccountSyncStatus) {
        lock.lock(); statuses[accountId] = status; let ls = Array((listeners[accountId] ?? [:]).values); lock.unlock()
        ls.forEach { $0.yield(status) }
        if case .idle(let at?) = status {
            Task { [db] in
                try? await db.writer.write { d in
                    try d.execute(sql: """
                        INSERT INTO accountSyncState (accountId, lastSyncedAt) VALUES (?, ?)
                        ON CONFLICT(accountId) DO UPDATE SET lastSyncedAt = excluded.lastSyncedAt
                        """, arguments: [accountId, at])
                }
            }
        }
    }

    private func storedDate(_ accountId: String) async -> Date? {
        (try? await db.writer.read { d in
            try Date.fetchOne(d, sql: "SELECT lastSyncedAt FROM accountSyncState WHERE accountId = ?", arguments: [accountId])
        }) ?? nil
    }
}
