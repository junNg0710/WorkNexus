import CoreDomain
import Foundation

/// Ported from: lib/core/util/priority_labels.dart (GitHub half) + lib/core/util/synthetic_labels.dart (GitHub half)
///
/// GitHub has no native priority — it is read from a `priority: <level>` / `P1`-style label. The normalizer falls
/// back to `.medium`; the UI uses this nil-returning detector to show a priority tag only for a real label.
public func gitHubPriorityFromLabels(_ labels: [String]) -> Priority? {
    for raw in labels {
        let l = raw.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        let v = l.hasPrefix("priority")
            ? l.replacingOccurrences(of: #"^priority\s*[:/]?\s*"#, with: "", options: .regularExpression)
            : l
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

/// Synthetic board-membership labels the list-sync paths stamp onto a ticket so a native board can scope its
/// tickets from the local DB. The format is a cross-feature contract — always go through these builders.
public enum GitHubSyntheticLabels {
    public static let repoPrefix = "github-repo:"
    public static let minePrefix = "github-mine:"
    public static func repo(_ repoId: String) -> String { "\(repoPrefix)\(repoId)" }
    public static func mine(_ accountId: String) -> String { "\(minePrefix)\(accountId)" }
}
