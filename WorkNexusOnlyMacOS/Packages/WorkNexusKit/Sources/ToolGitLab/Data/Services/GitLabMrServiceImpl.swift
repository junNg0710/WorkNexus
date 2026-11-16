import CoreDomain
import Foundation

/// What `GitLabMrServiceImpl` needs from the composition root. The Dart service reached into `SyncCoordinator`;
/// here the same capabilities arrive as narrow interfaces/closures from `CoreDomain`.
public struct GitLabMrServiceDependencies: Sendable {
    /// Local DB (single source of truth): optimistic writes, rollback and synced rows go through it.
    public var tickets: TicketRepository
    /// Re-fetches ticket + comments + activity into the DB after an action; also posts comments.
    public var ticketDetail: TicketDetailService
    /// Optional: reports syncing / idle / offline / authExpired around project and "mine" syncs.
    public var syncStatus: SyncStatusRepository?
    /// The pooled adapter for an account id (nil when its secret is missing).
    public var adapter: @Sendable (_ accountId: String) async -> ProviderAdapter?
    /// The stored account for an id.
    public var account: @Sendable (_ accountId: String) async -> Account?

    public init(tickets: TicketRepository, ticketDetail: TicketDetailService, syncStatus: SyncStatusRepository? = nil,
                adapter: @escaping @Sendable (String) async -> ProviderAdapter?,
                account: @escaping @Sendable (String) async -> Account?) {
        self.tickets = tickets; self.ticketDetail = ticketDetail; self.syncStatus = syncStatus
        self.adapter = adapter; self.account = account
    }
}

/// Ported from: lib/tools/gitlab/data/services/gitlab_mr_service_impl.dart
/// Optimistic GitLab actions: the ticket row is updated first, rolled back if the provider call fails, and the
/// detail is refreshed after success.
public final class GitLabMrServiceImpl: GitLabMrService, @unchecked Sendable {
    private let deps: GitLabMrServiceDependencies
    public init(_ deps: GitLabMrServiceDependencies) { self.deps = deps }

    private static let noCredentials = Failure.auth("No stored credentials for this account")

    public func postComment(_ ticket: Ticket, body: String) async -> Outcome<Void> {
        await deps.ticketDetail.postComment(ticket: ticket, body: body)
    }

    public func closeGitLabItem(_ ticket: Ticket) async -> Outcome<Void> {
        let isMr = isMergeRequest(ticket)
        return await action(ticket, optimistic: ticket.with(.done, "closed")) { isMr ? await $0.closeMergeRequest(ticket) : await $0.closeIssue(ticket) }
    }

    public func reopenGitLabItem(_ ticket: Ticket) async -> Outcome<Void> {
        let isMr = isMergeRequest(ticket)
        return await action(ticket, optimistic: ticket.with(isMr ? .review : .todo, "opened")) { isMr ? await $0.reopenMergeRequest(ticket) : await $0.reopenIssue(ticket) }
    }

    public func mergeGitLabMr(_ ticket: Ticket, squash: Bool?, removeSourceBranch: Bool?) async -> Outcome<Void> {
        await action(ticket, optimistic: ticket.with(.done, "merged")) {
            await $0.mergeMergeRequest(ticket, squash: squash, removeSourceBranch: removeSourceBranch)
        }
    }

    public func approveGitLabMr(_ ticket: Ticket) async -> Outcome<Void> { await action(ticket) { await $0.approveMergeRequest(ticket) } }
    public func unapproveGitLabMr(_ ticket: Ticket) async -> Outcome<Void> { await action(ticket) { await $0.unapproveMergeRequest(ticket) } }
    public func rebaseGitLabMr(_ ticket: Ticket) async -> Outcome<Void> { await action(ticket) { await $0.rebaseMergeRequest(ticket) } }

    public func setGitLabMrDraft(_ ticket: Ticket, draft: Bool) async -> Outcome<Void> {
        await action(ticket, optimistic: ticket.with(draft ? .inprogress : .review, draft ? "draft" : "opened")) {
            await $0.setMergeRequestDraft(ticket, draft: draft)
        }
    }

    public func setGitLabLabels(_ ticket: Ticket, labels: [String]) async -> Outcome<Void> { await action(ticket) { await $0.setLabels(ticket, labels: labels) } }
    public func setGitLabMilestone(_ ticket: Ticket, milestoneId: Int?) async -> Outcome<Void> { await action(ticket) { await $0.setMilestone(ticket, milestoneId: milestoneId) } }

    public func updateGitLabTimeTracking(_ ticket: Ticket, estimate: String?, spent: String?, resetEstimate: Bool, resetSpent: Bool) async -> Outcome<Void> {
        await action(ticket) {
            await $0.updateTimeTracking(ticket, estimate: estimate, spent: spent, resetEstimate: resetEstimate, resetSpent: resetSpent)
        }
    }

    // MARK: pass-through actions that refresh the detail (SyncCoordinator.assignTicket / setReviewers)

    public func assignTicket(_ ticket: Ticket, assignee: String, comment: String?) async -> Outcome<Void> {
        guard let adapter = await deps.adapter(ticket.accountId) else { return .failure(Self.noCredentials) }
        if case .failure(let f) = await adapter.assignTicket(ticket, assignee: assignee, comment: comment, left: nil) { return .failure(f) }
        return await deps.ticketDetail.refresh(ticket: ticket)
    }

    public func setReviewers(_ ticket: Ticket, logins: [String]) async -> Outcome<Void> {
        guard let adapter = await deps.adapter(ticket.accountId) else { return .failure(Self.noCredentials) }
        guard let mr = adapter as? GitLabMrAdapter else { return .failure(.unexpected("Reviewers are GitLab/GitHub only")) }
        if case .failure(let f) = await mr.setReviewers(ticket, logins: logins) { return .failure(f) }
        return await deps.ticketDetail.refresh(ticket: ticket)
    }

