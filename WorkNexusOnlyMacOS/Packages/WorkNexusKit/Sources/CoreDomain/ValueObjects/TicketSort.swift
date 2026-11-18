/// Ported from: lib/core/domain/value_objects/ticket_sort.dart
public enum TicketSortField: String, Codable, CaseIterable, Sendable {
    case id, title, priority, severity, status, assignee, estimate, left, resolution, updated, deadline
    public var startsDescending: Bool { self == .id || self == .updated }
}

public struct TicketSort: Codable, Hashable, Sendable {
    public var field: TicketSortField
    public var descending: Bool
    public init(_ field: TicketSortField, descending: Bool = false) { self.field = field; self.descending = descending }

    public static let newest = TicketSort(.id, descending: true)
    /// The order a Kanban board starts in: most urgent first, then most recently updated (Dart `boardDefaultSort`).
    public static let boardDefault = TicketSort(.priority)

    public func toggled(_ column: TicketSortField) -> TicketSort {
        column == field ? TicketSort(field, descending: !descending) : TicketSort(column, descending: column.startsDescending)
    }
}
