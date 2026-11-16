import Foundation

/// Ported from: lib/core/domain/value_objects/account_sync_status.dart
public enum AccountSyncStatus: Equatable, Sendable {
    case idle(lastSyncedAt: Date?)
    case syncing
    case offline
    case authExpired
    case error(String)
}
