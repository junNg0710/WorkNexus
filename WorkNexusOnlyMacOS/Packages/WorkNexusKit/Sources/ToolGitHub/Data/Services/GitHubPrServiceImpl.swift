import CoreDomain
import Foundation

/// What `GitHubPrServiceImpl` needs from the composition root. The Dart service reached into `SyncCoordinator`;
/// here the same capabilities arrive as narrow interfaces/closures from `CoreDomain`.
public struct GitHubPrServiceDependencies: Sendable {
    /// Local DB (single source of truth): optimistic writes, rollback and synced rows go through it.
    public var tickets: TicketRepository
    /// Re-fetches ticket + comments + activity into the DB after an action; also posts comments.
    public var ticketDetail: TicketDetailService
    /// Optional: reports syncing / idle / offline / authExpired around repo and "mine" syncs.
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

/// Ported from: lib/tools/github/data/services/github_pr_service_impl.dart
/// Optimistic GitHub actions: the ticket row is updated first, rolled back if the provider call fails, and the
/// detail is refreshed after success (a failed refresh does not undo an action that already landed).
public final class GitHubPrServiceImpl: GitHubPrService, @unchecked Sendable {
    private let deps: GitHubPrServiceDependencies
    public init(_ deps: GitHubPrServiceDependencies) { self.deps = deps }

    private static let noCredentials = Failure.auth("No stored credentials for this account")

    public func postComment(_ ticket: Ticket, body: String) async -> Outcome<Void> {
        await deps.ticketDetail.postComment(ticket: ticket, body: body)
    }

    public func closeGitHubItem(_ ticket: Ticket) async -> Outcome<Void> {
        await action(ticket, optimistic: ticket.with(.done, "closed")) { await $0.closeItem(ticket) }
    }

    public func reopenGitHubItem(_ ticket: Ticket) async -> Outcome<Void> {
        let isPr = (ticket.externalType ?? "").lowercased() == "pullrequest"
        return await action(ticket, optimistic: ticket.with(isPr ? .review : .todo, "open")) { await $0.reopenItem(ticket) }
    }

    public func mergeGitHubPr(_ ticket: Ticket) async -> Outcome<Void> {
        await action(ticket, optimistic: ticket.with(.done, "merged")) { await $0.mergePull(ticket) }
    }

    public func updateGitHubPrBranch(_ ticket: Ticket) async -> Outcome<Void> {
        await action(ticket) { await $0.updateBranch(ticket) }
    }

    // MARK: pass-through actions that refresh the detail (SyncCoordinator.assignTicket / setReviewers)

    public func setReviewers(_ ticket: Ticket, logins: [String]) async -> Outcome<Void> {
        guard let adapter = await prAdapter(ticket.accountId) else { return .failure(Self.noCredentials) }
        if case .failure(let f) = await adapter.setReviewers(ticket, logins: logins) { return .failure(f) }
        return await deps.ticketDetail.refresh(ticket: ticket)
    }

    public func assignTicket(_ ticket: Ticket, assignee: String, comment: String?) async -> Outcome<Void> {
        guard let adapter = await deps.adapter(ticket.accountId) else { return .failure(Self.noCredentials) }
        if case .failure(let f) = await adapter.assignTicket(ticket, assignee: assignee, comment: comment, left: nil) { return .failure(f) }
        return await deps.ticketDetail.refresh(ticket: ticket)
    }

    // MARK: reads

    public func listUsers(_ ticket: Ticket) async -> Outcome<[ProviderUser]> {
        guard let adapter = await deps.adapter(ticket.accountId) else { return .success([]) }
        if let pr = adapter as? GitHubPrAdapter { return await pr.listRepoAssignees(ticket) }
        return await adapter.listUsers()
    }

    public func fetchTicketImage(_ ticket: Ticket, url: String) async -> Data? {
        await deps.adapter(ticket.accountId)?.fetchBytes(url: url, projectPath: nil, projectId: nil)
    }

    public func listPullCommits(_ ticket: Ticket) async -> Outcome<[RepoCommit]> {
        guard let pr = await prAdapter(ticket.accountId) else { return .failure(.auth("No stored GitHub credentials")) }
        return await pr.listPullCommits(ticket)
    }

    public func listPullFiles(_ ticket: Ticket) async -> Outcome<[RepoFileChange]> {
        guard let pr = await prAdapter(ticket.accountId) else { return .failure(.auth("No stored GitHub credentials")) }
        return await pr.listPullFiles(ticket)
    }

    public func listProjects(accountId: String) async -> Outcome<[ProviderProject]> {
        guard let adapter = await deps.adapter(accountId) else { return .failure(Self.noCredentials) }
        return await adapter.listProjects()
    }

    // MARK: sync into the local DB

    public func syncGitHubRepoItems(accountId: String, repoId: String, pullRequests: Bool) async -> Outcome<[String]> {
        await trackSync(accountId) {
            await self.syncSlice(accountId, label: GitHubSyntheticLabels.repo(repoId)) {
                await $0.listRepoItems(repo: repoId, pullRequests: pullRequests)
            }
        }
    }

    public func syncGitHubMine(accountId: String) async -> Outcome<[String]> {
        await trackSync(accountId) {
            await self.syncSlice(accountId, label: GitHubSyntheticLabels.mine(accountId)) { await $0.listMyPullRequests() }
        }
    }

    // MARK: helpers

    private func syncSlice(_ accountId: String, label: String, fetch: (GitHubPrAdapter) async -> Outcome<[Ticket]>) async -> Outcome<[String]> {
        guard await deps.account(accountId) != nil else { return .failure(.auth("GitHub account not found")) }
        guard let pr = await prAdapter(accountId) else { return .failure(Self.noCredentials) }
        switch await fetch(pr) {
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

    private func prAdapter(_ accountId: String) async -> GitHubPrAdapter? { await deps.adapter(accountId) as? GitHubPrAdapter }

    private func action(_ ticket: Ticket, optimistic: Ticket? = nil, _ run: (GitHubPrAdapter) async -> Outcome<Bool>) async -> Outcome<Void> {
        _ = await deps.tickets.upsertTickets([optimistic ?? ticket])
        guard let pr = await prAdapter(ticket.accountId) else {
            _ = await deps.tickets.upsertTickets([ticket])
            return .failure(Self.noCredentials)
        }
        if case .failure(let f) = await run(pr) {
            _ = await deps.tickets.upsertTickets([ticket])   // rollback
            return .failure(f)
        }
        // The action already landed on the server: a failed refresh must not roll the ticket back.
        _ = await deps.ticketDetail.refresh(ticket: ticket)
        return .success(())
    }
}

private extension Ticket {
    func with(_ status: UnifiedStatus, _ providerStatus: String) -> Ticket {
        var t = self; t.status = status; t.providerStatus = providerStatus; return t
    }
}