    // MARK: reads

    public func listUsers(_ ticket: Ticket) async -> Outcome<[ProviderUser]> {
        guard let adapter = await deps.adapter(ticket.accountId) else { return .success([]) }
        if let mr = adapter as? GitLabMrAdapter { return await mr.listProjectMembers(ticket) }
        return await adapter.listUsers()
    }

    public func listGitLabLabels(_ ticket: Ticket) async -> Outcome<[ProviderLabelOption]> {
        guard let mr = await mrAdapter(ticket.accountId) else { return .failure(.auth("No stored GitLab credentials")) }
        return await mr.listProjectLabels(ticket)
    }

    public func listGitLabMilestones(_ ticket: Ticket) async -> Outcome<[ProviderMilestoneOption]> {
        guard let mr = await mrAdapter(ticket.accountId) else { return .failure(.auth("No stored GitLab credentials")) }
        return await mr.listProjectMilestones(ticket)
    }

    public func listMergeRequestCommits(_ ticket: Ticket) async -> Outcome<[RepoCommit]> {
        guard let mr = await mrAdapter(ticket.accountId) else { return .failure(.auth("No stored GitLab credentials")) }
        return await mr.listMergeRequestCommits(ticket)
    }

    public func listMergeRequestChanges(_ ticket: Ticket) async -> Outcome<[RepoFileChange]> {
        guard let mr = await mrAdapter(ticket.accountId) else { return .failure(.auth("No stored GitLab credentials")) }
        return await mr.listMergeRequestChanges(ticket)
    }

    /// Fetches an inline image through the account's adapter (project path/id resolve `/uploads/…` links).
    public func fetchTicketImage(_ ticket: Ticket, url: String) async -> Data? {
        var projectPath: String?, projectId: String?
        if case .gitlabItem(let e)? = ticket.providerEntity { projectPath = e.projectPath; projectId = e.projectId.map(String.init) }
        return await deps.adapter(ticket.accountId)?.fetchBytes(url: url, projectPath: projectPath, projectId: projectId)
    }

    public func gitlabServerVersion(accountId: String) async -> String? { await mrAdapter(accountId)?.serverVersion() }

    public func listProjects(accountId: String) async -> Outcome<[ProviderProject]> {
        guard let adapter = await deps.adapter(accountId) else { return .failure(Self.noCredentials) }
        return await adapter.listProjects()
    }

    // MARK: sync into the local DB

    public func syncGitLabProjectItems(accountId: String, projectId: String, mergeRequests: Bool) async -> Outcome<[String]> {
        await trackSync(accountId) {
            await self.syncSlice(accountId, label: GitLabSyntheticLabels.project(projectId)) {
                await $0.listProjectItems(projectId: projectId, mergeRequests: mergeRequests)
            }
        }
    }

    public func syncGitLabMine(accountId: String) async -> Outcome<[String]> {
        await trackSync(accountId) {
            await self.syncSlice(accountId, label: GitLabSyntheticLabels.mine(accountId)) { await $0.listMyMergeRequests() }
        }
    }

    // MARK: helpers

    private func syncSlice(_ accountId: String, label: String, fetch: (GitLabMrAdapter) async -> Outcome<[Ticket]>) async -> Outcome<[String]> {
        guard await deps.account(accountId) != nil else { return .failure(.auth("GitLab account not found")) }
        guard let mr = await mrAdapter(accountId) else { return .failure(Self.noCredentials) }
        switch await fetch(mr) {
        case .failure(let f): return .failure(f)
        case .success(let items):
            let tagged = items.map { t -> Ticket in var c = t; c.labels += [label]; return c }
            if case .failure(let f) = await deps.tickets.upsertTickets(tagged) { return .failure(f) }
            return .success(tagged.map(\.id))
        }
    }

    /// Reports the account's sync status around `run` (syncing → idle / offline / authExpired / error).
    private func trackSync<T>(_ accountId: String, _ run: () async -> Outcome<T>) async -> Outcome<T> {
        guard let repo = deps.syncStatus else { return await run() }
        repo.report(accountId: accountId, status: .syncing)
        let result = await run()
        switch result {
        case .success: repo.report(accountId: accountId, status: .idle(lastSyncedAt: Date()))
        case .failure(let f):
            switch f {
            case .auth: repo.report(accountId: accountId, status: .authExpired)
            case .network: repo.report(accountId: accountId, status: .offline)
            default: repo.report(accountId: accountId, status: .error(f.message))
            }
        }
        return result
    }

    private func mrAdapter(_ accountId: String) async -> GitLabMrAdapter? { await deps.adapter(accountId) as? GitLabMrAdapter }
    private func isMergeRequest(_ t: Ticket) -> Bool { (t.externalType ?? "").lowercased() == "mergerequest" }

    private func action(_ ticket: Ticket, optimistic: Ticket? = nil, _ run: (GitLabMrAdapter) async -> Outcome<Bool>) async -> Outcome<Void> {
        _ = await deps.tickets.upsertTickets([optimistic ?? ticket])
        guard let mr = await mrAdapter(ticket.accountId) else {
            _ = await deps.tickets.upsertTickets([ticket])
            return .failure(Self.noCredentials)
        }
        if case .failure(let f) = await run(mr) {
            _ = await deps.tickets.upsertTickets([ticket])   // rollback
            return .failure(f)
        }
        return await deps.ticketDetail.refresh(ticket: ticket)
    }
}

private extension Ticket {
    func with(_ status: UnifiedStatus, _ providerStatus: String) -> Ticket {
        var t = self; t.status = status; t.providerStatus = providerStatus; return t
    }
}
