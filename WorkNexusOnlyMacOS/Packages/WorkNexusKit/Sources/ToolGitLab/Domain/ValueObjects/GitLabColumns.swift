/// Ported from: lib/tools/gitlab/domain/value_objects/gitlab_issue_column.dart + gitlab_mr_column.dart
/// Native GitLab issue board columns: open, in-progress (an open issue with a "doing/wip" label), closed.
public enum GitLabIssueColumn: Int, Sendable, CaseIterable, Hashable {
    case open = 0, inProgress, closed
    public var order: Int { rawValue }
    public static var columns: [GitLabIssueColumn] { allCases.sorted { $0.order < $1.order } }
}

/// Native GitLab merge-request board columns, following an MR's lifecycle (draft → review → merged / closed).
public enum GitLabMrColumn: Int, Sendable, CaseIterable, Hashable {
    case draft = 0, review, merged, closed
    public var order: Int { rawValue }
    public static var columns: [GitLabMrColumn] { allCases.sorted { $0.order < $1.order } }
}
