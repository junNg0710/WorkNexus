import Foundation

/// Ported from: lib/shared/board/domain/usecases/build_saved_filter.dart
/// Makes a named preset from the current filter; a name that matches an existing one (case-insensitively) reuses its id.
public struct BuildSavedFilter: Sendable {
    public init() {}
    public func callAsFunction(name: String, filter: FilterState, existing: [SavedFilter], now: Date) -> SavedFilter? {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty { return nil }
        let lower = trimmed.lowercased()
        let reused = existing.first { $0.name.lowercased() == lower }?.id
        return SavedFilter(id: reused ?? "sf-\(Int(now.timeIntervalSince1970 * 1_000_000))", name: trimmed, filter: filter, createdAt: now)
    }
}

/// Ported from: lib/shared/board/domain/usecases/is_saved_filter_applied.dart
/// Whether `preset` is what `current` shows: its criteria match, ignoring the board scope (workspace) and
/// whatever the preset leaves unset (search, modules, saved view).
public struct IsSavedFilterApplied: Sendable {
    public init() {}
    public func callAsFunction(_ preset: SavedFilter, _ current: FilterState) -> Bool {
        var saved = preset.filter
        saved.workspaceId = current.workspaceId
        if saved.search.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { saved.search = current.search }
        if saved.modules.isEmpty { saved.modules = current.modules }
        if saved.savedView == .all { saved.savedView = current.savedView }
        return saved == current
    }
}
