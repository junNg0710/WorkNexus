import Foundation

/// Ported from: lib/shared/board/domain/value_objects/saved_filter.dart
/// A user-named filter preset — the board's "Save filter". Presets are global (not tied to one board).
public struct SavedFilter: Hashable, Sendable, Identifiable {
    public var id: String
    public var name: String
    public var filter: FilterState
    public var createdAt: Date
    public init(id: String, name: String, filter: FilterState, createdAt: Date) {
        self.id = id; self.name = name; self.filter = filter; self.createdAt = createdAt
    }
}
