/// Ported from: lib/tools/github/domain/value_objects/github_issue_column.dart + github_pr_column.dart
/// Native GitHub issue board columns: open, in-progress (an open issue with a "doing/wip" label), closed.
public enum GitHubIssueColumn: Int, Sendable, CaseIterable, Hashable {
    case open = 0, inProgress, closed
    public var order: Int { rawValue }
    public static var columns: [GitHubIssueColumn] { allCases.sorted { $0.order < $1.order } }
}

/// Native GitHub pull-request board columns, following a PR's lifecycle (draft → review → merged / closed).
public enum GitHubPrColumn: Int, Sendable, CaseIterable, Hashable {
    case draft = 0, review, merged, closed
    public var order: Int { rawValue }
    public static var columns: [GitHubPrColumn] { allCases.sorted { $0.order < $1.order } }
}
