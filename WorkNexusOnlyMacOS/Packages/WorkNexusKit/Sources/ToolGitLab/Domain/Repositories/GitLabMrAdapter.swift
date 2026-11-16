import CoreDomain

/// Ported from: lib/core/domain/adapters/gitlab_mr_adapter.dart (+ RepoChangesAdapter)
/// The GitLab-specific richness on top of `ProviderAdapter`: project-scoped boards, issue/MR state changes,
/// MR merge/approve/rebase, reviewers/labels/milestone/time tracking and commit/diff data for the detail view.
public protocol GitLabMrAdapter: ProviderAdapter {
    func listProjectItems(projectId: String, mergeRequests: Bool) async -> Outcome<[Ticket]>
    func listMyMergeRequests() async -> Outcome<[Ticket]>
    func serverVersion() async -> String?
    func listMergeRequestCommits(_ ticket: Ticket) async -> Outcome<[RepoCommit]>
    func listMergeRequestChanges(_ ticket: Ticket) async -> Outcome<[RepoFileChange]>
    func listProjectMembers(_ ticket: Ticket) async -> Outcome<[ProviderUser]>
    func closeIssue(_ ticket: Ticket) async -> Outcome<Bool>
    func reopenIssue(_ ticket: Ticket) async -> Outcome<Bool>
    func closeMergeRequest(_ ticket: Ticket) async -> Outcome<Bool>
    func reopenMergeRequest(_ ticket: Ticket) async -> Outcome<Bool>
    /// Merges `ticket`; a nil option keeps the MR's own setting.
    func mergeMergeRequest(_ ticket: Ticket, squash: Bool?, removeSourceBranch: Bool?) async -> Outcome<Bool>
    func approveMergeRequest(_ ticket: Ticket) async -> Outcome<Bool>
    func unapproveMergeRequest(_ ticket: Ticket) async -> Outcome<Bool>
    /// Marks `ticket` as a draft, or as ready when `draft` is false.
    func setMergeRequestDraft(_ ticket: Ticket, draft: Bool) async -> Outcome<Bool>
    func rebaseMergeRequest(_ ticket: Ticket) async -> Outcome<Bool>
    func setReviewers(_ ticket: Ticket, logins: [String]) async -> Outcome<Bool>
    func listProjectLabels(_ ticket: Ticket) async -> Outcome<[ProviderLabelOption]>
    func setLabels(_ ticket: Ticket, labels: [String]) async -> Outcome<Bool>
    func listProjectMilestones(_ ticket: Ticket) async -> Outcome<[ProviderMilestoneOption]>
    func setMilestone(_ ticket: Ticket, milestoneId: Int?) async -> Outcome<Bool>
    func updateTimeTracking(_ ticket: Ticket, estimate: String?, spent: String?, resetEstimate: Bool, resetSpent: Bool) async -> Outcome<Bool>
}
