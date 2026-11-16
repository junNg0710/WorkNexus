import CoreDomain
import Foundation

/// Ported from: lib/tools/github/data/repositories/github_adapter.dart
/// GitHub implementation of `ProviderAdapter`, bound to one account. The shared interface is ZenTao-shaped, so
/// the product/execution/bug-resolution methods with no GitHub analogue are no-ops. A PR is an issue with extra
/// fields, so comment/assign/close/reopen all route through the issues endpoints; only merge, update-branch and
/// the rich PR board use `/pulls` (see `GitHubProviderAdapter+PullRequests.swift` for `GitHubPrAdapter`).
public final class GitHubProviderAdapter: ProviderAdapter, @unchecked Sendable {
    let accountId: String
    let client: GitHubClient

    init(accountId: String, client: GitHubClient) {
        self.accountId = accountId
        self.client = client
    }

    public var providerType: ProviderType { .github }

    // MARK: assets

    public func fetchBytes(url: String, projectPath: String?, projectId: String?) async -> Data? {
        (try? await client.fetchBytes(url)) ?? nil
    }

    public func downloadBytes(url: String) async -> Data? {
        await fetchBytes(url: url, projectPath: nil, projectId: nil)
    }

    // Its files need the token as an Authorization header, which would then travel to the CDN a download
    // redirects to: downloaded whole instead (so no stream request).
    public func streamRequest(url: String) async -> MediaRequest? { nil }

    // MARK: ProviderAdapter

    public func testConnection() async -> Outcome<ConnectionCheck> {
        await perform { ConnectionCheck(ok: true, account: try await self.client.currentUser().login) }
    }

    public func listAssignedTickets(sinceCursor: String?) async -> Outcome<TicketPage> {
        await perform {
            // Three independent searches, one round trip of latency.
            async let issues = self.client.assignedIssues()
            async let assigned = self.client.assignedPulls()
            async let reviews = self.client.reviewPulls()
            let (i, a, r) = try await (issues, assigned, reviews)

            // Dedupe by unified ticket id (a PR can be both assigned to me and awaiting my review).
            var byId = OrderedTickets()
            i.forEach { byId.set(normalizeGitHubIssue($0, accountId: self.accountId)) }
            (a + r).forEach { byId.set(normalizeGitHubPullFromIssue($0, accountId: self.accountId)) }
            let tickets = byId.values

            let cursor = sinceCursor.flatMap(parseGitHubDate)
            let filtered = cursor.map { c in tickets.filter { $0.updatedAt.map { $0 > c } ?? true } } ?? tickets
            let maxUpdated = tickets.compactMap(\.updatedAt).max()
            return TicketPage(tickets: filtered, nextCursor: maxUpdated.map(gitHubCursor))
        }
    }

    public func getTicket(_ ticket: Ticket) async -> Outcome<Ticket> {
        await perform {
            let ref = self.repoRef(ticket)
            if self.kind(of: ticket) == .issue {
                return normalizeGitHubIssue(try await self.client.issue(ref, ticket.externalKey), accountId: self.accountId, repoPath: ref)
            }
            return normalizeGitHubPull(try await self.client.pull(ref, ticket.externalKey), accountId: self.accountId, repoPath: ref)
        }
    }

    public func listComments(_ ticket: Ticket) async -> Outcome<[Comment]> {
        await perform {
            try await self.client.issueComments(self.repoRef(ticket), ticket.externalKey).compactMap { n in
                let body = n.body ?? ""
                guard !body.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
                return Comment(id: "\(ticket.id):\(n.id)", ticketId: ticket.id, authorName: n.user?.display ?? "unknown",
                               body: body, createdAt: parseGitHubDate(n.createdAt) ?? Date())
            }
        }
    }

    public func postComment(_ ticket: Ticket, body: String) async -> Outcome<Comment> {
        await perform {
            let note = try await self.client.postIssueComment(self.repoRef(ticket), ticket.externalKey, body)
            return Comment(id: "\(ticket.id):\(note.id)", ticketId: ticket.id, authorName: note.user?.display ?? "You",
                           body: note.body ?? body, createdAt: parseGitHubDate(note.createdAt) ?? Date())
        }
    }

