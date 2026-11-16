import Foundation

/// Ported from: lib/tools/zentao/data/mappers/zentao_normalize.dart (ZenTaoType),
/// lib/core/domain/value_objects/zentao_ticket_id.dart
/// ZenTao object kinds we import.
public enum ZenTaoType: String, Sendable, CaseIterable, Hashable {
    case bug, task, story

    public var label: String {
        switch self { case .bug: "Bug"; case .task: "Task"; case .story: "Story" }
    }
    /// `bug|task|story`
    public var pathSegment: String { rawValue }
    /// REST v1 collection name (`bugs`, `tasks`, `stories`).
    public var plural: String {
        switch self { case .bug: "bugs"; case .task: "tasks"; case .story: "stories" }
    }
}

/// The local id of ZenTao `type` (`bug`, `task`, `story`) `id` of `accountId`. Bugs, tasks and stories number
/// independently, so the type is part of the id: bug #6492 and task #6492 are different tickets.
public func zenTaoTicketId(accountId: String, type: String, id: String) -> String {
    "\(accountId):\(type.lowercased()):\(id)"
}

/// Synthetic board-membership labels (lib/core/util/synthetic_labels.dart, ZenTao part): internal markers the
/// list-sync paths stamp onto a `Ticket` so a native board can scope its tickets from the local DB.
public func zentaoProductLabel(_ productId: String) -> String { "zentao-product:\(productId)" }
public func zentaoExecutionLabel(_ executionId: String) -> String { "zentao-execution:\(executionId)" }
