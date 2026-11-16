import CoreDomain
import CoreTools
import Foundation
import XCTest
@testable import ToolGitHub

/// Interface-boundary fakes for the GitHub presentation tests (no database, no network).
final class PresStore: TicketRepository, WorkspaceRepository, CommentRepository, ActivityRepository, @unchecked Sendable {
    private let lock = NSLock()
    var tickets: [Ticket] = []
    var accounts: [Account] = []
    var comments: [Comment] = []
    var events: [ActivityEvent] = []
    var moves: [(String, UnifiedStatus)] = []

    private func once<T: Sendable>(_ v: T) -> AsyncStream<T> { AsyncStream { $0.yield(v) } }
    func watchTickets() -> AsyncStream<[Ticket]> { once(lock.withLock { tickets }) }
    func ticket(id: String) async -> Outcome<Ticket?> { .success(lock.withLock { tickets.first { $0.id == id } }) }
    func upsertTickets(_ t: [Ticket]) async -> Outcome<Void> { .success(()) }
    func moveTicket(id: String, to status: UnifiedStatus) async -> Outcome<Void> { lock.withLock { moves.append((id, status)) }; return .success(()) }
    func watchWorkspaces() -> AsyncStream<[Workspace]> { once([Workspace(id: "w1", name: "Acme", shortCode: "AC", colorValue: 0xFF3D8DF1)]) }
    func watchAccounts() -> AsyncStream<[Account]> { once(lock.withLock { accounts }) }
    func watchProjects() -> AsyncStream<[Project]> { once([]) }
    func createWorkspace(_ w: Workspace) async -> Outcome<Void> { .success(()) }
    func updateWorkspace(_ w: Workspace) async -> Outcome<Void> { .success(()) }
    func upsertAccount(_ a: Account) async -> Outcome<Void> { .success(()) }
    func deleteAccount(id: String) async -> Outcome<Void> { .success(()) }
    func upsertProjects(_ p: [Project]) async -> Outcome<Void> { .success(()) }
    func watchComments(ticketId: String) -> AsyncStream<[Comment]> { once(lock.withLock { comments.filter { $0.ticketId == ticketId } }) }
    func upsertComments(_ c: [Comment]) async -> Outcome<Void> { .success(()) }
    func watchActivity(ticketId: String) -> AsyncStream<[ActivityEvent]> { once(lock.withLock { events.filter { $0.ticketId == ticketId } }) }
    func upsertActivity(_ e: [ActivityEvent]) async -> Outcome<Void> { .success(()) }
}

final class PresSettings: SettingsRepository, @unchecked Sendable {
    private let lock = NSLock()
    private var value = AppSettings()
    private(set) var saves = 0
    var current: AppSettings { lock.withLock { value } }
    func load() async -> AppSettings { current }
    func save(_ s: AppSettings) async -> Outcome<Void> { lock.withLock { value = s; saves += 1 }; return .success(()) }
    func watch() -> AsyncStream<AppSettings> { let v = current; return AsyncStream { $0.yield(v) } }
}

struct PresSyncStatus: SyncStatusRepository {
    func watch(accountId: String) -> AsyncStream<AccountSyncStatus> { AsyncStream { $0.finish() } }
    func status(accountId: String) async -> AccountSyncStatus { .idle(lastSyncedAt: nil) }
    func report(accountId: String, status: AccountSyncStatus) {}
}

struct PresCredentials: CredentialStore {
    func read(_ key: String) async -> String? { nil }
    func write(_ key: String, value: String) async -> Outcome<Void> { .success(()) }
    func delete(_ key: String) async -> Outcome<Void> { .success(()) }
}

struct PresSync: AccountSyncService, TicketDetailService {
    func sync(accountId: String) async -> Outcome<Void> { .success(()) }
    func adapter(for account: Account) async -> ProviderAdapter? { nil }
    func refresh(ticket: Ticket) async -> Outcome<Void> { .success(()) }
    func postComment(ticket: Ticket, body: String) async -> Outcome<Void> { .success(()) }
}

struct PresRegistry: ProviderAdapterRegistry {
    func createAdapter(account: Account, secret: String) -> ProviderAdapter? { nil }
}

/// A `GitHubPrService` that records every call and answers from `failWith`.
final class PresPrService: GitHubPrService, @unchecked Sendable {
    private let lock = NSLock()
    private var _calls: [String] = []
    var calls: [String] { lock.withLock { _calls } }
    var failWith: Failure?
    var repos: [ProviderProject] = []
    var users: [ProviderUser] = []
    var commits: [RepoCommit] = []
    var files: [RepoFileChange] = []