    public func listActivity(_ ticket: Ticket) async -> Outcome<[ActivityEvent]> {
        await perform {
            try await self.client.issueEvents(self.repoRef(ticket), ticket.externalKey).map { e in
                ActivityEvent(id: "\(ticket.id):\(e.id)", ticketId: ticket.id, actor: e.actor?.display ?? "unknown",
                              action: (e.event ?? "updated").replacingOccurrences(of: "_", with: " "),
                              at: parseGitHubDate(e.createdAt) ?? Date())
            }
        }
    }

    // GitHub's assignable users are repo-scoped; the assignee picker resolves them through `listRepoAssignees`.
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
            try await self.client.repos().map { ProviderProject(id: $0.fullName, name: $0.display, accountId: self.accountId) }
        }
    }

    public func assignTicket(_ ticket: Ticket, assignee: String, comment: String?, left: Double?) async -> Outcome<Bool> {
        // GitHub assigns by login string directly — no username→id lookup needed.
        await perform {
            let ref = self.repoRef(ticket)
            try await self.client.updateIssue(ref, ticket.externalKey, assignees: [assignee])
            if let comment, !comment.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                _ = try await self.client.postIssueComment(ref, ticket.externalKey, comment)
            }
            return true
        }
    }

    public func resolveBug(_ ticket: Ticket, resolution: String, resolvedBuild: String?, assignee: String?, comment: String?) async -> Outcome<Bool> {
        .failure(.unexpected("resolveBug is ZenTao-only; GitHub uses close/reopen"))
    }
    public func activateBug(_ ticket: Ticket, openedBuild: String?, assignee: String?, comment: String?) async -> Outcome<Bool> {
        .failure(.unexpected("activateBug is ZenTao-only; GitHub uses close/reopen"))
    }
    public func confirmBug(_ ticket: Ticket, assignee: String?, comment: String?) async -> Outcome<Bool> {
        .failure(.unexpected("confirmBug is ZenTao-only; GitHub has no bug workflow"))
    }

    // MARK: helpers

    func kind(of t: Ticket) -> GitHubKind { (t.externalType ?? "").lowercased() == "pullrequest" ? .pullRequest : .issue }

    /// The `owner/name` repo ref parsed from the ticket's `projectId` (`<accountId>:<owner/name>`), used in
    /// `/repos/:ref/…`. GitHub takes the slash literally, so (unlike GitLab's encoded ref) it is NOT URL-encoded.
    func repoRef(_ ticket: Ticket) -> String {
        let prefix = "\(accountId):"
        return ticket.projectId.hasPrefix(prefix) ? String(ticket.projectId.dropFirst(prefix.count)) : ticket.projectId
    }

    /// Runs `body`, mapping thrown errors to `Failure` like the Dart `_guard`.
    func perform<T>(_ body: () async throws -> T) async -> Outcome<T> {
        do { return .success(try await body()) }
        catch let f as Failure { return .failure(f) }
        catch let GitHubHTTPError.status(code, body) {
            if code == 401 || code == 403 { return .failure(.auth("GitHub authentication failed")) }
            if code == 404 { return .failure(.notFound("GitHub resource not found")) }
            return .failure(.network("GitHub request failed [badResponse]: HTTP \(code) \(body.prefix(200))"))
        }
        catch is CancellationError { return .failure(.cancelled("cancelled")) }
        catch let e as URLError where e.code == .cancelled { return .failure(.cancelled("cancelled")) }
        catch let e as URLError { return .failure(.network("GitHub request failed [\(e.code.rawValue)]: \(e.localizedDescription)")) }
        catch { return .failure(.parse("GitHub response could not be parsed: \(error)")) }
    }
}

/// Insertion-ordered ticket set keyed by id (a later entry replaces the earlier one in place).
struct OrderedTickets {
    private var order: [String] = []
    private var map: [String: Ticket] = [:]
    mutating func set(_ t: Ticket) { if map[t.id] == nil { order.append(t.id) }; map[t.id] = t }
    var values: [Ticket] { order.compactMap { map[$0] } }
}
