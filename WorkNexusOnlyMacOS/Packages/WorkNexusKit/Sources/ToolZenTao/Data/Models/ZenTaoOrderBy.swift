import CoreDomain
import Foundation

/// Ported from: lib/tools/zentao/data/models/zentao_order_by.dart
/// `sort` as the `orderBy` slot of ZenTao's classic task / bug list URLs (`pri_asc`, `lastEditedDate_desc`...).
/// A field the list cannot sort by (a bug's hours, a task's severity) falls back to the id.
public func zentaoOrderBy(_ sort: TicketSort, bug: Bool) -> String {
    let field: String
    switch sort.field {
    case .id: field = "id"
    case .title: field = bug ? "title" : "name"
    case .priority: field = "pri"
    case .severity: field = bug ? "severity" : "id"
    case .status: field = "status"
    case .assignee: field = "assignedTo"
    case .estimate: field = bug ? "id" : "estimate"
    case .left: field = bug ? "id" : "left"
    case .resolution: field = bug ? "resolution" : "id"
    case .updated: field = "lastEditedDate"
    case .deadline: field = "deadline"
    }
    return "\(field)_\(sort.descending ? "desc" : "asc")"
}
