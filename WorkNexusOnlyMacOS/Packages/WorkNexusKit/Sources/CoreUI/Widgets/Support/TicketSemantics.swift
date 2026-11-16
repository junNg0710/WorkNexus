import CoreDomain
import SwiftUI

/// Ported from: lib/core/theme/semantic.dart, lib/core/util/{labels,priority_labels,zentao_labels}.dart
/// Colour / label derivations for tickets that every board, card and detail panel shares.
public extension AppPalette {
    func statusColor(_ s: UnifiedStatus) -> Color {
        switch s {
        case .inbox: tx3
        case .todo: accent
        case .inprogress: orange
        case .review: violet
        case .blocked: red
        case .done: green
        }
    }
    func priorityColor(_ p: Priority) -> Color {
        switch p { case .urgent: red; case .high: orange; case .medium: yellow; case .low: tx3 }
    }
    func severityColor(_ severity: Int?) -> Color? {
        switch severity { case 1: red; case 2: orange; case 3: yellow; case 4: tx3; default: nil }
    }
    /// `color-mix` of two opaque colours (sRGB lerp): `over` toward `c` by `pct`.
    func mix(_ over: Color, _ c: Color, _ pct: Double) -> Color {
        over.mix(with: c, by: pct, in: .perceptual)
    }
    /// Company tint: the card lightly tinted toward the workspace colour.
    func tintedCard(_ ws: Color, enabled: Bool) -> Color { enabled ? mix(card, ws, 0.08) : card }
    /// Hover fill: the ink at low alpha, a touch more on dark themes.
    var hoverFill: Color { tx.opacity(isDark ? 0.08 : 0.06) }
}

public extension AppTheme {
    /// Whether the flat/outline surface style draws outlines.
    var showOutline: Bool { surface == .outline }
}

public extension AppRadii {
    /// Ticket-card corner (1.25 x the component radius).
    var card: CGFloat { component * 1.25 }
}

public func providerBrandColor(_ p: ProviderType) -> Color {
    switch p {
    case .github: Color(argb: 0xFF6E7681)
    case .gitlab: Color(argb: 0xFFFC6D26)
    case .jira: Color(argb: 0xFF4C9AFF)
    case .zentao: Color(argb: 0xFF3D8DF1)
    }
}

public func priorityLabel(_ prov: ProviderType, _ p: Priority) -> String {
    let lv = p.level
    switch prov {
    case .github: return "P\(lv)"
    case .gitlab: return "priority::\(lv + 1)"
    case .jira: return "◆ " + ["Highest", "High", "Medium", "Low"][lv]
    case .zentao: return "Pri \(lv + 1)"
    }
}

/// `#12`, `Bug #12`, `PROJ-12`.
public func ticketRef(_ prov: ProviderType, _ key: String, _ type: String?) -> String {
    switch prov { case .jira: key; case .zentao: "\(type ?? "") #\(key)"; default: "#\(key)" }
}
public func ticketShortRef(_ prov: ProviderType, _ key: String) -> String { prov == .jira ? key : "#\(key)" }

/// Column / status name (l10n keys `colInbox` ... `colDone`).
public func statusLabel(_ s: UnifiedStatus) -> String {
    switch s {
    case .inbox: appString("colInbox", "Inbox")
    case .todo: appString("colTodo", "To do")
    case .inprogress: appString("colInprogress", "In progress")
    case .review: appString("colReview", "Review")
    case .blocked: appString("colBlocked", "Blocked")
    case .done: appString("colDone", "Done")
    }
}

public func priorityName(_ p: Priority) -> String {
    switch p {
    case .urgent: appString("priorityUrgent", "Urgent")
    case .high: appString("priorityHigh", "High")
    case .medium: appString("priorityMedium", "Medium")
    case .low: appString("priorityLow", "Low")
    }
}

/// Labels to show as tags: synthetic membership markers, `resolution:` and `priority::` labels removed.
public func visibleUserLabels(_ labels: [String]) -> [String] {
    labels.filter {
        let l = $0.lowercased()
        return !$0.hasPrefix("zentao-") && !$0.hasPrefix("gitlab-project:") && !$0.hasPrefix("gitlab-mine:")
            && !$0.hasPrefix("github-repo:") && !$0.hasPrefix("github-mine:")
            && !l.hasPrefix("resolution:") && !l.hasPrefix("priority::")
    }
}

