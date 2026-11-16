import CoreDomain
import Foundation

/// Ported from: lib/core/util/priority_labels.dart (GitLab half) + lib/core/util/synthetic_labels.dart (GitLab half)
///
/// GitLab has no native priority — it is read from a scoped `priority::<level>` label. The normalizer falls
/// back to `.medium`; the UI uses this nil-returning detector to show a priority tag only for a real label.
public func gitLabPriorityFromLabels(_ labels: [String]) -> Priority? {
    for raw in labels {
        let l = raw.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        guard l.hasPrefix("priority::") else { continue }
        switch l.dropFirst("priority::".count).trimmingCharacters(in: .whitespacesAndNewlines) {
        case "urgent", "critical", "1": return .urgent
        case "high", "2": return .high
        case "medium", "normal", "3": return .medium
        case "low", "4": return .low
        default: continue
        }
    }
    return nil
}

/// Synthetic board-membership labels the list-sync paths stamp onto a ticket so a native board can scope its
/// tickets from the local DB. The format is a cross-feature contract — always go through these builders.
public enum GitLabSyntheticLabels {
    public static let projectPrefix = "gitlab-project:"
    public static let minePrefix = "gitlab-mine:"
    public static func project(_ projectId: String) -> String { "\(projectPrefix)\(projectId)" }
    public static func mine(_ accountId: String) -> String { "\(minePrefix)\(accountId)" }
}
