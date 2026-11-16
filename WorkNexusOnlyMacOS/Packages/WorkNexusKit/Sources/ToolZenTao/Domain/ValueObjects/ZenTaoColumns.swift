import CoreDomain
import Foundation

/// Ported from: lib/core/domain/value_objects/{zentao_bug_column,zentao_task_column,zentao_board_status,zentao_module_of}.dart
/// Native ZenTao bug board columns (separate from `UnifiedStatus`: bugs have active/resolved/closed + resolution).
public enum ZenTaoBugColumn: String, CaseIterable, Sendable, Hashable {
    case newUnconfirmed, confirmedToFix, resolvedVerify, postponed, nonFix, closed

    public var order: Int { Self.allCases.firstIndex(of: self)! }
    public static var columns: [ZenTaoBugColumn] { allCases.sorted { $0.order < $1.order } }
    /// Dart `enum.name`.
    public var name: String { rawValue }
}

/// Native ZenTao task board columns.
public enum ZenTaoTaskColumn: String, CaseIterable, Sendable, Hashable {
    case notStarted, inProgress, paused, doneVerify, closed, canceled

    public var order: Int { Self.allCases.firstIndex(of: self)! }
    /// The ZenTao task status view (`execution-task` browse type) holding exactly this column's tasks.
    public var browseType: String {
        switch self {
        case .notStarted: "wait"
        case .inProgress: "doing"
        case .paused: "pause"
        case .doneVerify: "done"
        case .closed: "closed"
        case .canceled: "cancel"
        }
    }
    public static var columns: [ZenTaoTaskColumn] { allCases.sorted { $0.order < $1.order } }
    public var name: String { rawValue }
}

/// Resolution code → label, in ZenTao's order.
public let zentaoBugResolutionLabels: [(code: String, label: String)] = [
    ("fixed", "Fixed"), ("bydesign", "By design"), ("duplicate", "Duplicate"), ("external", "External"),
    ("notrepro", "Irreproducible"), ("willnotfix", "Won't fix"), ("postponed", "Postponed"), ("tostory", "To story"),
]

public let zentaoNonFixResolutionLabels: [(code: String, label: String)] = [
    ("bydesign", "By design"), ("duplicate", "Duplicate"), ("external", "External"),
    ("notrepro", "Irreproducible"), ("willnotfix", "Won't fix"), ("tostory", "To story"),
]

public func zentaoBugResolution(_ ticket: Ticket) -> String {
    for label in ticket.labels {
        let lower = label.lowercased()
        if lower.hasPrefix("resolution:") {
            return String(lower.dropFirst("resolution:".count)).trimmingCharacters(in: .whitespaces)
        }
    }
    return ""
}

public func zentaoBugColumnFor(_ ticket: Ticket) -> ZenTaoBugColumn {
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

public func zentaoTaskColumnFor(_ ticket: Ticket) -> ZenTaoTaskColumn {
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

/// The board column a ZenTao bug or task sits in, by name - the status a table row shows, and what the Status
/// filter matches. Nil for any other ticket.
public func zentaoStatusOf(_ ticket: Ticket) -> String? {
    guard ticket.providerType == .zentao else { return nil }
    switch (ticket.externalType ?? "").lowercased() {
    case "bug": return zentaoBugColumnFor(ticket).name
    case "task": return zentaoTaskColumnFor(ticket).name
    default: return nil
    }
}

/// The ZenTao module (id) a bug or task sits in; nil for any other ticket or one without a module ('0' is
/// ZenTao's "no module", kept as given).
public func zentaoModuleOf(_ ticket: Ticket) -> String? {
    switch ticket.providerEntity {
    case .zentaoBug(let b): return b.module
    case .zentaoTask(let t): return t.module
    default: return nil
    }
}
