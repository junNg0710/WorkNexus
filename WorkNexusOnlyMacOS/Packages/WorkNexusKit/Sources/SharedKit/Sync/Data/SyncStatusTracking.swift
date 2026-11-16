import CoreDomain
import Foundation

/// Ported from: lib/shared/sync/data/sync_status_tracking.dart
/// Runs `action` (a sync for `accountId`) and reports the account's sync status around it — syncing, then
/// idle / offline / authExpired / error — so the auth-expired banner and the integration rows follow it.
public func trackSyncStatus<T: Sendable>(_ repo: SyncStatusRepository?, accountId: String,
                                         _ action: () async -> Outcome<T>) async -> Outcome<T> {
    guard let repo else { return await action() }
    repo.report(accountId: accountId, status: .syncing)
    let result = await action()
    switch result {
    case .success: repo.report(accountId: accountId, status: .idle(lastSyncedAt: Date()))
    case .failure(let f):
        switch f {
        case .auth: repo.report(accountId: accountId, status: .authExpired)
        case .network: repo.report(accountId: accountId, status: .offline)
        default: repo.report(accountId: accountId, status: .error(f.message))
        }
    }
    return result
}
