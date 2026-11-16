/// Ported from: lib/tools/github/domain/value_objects/github_item_kind.dart
/// The two GitHub object kinds the dedicated board can show. `externalType` matches the `Ticket.externalType`
/// stamped by `GitHubNormalize`, so the board can filter tickets to one kind.
public enum GitHubItemKind: String, Sendable, CaseIterable {
    case issue
    case pullRequest

    public var externalType: String {
        switch self { case .issue: "Issue"; case .pullRequest: "PullRequest" }
    }
}
