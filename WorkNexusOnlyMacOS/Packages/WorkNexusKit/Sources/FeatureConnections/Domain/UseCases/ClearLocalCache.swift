import CoreDomain

/// Ported from: lib/features/connections/domain/usecases/clear_local_cache.dart
public struct ClearLocalCache: Sendable {
    private let repository: LocalCacheRepository
    public init(_ repository: LocalCacheRepository) { self.repository = repository }

    /// Nothing picked is nothing to do.
    public func callAsFunction(_ sections: Set<CacheSection>) async -> Outcome<Void> {
        sections.isEmpty ? .success(()) : await repository.clear(sections)
    }
}
