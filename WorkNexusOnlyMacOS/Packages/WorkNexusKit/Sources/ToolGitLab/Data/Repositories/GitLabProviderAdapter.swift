import CoreDomain
import Foundation

/// Ported from: lib/tools/gitlab/data/repositories/gitlab_adapter.dart
/// GitLab implementation of `ProviderAdapter`, bound to one account. The shared interface is ZenTao-shaped, so
/// the product/execution/bug-resolution methods with no GitLab analogue are no-ops. GitLab richness lives in
/// `GitLabMrAdapter` (see `GitLabProviderAdapter+MergeRequests.swift`).
public final class GitLabProviderAdapter: ProviderAdapter, @unchecked Sendable {
    let accountId: String
    let client: GitLabClient
    /// How often `rebaseMergeRequest` checks on GitLab's background rebase.
    let rebasePollInterval: Duration
    /// Polls before giving up waiting on a rebase (about a minute by default).
    static let rebasePollLimit = 60
    private let notes = GitLabNotesCache()

    init(accountId: String, client: GitLabClient, rebasePollInterval: Duration = .seconds(1)) {
        self.accountId = accountId
        self.client = client
        self.rebasePollInterval = rebasePollInterval
    }

    public var providerType: ProviderType { .gitlab }

    // MARK: assets

    public func fetchBytes(url: String, projectPath: String?, projectId: String?) async -> Data? {
        (try? await client.fetchBytes(url, projectPath: projectPath, projectId: projectId.flatMap { Int($0) })) ?? nil
    }

    public func downloadBytes(url: String) async -> Data? {
        await fetchBytes(url: url, projectPath: nil, projectId: nil)
    }

    // Its files need the token as an Authorization header, which would then travel to the CDN a download
    // redirects to: downloaded whole instead (so no stream request).
    public func streamRequest(url: String) async -> MediaRequest? { nil }

    // MARK: ProviderAdapter

    public func testConnection() async -> Outcome<ConnectionCheck> {
        await perform { ConnectionCheck(ok: true, account: try await self.client.currentUser().username) }
    }

    public func listAssignedTickets(sinceCursor: String?) async -> Outcome<TicketPage> {
        await perform {
            // Independent requests go out together; the review list waits only for the username.
            async let issues = self.client.assignedIssues()
            async let assignedMrs = self.client.assignedMergeRequests()
            async let me = self.client.currentUser()
            let (i, a, user) = try await (issues, assignedMrs, me)
            var reviews: [GitLabMergeRequest] = []
            if let username = user.username { reviews = try await self.client.reviewMergeRequests(username: username) }

            // Dedupe by unified ticket id (an MR can be both assigned to me and awaiting my review).
            var byId = OrderedTickets()
            i.forEach { byId.set(normalizeGitLabIssue($0, accountId: self.accountId)) }
            (a + reviews).forEach { byId.set(normalizeGitLabMergeRequest($0, accountId: self.accountId)) }
            let tickets = byId.values

            let cursor = sinceCursor.flatMap(parseGitLabDate)
            let filtered = cursor.map { c in tickets.filter { $0.updatedAt.map { $0 > c } ?? true } } ?? tickets
            let maxUpdated = tickets.compactMap(\.updatedAt).max()
            return TicketPage(tickets: filtered, nextCursor: maxUpdated.map(gitLabCursor))
        }
    }

    public func getTicket(_ ticket: Ticket) async -> Outcome<Ticket> {
        // A detail refresh starts here: drop notes kept from an earlier one, or the pooled adapter would serve
        // them for the rest of the session.
        await notes.invalidate(ticket.id)
        return await perform {
            let ref = self.projectRef(ticket)
            if self.kind(of: ticket) == .issue {
                return normalizeGitLabIssue(try await self.client.issue(ref, ticket.externalKey), accountId: self.accountId)
            }
            let mr = try await self.client.mergeRequest(ref, ticket.externalKey)
            async let behind = self.withCommitsBehind(ref, mr)
            async let approvals = self.approvals(ref, mr)
            var merged = try await behind
            merged.approvals = try await approvals
            return normalizeGitLabMergeRequest(merged, accountId: self.accountId)
        }
    }

    public func listComments(_ ticket: Ticket) async -> Outcome<[Comment]> {
        await perform {
            try await self.cachedNotes(ticket).compactMap { n in
                // System notes are activity rows, not comment bubbles.
                let body = n.body ?? ""
                guard !n.system, !body.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
                return Comment(id: "\(ticket.id):\(n.id)", ticketId: ticket.id, authorName: n.author?.display ?? "unknown",
                               body: body, createdAt: parseGitLabDate(n.createdAt) ?? Date())
            }
        }
    }

