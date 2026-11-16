import CoreDomain

/// Ported from: lib/core/domain/adapters/github_pr_adapter.dart (+ RepoChangesAdapter)
/// The GitHub-specific richness on top of `ProviderAdapter`: repo-scoped boards, issue/PR state changes, PR
/// merge / update-branch, reviewers, and commit/file data for the detail view. (GitHub has no account-wide
/// assignable list and no label/milestone/approve API through a PAT, so only the supported actions exist.)
public protocol GitHubPrAdapter: ProviderAdapter {
    func closeItem(_ ticket: Ticket) async -> Outcome<Bool>
    func reopenItem(_ ticket: Ticket) async -> Outcome<Bool>
    func mergePull(_ ticket: Ticket) async -> Outcome<Bool>
    func updateBranch(_ ticket: Ticket) async -> Outcome<Bool>
    func listRepoItems(repo: String, pullRequests: Bool) async -> Outcome<[Ticket]>
    func listMyPullRequests() async -> Outcome<[Ticket]>
    func listRepoAssignees(_ ticket: Ticket) async -> Outcome<[ProviderUser]>
    func setReviewers(_ ticket: Ticket, logins: [String]) async -> Outcome<Bool>
    func listPullCommits(_ ticket: Ticket) async -> Outcome<[RepoCommit]>
    func listPullFiles(_ ticket: Ticket) async -> Outcome<[RepoFileChange]>
}
