import CoreDomain
import Foundation

/// Ported from: shared/sync status repository (in-memory stream; `lastSyncedAt` is persisted by the sync layer).
public final class InMemorySyncStatusRepository: SyncStatusRepository, @unchecked Sendable {
    private let lock = NSLock()
    private var statuses: [String: AccountSyncStatus] = [:]
    private var listeners: [String: [UUID: AsyncStream<AccountSyncStatus>.Continuation]] = [:]
    public init() {}

    public func watch(accountId: String) -> AsyncStream<AccountSyncStatus> {
        AsyncStream { cont in
            let id = UUID()
            lock.lock(); listeners[accountId, default: [:]][id] = cont; let cur = statuses[accountId]; lock.unlock()
            cont.yield(cur ?? .idle(lastSyncedAt: nil))
            cont.onTermination = { [weak self] _ in
                self?.lock.lock(); self?.listeners[accountId]?[id] = nil; self?.lock.unlock()
            }
        }
    }
    public func status(accountId: String) async -> AccountSyncStatus {
        lock.withLock { statuses[accountId] ?? .idle(lastSyncedAt: nil) }
    }
    public func report(accountId: String, status: AccountSyncStatus) {
        lock.lock(); statuses[accountId] = status; let ls = Array((listeners[accountId] ?? [:]).values); lock.unlock()
        ls.forEach { $0.yield(status) }
    }
}
