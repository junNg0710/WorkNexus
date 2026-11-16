import CoreDomain

/// Ported from: lib/features/connections/domain/repositories/local_cache_repository.dart
/// The device's copy of server-synced data.
public protocol LocalCacheRepository: Sendable {
    /// Deletes the cached data of `sections`; it downloads again on next sync.
    func clear(_ sections: Set<CacheSection>) async -> Outcome<Void>
}