    public func postComment(_ ticket: Ticket, body: String) async -> Outcome<Comment> {
        await perform {
            let ref = self.projectRef(ticket)
            let note = self.kind(of: ticket) == .issue
                ? try await self.client.postIssueNote(ref, ticket.externalKey, body)
                : try await self.client.postMrNote(ref, ticket.externalKey, body)
            return Comment(id: "\(ticket.id):\(note.id)", ticketId: ticket.id, authorName: note.author?.display ?? "You",
                           body: note.body ?? body, createdAt: parseGitLabDate(note.createdAt) ?? Date())
        }
    }

    public func listActivity(_ ticket: Ticket) async -> Outcome<[ActivityEvent]> {
        await perform {
            // Only system notes describe activity (assigned, closed, …); user comments render via `listComments`.
            try await self.cachedNotes(ticket).filter(\.system).map { n in
                let summary = gitLabActivitySummary(n.body ?? "")
                return ActivityEvent(id: "\(ticket.id):\(n.id)", ticketId: ticket.id, actor: n.author?.display ?? "unknown",
                                     action: summary.isEmpty ? "updated" : summary, at: parseGitLabDate(n.createdAt) ?? Date())
            }
        }
    }

    // The interface is account-scoped, but GitLab's assignable users are project-scoped and `GET /users` is
    // instance-wide: the assignee picker resolves project members through `listProjectMembers` instead.
    public func listUsers() async -> Outcome<[ProviderUser]> { .success([]) }
    public func listProducts() async -> Outcome<[ProviderProduct]> { .success([]) }
    public func listProductBugs(productId: String, browseType: String?) async -> Outcome<TicketPage> { .success(TicketPage(tickets: [])) }
    public func listProductBugsPage(productId: String, browseType: String, page: Int, limit: Int,
                                    sort: TicketSort, cancel: CancelSignal?) async -> Outcome<ViewPage> {
        .success(ViewPage(tickets: [], total: 0, hasMore: false))
    }
    public func listProjectExecutions(projectId: String) async -> Outcome<[ProviderExecution]> { .success([]) }
    public func listExecutionTasksPage(executionId: String, browseType: String, page: Int, limit: Int,
                                       sort: TicketSort, cancel: CancelSignal?) async -> Outcome<ViewPage> {
        .success(ViewPage(tickets: [], total: 0, hasMore: false))
    }

    public func listProjects() async -> Outcome<[ProviderProject]> {
        await perform {
            try await self.client.projects().map { ProviderProject(id: "\($0.id)", name: $0.display, accountId: self.accountId) }
        }
    }

