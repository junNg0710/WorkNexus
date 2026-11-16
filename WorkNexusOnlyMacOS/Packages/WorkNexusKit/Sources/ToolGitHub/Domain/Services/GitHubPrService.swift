import CoreDomain
import Foundation

/// Ported from: lib/core/domain/adapters/github_pr_service.dart
/// Presentation-facing contract for the GitHub issue/PR detail actions, mirroring `GitLabMrService`. Actions are
/// optimistic (row updated first, rolled back on failure) and finish with a detail refresh. Implemented in
/// `Data/Services`.
public protocol GitHubPrService: Sendable {
    func postComment(_ ticket: Ticket, body: String) async -> Outcome<Void>
    func closeGitHubItem(_ ticket: Ticket) async -> Outcome<Void>
    func reopenGitHubItem(_ ticket: Ticket) async -> Outcome<Void>
    func mergeGitHubPr(_ ticket: Ticket) async -> Outcome<Void>
    func updateGitHubPrBranch(_ ticket: Ticket) async -> Outcome<Void>
    func setReviewers(_ ticket: Ticket, logins: [String]) async -> Outcome<Void>
    func assignTicket(_ ticket: Ticket, assignee: String, comment: String?) async -> Outcome<Void>
    func listUsers(_ ticket: Ticket) async -> Outcome<[ProviderUser]>
    func fetchTicketImage(_ ticket: Ticket, url: String) async -> Data?
    func listPullCommits(_ ticket: Ticket) async -> Outcome<[RepoCommit]>
    func listPullFiles(_ ticket: Ticket) async -> Outcome<[RepoFileChange]>
    /// Fetches a repo's issues or PRs into the local DB; returns the written ticket ids.
    func syncGitHubRepoItems(accountId: String, repoId: String, pullRequests: Bool) async -> Outcome<[String]>
    /// Fetches the account-wide "my pull requests" slice into the local DB; returns the written ticket ids.
    func syncGitHubMine(accountId: String) async -> Outcome<[String]>
    func listProjects(accountId: String) async -> Outcome<[ProviderProject]>
}
