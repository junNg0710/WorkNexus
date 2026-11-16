import CoreDomain
import CoreTools
import Foundation
import XCTest
@testable import ToolGitLab

/// Interface-boundary fakes for the GitLab presentation tests (no database, no network).
final class GLPresStore: TicketRepository, WorkspaceRepository, CommentRepository, ActivityRepository, @unchecked Sendable {
    private let lock = NSLock()
    var tickets: [Ticket] = []
    var accounts: [Account] = []
    var comments: [Comment] = []
    var events: [ActivityEvent] = []

    private func once<T: Sendable>(_ v: T) -> AsyncStream<T> { AsyncStream { $0.yield(v) } }
    func watchTickets() -> AsyncStream<[Ticket]> { once(lock.withLock { tickets }) }
    func ticket(id: String) async -> Outcome<Ticket?> { .success(lock.withLock { tickets.first { $0.id == id } }) }
    func upsertTickets(_ t: [Ticket]) async -> Outcome<Void> { .success(()) }
    func moveTicket(id: String, to status: UnifiedStatus) async -> Outcome<Void> { .success(()) }
    func watchWorkspaces() -> AsyncStream<[Workspace]> { once([Workspace(id: "w1", name: "Acme", shortCode: "AC", colorValue: 0xFFFC6D26)]) }
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

final class GLPresSettings: SettingsRepository, @unchecked Sendable {
    private let lock = NSLock()
    private var value = AppSettings()
    var current: AppSettings { lock.withLock { value } }
    func load() async -> AppSettings { current }
    func save(_ s: AppSettings) async -> Outcome<Void> { lock.withLock { value = s }; return .success(()) }
    func watch() -> AsyncStream<AppSettings> { let v = current; return AsyncStream { $0.yield(v) } }
}

struct GLPresSyncStatus: SyncStatusRepository {
    func watch(accountId: String) -> AsyncStream<AccountSyncStatus> { AsyncStream { $0.finish() } }
    func status(accountId: String) async -> AccountSyncStatus { .idle(lastSyncedAt: nil) }
    func report(accountId: String, status: AccountSyncStatus) {}
}

struct GLPresCredentials: CredentialStore {
    func read(_ key: String) async -> String? { nil }
    func write(_ key: String, value: String) async -> Outcome<Void> { .success(()) }
    func delete(_ key: String) async -> Outcome<Void> { .success(()) }
}

struct GLPresSync: AccountSyncService, TicketDetailService {
    func sync(accountId: String) async -> Outcome<Void> { .success(()) }
    func adapter(for account: Account) async -> ProviderAdapter? { nil }
    func refresh(ticket: Ticket) async -> Outcome<Void> { .success(()) }
    func postComment(ticket: Ticket, body: String) async -> Outcome<Void> { .success(()) }
}

struct GLPresRegistry: ProviderAdapterRegistry {
    func createAdapter(account: Account, secret: String) -> ProviderAdapter? { nil }
}

/// A `GitLabMrService` that records every call and answers from `failWith`.
final class GLPresMrService: GitLabMrService, @unchecked Sendable {
    private let lock = NSLock()
    private var _calls: [String] = []
    var calls: [String] { lock.withLock { _calls } }
    var failWith: Failure?
    var projects: [ProviderProject] = []
    var users: [ProviderUser] = []
    var labels: [ProviderLabelOption] = []
    var milestones: [ProviderMilestoneOption] = []
    var commits: [RepoCommit] = []
    var files: [RepoFileChange] = []

