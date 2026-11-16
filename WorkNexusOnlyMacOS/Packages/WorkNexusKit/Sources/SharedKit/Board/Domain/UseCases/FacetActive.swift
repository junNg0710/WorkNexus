import CoreDomain

/// Ported from: lib/shared/board/presentation/widgets/facet_labels.dart (`facetActive`, pure part)
/// Whether `value` of the facet `kind` is selected in `f`.
public func facetActive(_ f: FilterState, _ kind: BoardFacetKind, _ value: String) -> Bool {
    switch kind {
    case .status: f.zentaoStatuses.contains(value)
    case .resolvedBy: f.resolvers.contains(value)
    case .openedBy: f.reporters.contains(value)
    case .confirmed: f.confirmations.contains(value)
    case .assignee: f.assignees.contains(value)
    case .reviewer: f.reviewers.contains(value)
    case .severity: f.severities.contains(Int(value) ?? -1)
    case .priority: Priority(rawValue: value).map { f.priorities.contains($0) } ?? false
    case .bugType: f.bugTypes.contains(value)
    case .resolution: f.resolutions.contains(value)
    case .module: f.modules.contains(value)
    }
}
