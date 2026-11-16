/// Ported from: lib/core/util/synthetic_labels.dart
/// Synthetic board-membership labels: internal markers the list-sync paths stamp onto a `Ticket` so a native board can
/// scope its tickets from the local DB (offline). The label *format* is a cross-module contract — sync writes it,
/// boards read it — so both sides go through the builders here. These labels are machinery, never shown as tags.
public enum SyntheticLabels {
    /// Prefixes of every synthetic membership label (a detail refresh must preserve them; card views strip them).
    public static let prefixes: [String] = [
        "zentao-product:", "zentao-execution:", "gitlab-project:", "github-repo:", "gitlab-mine:", "github-mine:",
    ]
    public static func gitlabProject(_ projectId: String) -> String { "gitlab-project:\(projectId)" }
    public static func gitlabMine(_ accountId: String) -> String { "gitlab-mine:\(accountId)" }
    public static func githubRepo(_ repoId: String) -> String { "github-repo:\(repoId)" }
    public static func githubMine(_ accountId: String) -> String { "github-mine:\(accountId)" }
    public static func zentaoProduct(_ productId: String) -> String { "zentao-product:\(productId)" }
    public static func zentaoExecution(_ executionId: String) -> String { "zentao-execution:\(executionId)" }
    public static func isSynthetic(_ label: String) -> Bool { prefixes.contains { label.hasPrefix($0) } }
    /// Labels to render as tags (synthetic markers removed).
    public static func visible(_ labels: [String]) -> [String] { labels.filter { !isSynthetic($0) } }
}
