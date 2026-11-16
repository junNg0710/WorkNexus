import CoreDomain

/// Ported from: lib/shared/sync/data/merge_detail_labels.dart
/// Merges a detail fetch's labels with the synthetic board-membership labels carried on the already-stored ones.
/// The detail endpoint omits those, so without this a detail refresh would silently drop a ticket from its board.
public func mergeDetailLabels(_ detailLabels: [String], _ existingLabels: [String]) -> [String] {
    detailLabels + existingLabels.filter { SyntheticLabels.isSynthetic($0) && !detailLabels.contains($0) }
}

/// Keeps GitLab label colours across a detail refresh that carries none.
public func preserveLabelColors(_ fresh: TicketProviderEntity?, _ existing: TicketProviderEntity?) -> TicketProviderEntity? {
    if case .gitlabItem(var f)? = fresh, case .gitlabItem(let e)? = existing, f.labelColors.isEmpty, !e.labelColors.isEmpty {
        f.labelColors = e.labelColors; f.labelTextColors = e.labelTextColors
        return .gitlabItem(f)
    }
    return fresh
}
