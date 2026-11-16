import CoreDomain

/// Ported from: lib/core/domain/value_objects/{zentao_board_status,zentao_bug_column,zentao_task_column,zentao_module_of}.dart
/// and lib/core/util/ticket_open.dart. The shared board's filters read ZenTao's own board columns, so the pure
/// derivations live here (internal to SharedKit; ToolZenTao keeps its own public copy of the column enums).
enum BoardZenTaoBugColumn: String, CaseIterable {
    case newUnconfirmed, confirmedToFix, resolvedVerify, postponed, nonFix, closed
    var order: Int { Self.allCases.firstIndex(of: self)! }
}

enum BoardZenTaoTaskColumn: String, CaseIterable {
    case notStarted, inProgress, paused, doneVerify, closed, canceled
    var order: Int { Self.allCases.firstIndex(of: self)! }
}

/// The resolution of a ZenTao bug, carried on the ticket as a `resolution:<code>` label ("" when none).
func zentaoBugResolution(_ ticket: Ticket) -> String {
    for label in ticket.labels {
        let lower = label.lowercased()
        if lower.hasPrefix("resolution:") { return String(lower.dropFirst("resolution:".count)).trimmingCharacters(in: .whitespaces) }
    }
    return ""
}

func zentaoBugColumnFor(_ ticket: Ticket) -> BoardZenTaoBugColumn {
    let raw = ticket.providerStatus.lowercased()
    let resolution = zentaoBugResolution(ticket)
    if raw == "closed" { return .closed }
    if raw == "resolved" {
        if resolution == "postponed" { return .postponed }
        if resolution == "fixed" || resolution.isEmpty { return .resolvedVerify }
        return .nonFix
    }
    if ticket.status == .inbox { return .newUnconfirmed }
    return .confirmedToFix
}

func zentaoTaskColumnFor(_ ticket: Ticket) -> BoardZenTaoTaskColumn {
    switch ticket.providerStatus.lowercased() {
    case "doing": return .inProgress
    case "pause": return .paused
    case "done": return .doneVerify
    case "closed": return .closed
    case "cancel": return .canceled
    default:
        switch ticket.status {
        case .inprogress: return .inProgress
        case .blocked: return .paused
        case .review: return .doneVerify
        case .done: return .closed
        default: return .notStarted
        }
    }
}

/// The ZenTao board column (as a name) a ticket sits in, or nil for non-ZenTao / unknown types.
func zentaoStatusOf(_ ticket: Ticket) -> String? {
    guard ticket.providerType == .zentao else { return nil }
    switch (ticket.externalType ?? "").lowercased() {
    case "bug": return zentaoBugColumnFor(ticket).rawValue
    case "task": return zentaoTaskColumnFor(ticket).rawValue
    default: return nil
    }
}

func zentaoModuleOf(_ ticket: Ticket) -> String? {
    switch ticket.providerEntity {
    case .zentaoBug(let e): return e.module
    case .zentaoTask(let e): return e.module
    default: return nil
    }
}

private let finishedStatuses: Set<String> = ["done", "closed", "cancel", "resolved"]

/// Whether a ticket still counts as open work for its assignee.
public func isOpenForAssignee(_ t: Ticket) -> Bool {
    t.status != .done && !finishedStatuses.contains(t.providerStatus.trimmingCharacters(in: .whitespaces).lowercased())
}
