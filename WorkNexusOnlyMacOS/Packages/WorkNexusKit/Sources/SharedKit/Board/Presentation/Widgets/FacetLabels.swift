import CoreDomain
import CoreUI
import SwiftUI

/// Ported from: lib/shared/board/presentation/widgets/facet_labels.dart
func facetHeader(_ kind: BoardFacetKind) -> String {
    switch kind {
    case .status: appString("status", "Status")
    case .resolvedBy: appString("fieldResolvedBy", "Resolved by")
    case .openedBy: appString("openedBy", "Opened by")
    case .confirmed: appString("fieldConfirmation", "Confirmation")
    case .assignee: appString("assignee", "Assignee")
    case .reviewer: appString("reviewers", "Reviewers")
    case .severity: appString("severity", "Severity")
    case .priority: appString("priority", "Priority")
    case .bugType: appString("bugType", "Type")
    case .resolution: appString("resolution", "Resolution")
    case .module: appString("fieldModule", "Module")
    }
}

func facetLabel(_ kind: BoardFacetKind, _ value: String) -> String {
    switch kind {
    case .status, .resolvedBy, .openedBy, .module: value
    case .confirmed: value == "1" ? appString("confirmed", "Confirmed") : appString("bugUnconfirmed", "Not confirmed")
    case .assignee, .reviewer: value.isEmpty ? appString("unassigned", "Unassigned") : value
    case .severity: zentaoSeverityLabel(Int(value)) ?? value
    case .priority: Priority(rawValue: value).map(priorityName) ?? value
    case .bugType: zentaoBugTypeLabel(value) ?? value
    case .resolution: zentaoResolutionLabel(value) ?? value
    }
}

/// The colour dot of a facet option (severity and priority only).
func facetDot(_ p: AppPalette, _ kind: BoardFacetKind, _ value: String) -> Color? {
    switch kind {
    case .severity: p.severityColor(Int(value))
    case .priority: Priority(rawValue: value).map(p.priorityColor)
    default: nil
    }
}

extension BoardController {
    /// Toggles `value` of the facet `kind` (what a chip tap does).
    func toggleFacet(_ kind: BoardFacetKind, _ value: String) {
        switch kind {
        case .status: toggleZenTaoStatus(value)
        case .resolvedBy: toggleResolver(value)
        case .openedBy: toggleReporter(value)
        case .confirmed: toggleConfirmation(value)
        case .assignee: toggleAssignee(value)
        case .reviewer: toggleReviewer(value)
        case .severity: toggleSeverity(Int(value) ?? -1)
        case .priority: if let p = Priority(rawValue: value) { togglePriority(p) }
        case .bugType: toggleBugType(value)
        case .resolution: toggleResolution(value)
        case .module: toggleModule(value)
        }
    }
}