    private func record(_ s: String) -> Outcome<Void> {
        lock.withLock { _calls.append(s) }
        return failWith.map { .failure($0) } ?? .success(())
    }
    func postComment(_ t: Ticket, body: String) async -> Outcome<Void> { record("comment:\(body)") }
    func closeGitHubItem(_ t: Ticket) async -> Outcome<Void> { record("close:\(t.externalKey)") }
    func reopenGitHubItem(_ t: Ticket) async -> Outcome<Void> { record("reopen:\(t.externalKey)") }
    func mergeGitHubPr(_ t: Ticket) async -> Outcome<Void> { record("merge:\(t.externalKey)") }
    func updateGitHubPrBranch(_ t: Ticket) async -> Outcome<Void> { record("update:\(t.externalKey)") }
    func setReviewers(_ t: Ticket, logins: [String]) async -> Outcome<Void> { record("reviewers:\(logins.joined(separator: ","))") }
    func assignTicket(_ t: Ticket, assignee: String, comment: String?) async -> Outcome<Void> { record("assign:\(assignee):\(comment ?? "-")") }
    func listUsers(_ t: Ticket) async -> Outcome<[ProviderUser]> { .success(users) }
    func fetchTicketImage(_ t: Ticket, url: String) async -> Data? { nil }
    func listPullCommits(_ t: Ticket) async -> Outcome<[RepoCommit]> { .success(commits) }
    func listPullFiles(_ t: Ticket) async -> Outcome<[RepoFileChange]> { .success(files) }
    func syncGitHubRepoItems(accountId: String, repoId: String, pullRequests: Bool) async -> Outcome<[String]> {
        _ = record("slice:\(accountId):\(repoId):\(pullRequests ? "pr" : "issue")"); return failWith.map { .failure($0) } ?? .success([])
    }
    func syncGitHubMine(accountId: String) async -> Outcome<[String]> { _ = record("mine:\(accountId)"); return .success([]) }
    func listProjects(accountId: String) async -> Outcome<[ProviderProject]> {
        lock.withLock { _calls.append("projects:\(accountId)") }
        return failWith.map { .failure($0) } ?? .success(repos)
    }
}

enum PresFixtures {
    static let account = Account(id: "gh-a", workspaceId: "w1", providerType: .github, handle: "octocat", baseUrl: "https://github.com")

    static func pr(_ id: String, key: String? = nil, title: String = "feat: add dashboard", status: UnifiedStatus = .review,
                   providerStatus: String = "open", repo: String = "acme/web", draft: Bool = false, merged: Bool = false,
                   reviewers: [String] = [], reviewerLogins: [String] = [], mergeable: String? = "clean", body: String = "Adds the analytics dashboard.",
                   labels: [String] = ["frontend"], updated: Date? = Date()) -> Ticket {
        Ticket(id: id, accountId: "gh-a", projectId: repo, providerType: .github, externalKey: key ?? id, title: title, body: body,
               priority: .medium, status: status, providerStatus: providerStatus, sourceHash: "h", externalType: "PullRequest",
               labels: labels, assignee: "octocat", url: "https://github.com/\(repo)/pull/\(key ?? id)",
               createdAt: Date().addingTimeInterval(-86_400), updatedAt: updated,
               providerEntity: .githubItem(GitHubItemEntity(repo: repo, author: "octocat", headBranch: "feature/dashboard", baseBranch: "main",
                                                            mergeableState: mergeable, draft: draft, merged: merged,
                                                            reviewers: reviewers, assignees: ["octocat"], reviewerLogins: reviewerLogins)))
    }

    static func issue(_ id: String, title: String = "Crash on start", status: UnifiedStatus = .todo, providerStatus: String = "open",
                      repo: String = "acme/web") -> Ticket {
        Ticket(id: id, accountId: "gh-a", projectId: repo, providerType: .github, externalKey: id, title: title, body: "",
               priority: .medium, status: status, providerStatus: providerStatus, sourceHash: "h", externalType: "Issue",
               assignee: "octocat", updatedAt: Date(), providerEntity: .githubItem(GitHubItemEntity(repo: repo, author: "ana")))
    }

    @MainActor
    static func context(store: PresStore = PresStore(), settings: PresSettings = PresSettings(), service: PresPrService = PresPrService(),
                        registry: ToolRegistry? = nil) -> (GithubContext, PresStore, PresSettings, PresPrService) {
        let sync = PresSync()
        let services = AppServices(tickets: store, workspaces: store, comments: store, activity: store, syncStatus: PresSyncStatus(),
                                   settings: settings, credentials: PresCredentials(), sync: sync, ticketDetail: sync, adapters: PresRegistry())
        let nav = AppNavController { _ in "github.pulls" }
        return (GithubContext(services: services, nav: nav, registry: registry ?? ToolRegistry(), prService: service), store, settings, service)
    }
}
