import CoreDomain

/// Ported from: lib/features/workspace_overview/domain/value_objects/dashboard_item_kind.dart
/// What a dashboard work item is. Bugs, tasks and stories are ZenTao tickets that open in the detail panel; todos are
/// personal and have no detail view. The enum itself is the hoisted `ZenTaoDashboardItemKind` (CoreDomain).
public typealias DashboardItemKind = ZenTaoDashboardItemKind

public extension ZenTaoDashboardItemKind {
    /// Whether the item can be loaded as a ticket (detail panel).
    var isTicket: Bool { self != .todo }

    /// The kind behind a ZenTao `objectType` code, or nil for other objects (projects, docs...).
    static func fromObjectType(_ type: String?) -> ZenTaoDashboardItemKind? {
        switch type?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
        case "task": .task
        case "bug": .bug
        case "story": .story
        case "todo": .todo
        default: nil
        }
    }
}
