import CoreDomain

/// Ported from: lib/shared/board/domain/repositories/saved_filter_repository.dart
/// Storage for the board's named filter presets (local-first: the DB is the source of truth and the UI watches it).
public protocol SavedFilterRepository: Sendable {
    /// All presets, newest first, re-emitted on every change.
    func watchSavedFilters() -> AsyncStream<[SavedFilter]>
    /// Inserts `filter`, or replaces the preset with the same id.
    func upsert(_ filter: SavedFilter) async -> Outcome<Void>
    func delete(id: String) async -> Outcome<Void>
}
