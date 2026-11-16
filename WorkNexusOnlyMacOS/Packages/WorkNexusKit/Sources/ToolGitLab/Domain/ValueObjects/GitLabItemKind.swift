/// Ported from: lib/tools/gitlab/domain/value_objects/gitlab_item_kind.dart
/// The two GitLab object kinds the dedicated board can show. `externalType` matches the `Ticket.externalType`
/// stamped by `GitLabNormalize`, so the board can filter tickets to one kind.
public enum GitLabItemKind: String, Sendable, CaseIterable {
    case issue
    case mergeRequest

    public var externalType: String {
        switch self { case .issue: "Issue"; case .mergeRequest: "MergeRequest" }
    }
}
