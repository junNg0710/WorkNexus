import CoreDomain
import Foundation

/// Ported from: lib/core/domain/adapters/gitlab_mr_service.dart
/// Presentation-facing contract for the GitLab issue/MR detail actions. Actions are optimistic (the ticket row is
/// updated first, rolled back on failure) and finish with a detail refresh. Implemented in `Data/Services`.
public protocol GitLabMrService: Sendable {
    func postComment(_ ticket: Ticket, body: String) async -> Outcome<Void>
    func closeGitLabItem(_ ticket: Ticket) async -> Outcome<Void>
    func reopenGitLabItem(_ ticket: Ticket) async -> Outcome<Void>
    func approveGitLabMr(_ ticket: Ticket) async -> Outcome<Void>
    func unapproveGitLabMr(_ ticket: Ticket) async -> Outcome<Void>
    /// Merges `ticket`; a nil option keeps the MR's own setting.
    func mergeGitLabMr(_ ticket: Ticket, squash: Bool?, removeSourceBranch: Bool?) async -> Outcome<Void>
    /// Marks `ticket` as a draft, or as ready for review when `draft` is false.
    func setGitLabMrDraft(_ ticket: Ticket, draft: Bool) async -> Outcome<Void>
    func rebaseGitLabMr(_ ticket: Ticket) async -> Outcome<Void>
    func listUsers(_ ticket: Ticket) async -> Outcome<[ProviderUser]>
    func assignTicket(_ ticket: Ticket, assignee: String, comment: String?) async -> Outcome<Void>
    func setReviewers(_ ticket: Ticket, logins: [String]) async -> Outcome<Void>
    func listGitLabLabels(_ ticket: Ticket) async -> Outcome<[ProviderLabelOption]>
    func setGitLabLabels(_ ticket: Ticket, labels: [String]) async -> Outcome<Void>
    func listGitLabMilestones(_ ticket: Ticket) async -> Outcome<[ProviderMilestoneOption]>
    func setGitLabMilestone(_ ticket: Ticket, milestoneId: Int?) async -> Outcome<Void>
    func updateGitLabTimeTracking(_ ticket: Ticket, estimate: String?, spent: String?, resetEstimate: Bool, resetSpent: Bool) async -> Outcome<Void>
    func fetchTicketImage(_ ticket: Ticket, url: String) async -> Data?
    func listMergeRequestCommits(_ ticket: Ticket) async -> Outcome<[RepoCommit]>
    func listMergeRequestChanges(_ ticket: Ticket) async -> Outcome<[RepoFileChange]>
    /// Fetches a project's issues or MRs into the local DB; returns the written ticket ids.
    func syncGitLabProjectItems(accountId: String, projectId: String, mergeRequests: Bool) async -> Outcome<[String]>
    /// Fetches the account-wide "my merge requests" slice into the local DB; returns the written ticket ids.
    func syncGitLabMine(accountId: String) async -> Outcome<[String]>
    func gitlabServerVersion(accountId: String) async -> String?
    func listProjects(accountId: String) async -> Outcome<[ProviderProject]>
}