/// GitLab label colours (background / text hex) carried on the ticket, or empty.
public func labelColorsOf(_ t: Ticket) -> (background: [String: String], text: [String: String]) {
    if case .gitlabItem(let g)? = t.providerEntity { return (g.labelColors, g.labelTextColors) }
    return ([:], [:])
}

public func gitLabPriorityFromLabels(_ labels: [String]) -> Priority? {
    for raw in labels {
        let l = raw.lowercased().trimmingCharacters(in: .whitespaces)
        guard l.hasPrefix("priority::") else { continue }
        switch l.dropFirst("priority::".count).trimmingCharacters(in: .whitespaces) {
        case "urgent", "critical", "1": return .urgent
        case "high", "2": return .high
        case "medium", "normal", "3": return .medium
        case "low", "4": return .low
        default: continue
        }
    }
    return nil
}

public func gitHubPriorityFromLabels(_ labels: [String]) -> Priority? {
    for raw in labels {
        var v = raw.lowercased().trimmingCharacters(in: .whitespaces)
        if v.hasPrefix("priority") {
            v = v.replacingOccurrences(of: #"^priority\s*[:/]?\s*"#, with: "", options: .regularExpression)
        }
        switch v {
        case "urgent", "critical", "p0", "p1", "1": return .urgent
        case "high", "p2", "2": return .high
        case "medium", "normal", "p3", "3": return .medium
        case "low", "p4", "4": return .low
        default: continue
        }
    }
    return nil
}

/// Whether the provider states a priority for this ticket (GitLab/GitHub only when labelled).
public func hasExplicitPriority(_ t: Ticket) -> Bool {
    switch t.providerType {
    case .zentao, .jira: true
    case .gitlab: gitLabPriorityFromLabels(t.labels) != nil
    case .github: gitHubPriorityFromLabels(t.labels) != nil
    }
}

public func zentaoSeverityLabel(_ severity: Int?) -> String? {
    switch severity { case 1: "Critical"; case 2: "Major"; case 3: "Minor"; case 4: "Trivial"; default: nil }
}

private let bugTypes: [String: String] = [
    "codeerror": "Code error", "config": "Config", "install": "Installation", "security": "Security",
    "performance": "Performance", "standard": "Standard", "automation": "Automation", "designdefect": "Design defect",
    "interface": "Interface", "designchange": "Design change", "others": "Others",
]
private let taskTypes: [String: String] = [
    "design": "Design", "devel": "Development", "request": "Feature request", "test": "Testing", "study": "Research",
    "discuss": "Discussion", "ui": "UI", "affair": "Transaction", "misc": "Misc",
]
private let resolutions: [String: String] = [
    "bydesign": "By design", "duplicate": "Duplicate", "external": "External", "fixed": "Fixed",
    "notrepro": "Irreproducible", "willnotfix": "Won't fix", "postponed": "Postponed", "tostory": "Converted to story",
]
private func capitalized(_ code: String) -> String { code.prefix(1).uppercased() + code.dropFirst() }

public func zentaoBugTypeLabel(_ type: String?) -> String? {
    guard let code = type?.trimmingCharacters(in: .whitespaces).lowercased(), !code.isEmpty else { return nil }
    return bugTypes[code] ?? capitalized(code)
}
public func zentaoTaskTypeLabel(_ type: String?) -> String? {
    guard let code = type?.trimmingCharacters(in: .whitespaces).lowercased(), !code.isEmpty else { return nil }
    return taskTypes[code] ?? capitalized(code)
}
public func zentaoResolutionLabel(_ resolution: String?) -> String? {
    guard let raw = resolution?.trimmingCharacters(in: .whitespaces), !raw.isEmpty else { return nil }
    return resolutions[raw.lowercased()] ?? raw
}

/// "1.5 MB" style size, or nil for a missing / negative size.
public func formatFileSize(_ bytes: Int?) -> String? {
    guard let bytes, bytes >= 0 else { return nil }
    if bytes < 1024 { return "\(bytes) B" }
    let units = ["KB", "MB", "GB", "TB"]
    var size = Double(bytes) / 1024, unit = 0
    while size >= 1024, unit < units.count - 1 { size /= 1024; unit += 1 }
    return String(format: size >= 100 ? "%.0f %@" : "%.1f %@", size, units[unit])
}
