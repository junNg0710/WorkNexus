/// ToolGitHub — the GitHub tool module (port of `lib/tools/github`). **Data + Domain layers** (Presentation and
/// the `ToolModule` UI come from a later pass).
///
/// Public entry points:
/// - `GitHubAdapterFactory.make(account:secret:)` / `.makePullRequestAdapter(account:secret:)` — account + PAT →
///   `ProviderAdapter` / `GitHubPrAdapter` (wire it into the composition root's `ProviderAdapterRegistry`).
/// - `GitHubPrService` (protocol) + `GitHubPrServiceImpl(GitHubPrServiceDependencies)` — optimistic PR/issue actions.
/// - `GitHubPrAdapter` (protocol) — repo items, close/reopen, merge, update-branch, reviewers, assignees, commits
///   and changed files on top of `ProviderAdapter`.
/// - Use cases: `PostGitHubComment`, `CloseGitHubItem`, `ReopenGitHubItem`, `MergeGitHubPr`, `UpdateGitHubPrBranch`,
///   `BuildGitHubPrBoard`, `BuildGitHubIssueBoard`, `ComputeGitHubMetrics`.
/// - Value types: `GitHubItemKind`, `GitHubPrColumn`/`GitHubIssueColumn`, `RepoCommit`, `RepoFileChange`,
///   `GitHubSyntheticLabels`, `gitHubPriorityFromLabels(_:)`.
public enum ToolGitHubModule { public static let name = "ToolGitHub" }