    public func assignTicket(_ ticket: Ticket, assignee: String, comment: String?, left: Double?) async -> Outcome<Bool> {
        // Resolve the assignee login → numeric id (what `assignee_ids` expects).
        let userRes = await perform { try await self.client.userByUsername(assignee) }
        switch userRes {
        case .failure(let f): return .failure(f)
        case .success(let user):
            guard let id = user?.id else { return .failure(.notFound("No GitLab user \"\(assignee)\"")) }
            return await perform {
                let ref = self.projectRef(ticket)
                if self.kind(of: ticket) == .issue { try await self.client.updateIssue(ref, ticket.externalKey, assigneeIds: [id]) }
                else { try await self.client.updateMergeRequest(ref, ticket.externalKey, assigneeIds: [id]) }
                if let comment, !comment.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    if self.kind(of: ticket) == .issue { _ = try await self.client.postIssueNote(ref, ticket.externalKey, comment) }
                    else { _ = try await self.client.postMrNote(ref, ticket.externalKey, comment) }
                }
                return true
            }
        }
    }

    public func resolveBug(_ ticket: Ticket, resolution: String, resolvedBuild: String?, assignee: String?, comment: String?) async -> Outcome<Bool> {
        .failure(.unexpected("resolveBug is ZenTao-only; GitLab uses close/reopen"))
    }
    public func activateBug(_ ticket: Ticket, openedBuild: String?, assignee: String?, comment: String?) async -> Outcome<Bool> {
        .failure(.unexpected("activateBug is ZenTao-only; GitLab uses close/reopen"))
    }
    public func confirmBug(_ ticket: Ticket, assignee: String?, comment: String?) async -> Outcome<Bool> {
        .failure(.unexpected("confirmBug is ZenTao-only; GitLab has no bug workflow"))
    }

    // MARK: helpers

    /// Issue/MR notes shared within one detail refresh (comments and activity are the same paginated notes read
    /// two ways); dropped shortly after and by `getTicket`. A failed fetch is not kept.
    private func cachedNotes(_ ticket: Ticket) async throws -> [GitLabNote] {
        let ref = projectRef(ticket)
        let isIssue = kind(of: ticket) == .issue
        let client = self.client, key = ticket.externalKey
        return try await notes.notes(for: ticket.id) {
            isIssue ? try await client.issueNotes(ref, key) : try await client.mrNotes(ref, key)
        }
    }

    /// Best effort: the behind-count only hints at a needed rebase, so it never fails the MR itself. A
    /// merged/closed MR needs no rebase and often has its source branch deleted (compare answers 404).
    private func withCommitsBehind(_ projectRef: String, _ mr: GitLabMergeRequest) async throws -> GitLabMergeRequest {
        guard mr.state == "opened", let source = mr.sourceBranch, !source.isEmpty, let target = mr.targetBranch, !target.isEmpty else { return mr }
        var out = mr
        do { out.commitsBehind = try await client.commitsBehindTarget(projectRef, sourceBranch: source, targetBranch: target) }
        catch is GitLabHTTPError { return mr }
        catch is URLError { return mr }
        return out
    }

    /// The MR's approval state, or nil where the endpoint is unavailable (older/restricted instance).
    private func approvals(_ projectRef: String, _ mr: GitLabMergeRequest) async throws -> GitLabMrApprovals? {
        do { return try await client.mergeRequestApprovals(projectRef, "\(mr.iid)") }
        catch is GitLabHTTPError { return nil }
        catch is URLError { return nil }
    }

    func kind(of t: Ticket) -> GitLabKind { (t.externalType ?? "").lowercased() == "mergerequest" ? .mergeRequest : .issue }

    /// The URL-encoded project ref (`group%2Fweb` or a numeric id) parsed from the ticket's `projectId`
    /// (`<accountId>:<path>`), used in `/projects/:ref/…`.
    func projectRef(_ ticket: Ticket) -> String {
        let prefix = "\(accountId):"
        let path = ticket.projectId.hasPrefix(prefix) ? String(ticket.projectId.dropFirst(prefix.count)) : ticket.projectId
        return GitLabClient.encodeSegment(path)
    }

    /// Runs `body`, mapping thrown errors to `Failure` like the Dart `_guard`.
    func perform<T>(_ body: () async throws -> T) async -> Outcome<T> {
        do { return .success(try await body()) }
        catch let f as Failure { return .failure(f) }
        catch let GitLabHTTPError.status(code, body) {
            if code == 401 || code == 403 { return .failure(.auth("GitLab authentication failed")) }
            if code == 404 { return .failure(.notFound("GitLab resource not found")) }
            return .failure(.network("GitLab request failed [badResponse]: HTTP \(code) \(body.prefix(200))"))
        }
        catch is CancellationError { return .failure(.cancelled("cancelled")) }
        catch let e as URLError where e.code == .cancelled { return .failure(.cancelled("cancelled")) }
        catch let e as URLError { return .failure(.network("GitLab request failed [\(e.code.rawValue)]: \(e.localizedDescription)")) }
        catch { return .failure(.parse("GitLab response could not be parsed: \(error)")) }
    }
}

/// Insertion-ordered ticket set keyed by id (a later entry replaces the earlier one in place).
struct OrderedTickets {
    private var order: [String] = []
    private var map: [String: Ticket] = [:]
    mutating func set(_ t: Ticket) { if map[t.id] == nil { order.append(t.id) }; map[t.id] = t }
    var values: [Ticket] { order.compactMap { map[$0] } }
}

/// Shares one in-flight/fresh notes request per ticket for a few seconds (see `cachedNotes`).
actor GitLabNotesCache {
    private var tasks: [String: Task<[GitLabNote], Error>] = [:]

    func notes(for key: String, fetch: @escaping @Sendable () async throws -> [GitLabNote]) async throws -> [GitLabNote] {
        if let pending = tasks[key] { return try await pending.value }
        let task = Task { try await fetch() }
        tasks[key] = task
        do {
            let value = try await task.value
            Task { [weak self] in
                try? await Task.sleep(for: .seconds(4))
                await self?.drop(key, task)
            }
            return value
        } catch {
            drop(key, task)
            throw error
        }
    }

    func invalidate(_ key: String) { tasks[key] = nil }
    private func drop(_ key: String, _ task: Task<[GitLabNote], Error>) { if tasks[key] == task { tasks[key] = nil } }
}
