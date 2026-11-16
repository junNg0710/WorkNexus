/// ToolGitLab — the GitLab tool module (port of `lib/tools/gitlab`). **Data + Domain layers** (Presentation and
/// the `ToolModule` UI come from a later pass).
///
/// Public entry points:
/// - `GitLabAdapterFactory.make(account:secret:)` / `.makeMergeRequestAdapter(account:secret:)` — account + PAT →
///   `ProviderAdapter` / `GitLabMrAdapter` (wire it into the composition root's `ProviderAdapterRegistry`).
/// - `GitLabMrService` (protocol) + `GitLabMrServiceImpl(GitLabMrServiceDependencies)` — optimistic MR/issue actions.
/// - `GitLabMrAdapter` (protocol) — project items, merge/approve/rebase/draft, reviewers/labels/milestone, time
///   tracking, commits and diffs on top of `ProviderAdapter`.
/// - Use cases: `PostGitLabMrComment`, `CloseGitLabMr`, `ReopenGitLabMr`, `ApproveGitLabMr`, `UnapproveGitLabMr`,
///   `RebaseGitLabMr`, `MergeGitLabMr`, `SetGitLabMrDraft`, `BuildGitLabMrBoard`, `BuildGitLabIssueBoard`,
///   `ComputeGitLabMetrics`.
/// - Value types: `GitLabProjectTree`/`GitLabGroupNode`, `GitLabItemKind`, `GitLabMrColumn`/`GitLabIssueColumn`,
///   `RepoCommit`, `RepoFileChange`, `GitLabSyntheticLabels`, `gitLabPriorityFromLabels(_:)`.
public enum ToolGitLabModule { public static let name = "ToolGitLab" }