    private func record(_ s: String) -> Outcome<Void> {
        lock.withLock { _calls.append(s) }
        return failWith.map { .failure($0) } ?? .success(())
    }
    func postComment(_ t: Ticket, body: String) async -> Outcome<Void> { record("comment:\(body)") }
    func closeGitLabItem(_ t: Ticket) async -> Outcome<Void> { record("close:\(t.externalKey)") }
    func reopenGitLabItem(_ t: Ticket) async -> Outcome<Void> { record("reopen:\(t.externalKey)") }
    func approveGitLabMr(_ t: Ticket) async -> Outcome<Void> { record("approve:\(t.externalKey)") }
    func unapproveGitLabMr(_ t: Ticket) async -> Outcome<Void> { record("unapprove:\(t.externalKey)") }
    func mergeGitLabMr(_ t: Ticket, squash: Bool?, removeSourceBranch: Bool?) async -> Outcome<Void> {
        record("merge:\(t.externalKey):squash=\(squash.map(String.init) ?? "-"):remove=\(removeSourceBranch.map(String.init) ?? "-")")
    }
    func setGitLabMrDraft(_ t: Ticket, draft: Bool) async -> Outcome<Void> { record("draft:\(t.externalKey):\(draft)") }
    func rebaseGitLabMr(_ t: Ticket) async -> Outcome<Void> { record("rebase:\(t.externalKey)") }
    func listUsers(_ t: Ticket) async -> Outcome<[ProviderUser]> { .success(users) }
    func assignTicket(_ t: Ticket, assignee: String, comment: String?) async -> Outcome<Void> { record("assign:\(assignee):\(comment ?? "-")") }
    func setReviewers(_ t: Ticket, logins: [String]) async -> Outcome<Void> { record("reviewers:\(logins.joined(separator: ","))") }
    func listGitLabLabels(_ t: Ticket) async -> Outcome<[ProviderLabelOption]> { .success(labels) }
    func setGitLabLabels(_ t: Ticket, labels: [String]) async -> Outcome<Void> { record("labels:\(labels.joined(separator: ","))") }
    func listGitLabMilestones(_ t: Ticket) async -> Outcome<[ProviderMilestoneOption]> { .success(milestones) }
    func setGitLabMilestone(_ t: Ticket, milestoneId: Int?) async -> Outcome<Void> { record("milestone:\(milestoneId.map(String.init) ?? "-")") }
    func updateGitLabTimeTracking(_ t: Ticket, estimate: String?, spent: String?, resetEstimate: Bool, resetSpent: Bool) async -> Outcome<Void> {
        record("time:\(estimate ?? "-"):\(spent ?? "-"):\(resetEstimate):\(resetSpent)")
    }
    func fetchTicketImage(_ t: Ticket, url: String) async -> Data? { nil }
    func listMergeRequestCommits(_ t: Ticket) async -> Outcome<[RepoCommit]> { .success(commits) }
    func listMergeRequestChanges(_ t: Ticket) async -> Outcome<[RepoFileChange]> { .success(files) }
    func syncGitLabProjectItems(accountId: String, projectId: String, mergeRequests: Bool) async -> Outcome<[String]> {
        _ = record("slice:\(accountId):\(projectId):\(mergeRequests ? "mr" : "issue")"); return failWith.map { .failure($0) } ?? .success([])
    }
    func syncGitLabMine(accountId: String) async -> Outcome<[String]> { _ = record("mine:\(accountId)"); return .success([]) }
    func gitlabServerVersion(accountId: String) async -> String? { nil }
    func listProjects(accountId: String) async -> Outcome<[ProviderProject]> {
        lock.withLock { _calls.append("projects:\(accountId)") }
        return failWith.map { .failure($0) } ?? .success(projects)
    }
}

enum GLPresFixtures {
    static let account = Account(id: "gl-a", workspaceId: "w1", providerType: .gitlab, handle: "jdoe", baseUrl: "https://gitlab.example.com")

    static func mr(_ id: String, key: String? = nil, title: String = "feat: add dashboard", status: UnifiedStatus = .review,
                   providerStatus: String = "opened", projectId: Int = 12, path: String = "icom/web/app", draft: Bool = false,
                   reviewers: [String] = [], assigneeLogins: [String] = [], mergeStatus: String? = "can_be_merged", behind: Int? = nil,
                   approvedBy: [String] = [], body: String = "Adds the analytics dashboard.", labels: [String] = ["frontend"],
                   updated: Date? = Date()) -> Ticket {
        Ticket(id: id, accountId: "gl-a", projectId: path, providerType: .gitlab, externalKey: key ?? id, title: title, body: body,
               priority: .medium, status: status, providerStatus: providerStatus, sourceHash: "h", externalType: "MergeRequest",
               labels: labels, assignee: "ana", url: "https://gitlab.example.com/\(path)/-/merge_requests/\(key ?? id)",
               createdAt: Date().addingTimeInterval(-86_400), updatedAt: updated,
               providerEntity: .gitlabItem(GitLabItemEntity(
                   projectPath: path, projectId: projectId, author: "ana", sourceBranch: "feature/dashboard", targetBranch: "main",
                   mergeStatus: mergeStatus, commitsBehind: behind, draft: draft, changedFiles: 3, milestoneTitle: "v1.2",
                   humanTimeEstimate: "2h", humanTotalTimeSpent: "30m", approvedBy: approvedBy, approvalsRequired: 1,
                   approvalsLeft: approvedBy.isEmpty ? 1 : 0, userHasApproved: false, userCanApprove: true, reviewers: reviewers,
                   assignees: ["ana"], assigneeLogins: assigneeLogins, labelColors: ["frontend": "#428BCA"], labelTextColors: ["frontend": "#FFFFFF"])))
    }

    static func issue(_ id: String, title: String = "Crash on start", status: UnifiedStatus = .todo, providerStatus: String = "opened",
                      projectId: Int = 12, path: String = "icom/web/app") -> Ticket {
        Ticket(id: id, accountId: "gl-a", projectId: path, providerType: .gitlab, externalKey: id, title: title, body: "",
               priority: .medium, status: status, providerStatus: providerStatus, sourceHash: "h", externalType: "Issue",
               assignee: "ana", updatedAt: Date(),
               providerEntity: .gitlabItem(GitLabItemEntity(projectPath: path, projectId: projectId, author: "ana", assignees: ["ana"], assigneeLogins: ["ana"])))
    }

    @MainActor
    static func context(store: GLPresStore = GLPresStore(), settings: GLPresSettings = GLPresSettings(), service: GLPresMrService = GLPresMrService(),
                        registry: ToolRegistry? = nil) -> (GitlabContext, GLPresStore, GLPresSettings, GLPresMrService) {
        let sync = GLPresSync()
        let services = AppServices(tickets: store, workspaces: store, comments: store, activity: store, syncStatus: GLPresSyncStatus(),
                                   settings: settings, credentials: GLPresCredentials(), sync: sync, ticketDetail: sync, adapters: GLPresRegistry())
        let nav = AppNavController { _ in "gitlab.mrs" }
        return (GitlabContext(services: services, nav: nav, registry: registry ?? ToolRegistry(), mrService: service), store, settings, service)
    }
}
