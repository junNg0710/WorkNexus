import CoreDomain
import Foundation
@testable import SharedKit

/// In-memory fakes of the CoreDomain repositories that count writes (tests mock at the interface boundary).
final class FakeStore: TicketRepository, WorkspaceRepository, CommentRepository, ActivityRepository, CredentialStore, @unchecked Sendable {
    private let lock = NSLock()
    var tickets: [String: Ticket] = [:]
    var accounts: [String: Account] = [:]
    var projects: [String: Project] = [:]
    var comments: [String: Comment] = [:]
    var events: [String: ActivityEvent] = [:]
    var secrets: [String: String] = [:]
    var ticketWrites = 0, accountWrites = 0, projectWrites = 0, commentWrites = 0, activityWrites = 0

    private func once<T>(_ v: T) -> AsyncStream<T> { AsyncStream { $0.yield(v); $0.finish() } }

    func watchTickets() -> AsyncStream<[Ticket]> { once(Array(tickets.values)) }
    func ticket(id: String) async -> Outcome<Ticket?> { .success(tickets[id]) }
    func upsertTickets(_ list: [Ticket]) async -> Outcome<Void> {
        lock.withLock { ticketWrites += list.count; for t in list { tickets[t.id] = StoredForm.ticket(t) } }   // the database stores millisecond dates
        return .success(())
    }
    func moveTicket(id: String, to status: UnifiedStatus) async -> Outcome<Void> { tickets[id]?.status = status; return .success(()) }

    func watchWorkspaces() -> AsyncStream<[Workspace]> { once([]) }
    func watchAccounts() -> AsyncStream<[Account]> { once(Array(accounts.values)) }
    func watchProjects() -> AsyncStream<[Project]> { once(Array(projects.values)) }
    func createWorkspace(_ workspace: Workspace) async -> Outcome<Void> { .success(()) }
    func updateWorkspace(_ workspace: Workspace) async -> Outcome<Void> { .success(()) }
    func upsertAccount(_ account: Account) async -> Outcome<Void> { lock.withLock { accountWrites += 1; accounts[account.id] = account }; return .success(()) }
    func deleteAccount(id: String) async -> Outcome<Void> { accounts[id] = nil; return .success(()) }
    func upsertProjects(_ list: [Project]) async -> Outcome<Void> { lock.withLock { projectWrites += list.count; for p in list { projects[p.id] = p } }; return .success(()) }

    func watchComments(ticketId: String) -> AsyncStream<[Comment]> { once(comments.values.filter { $0.ticketId == ticketId }.sorted { $0.id < $1.id }) }
    func upsertComments(_ list: [Comment]) async -> Outcome<Void> { lock.withLock { commentWrites += 1; for c in list { comments[c.id] = StoredForm.comment(c) } }; return .success(()) }
    func watchActivity(ticketId: String) -> AsyncStream<[ActivityEvent]> { once(events.values.filter { $0.ticketId == ticketId }.sorted { $0.id < $1.id }) }
    func upsertActivity(_ list: [ActivityEvent]) async -> Outcome<Void> { lock.withLock { activityWrites += 1; for e in list { events[e.id] = StoredForm.activity(e) } }; return .success(()) }

    func read(_ key: String) async -> String? { secrets[key] }
    func write(_ key: String, value: String) async -> Outcome<Void> { secrets[key] = value; return .success(()) }
    func delete(_ key: String) async -> Outcome<Void> { secrets[key] = nil; return .success(()) }
}

/// A scripted adapter: counts list calls, returns canned tickets / comments / activity, optionally with a delay.
final class FakeAdapter: ProviderAdapter, @unchecked Sendable {
    let providerType: ProviderType = .zentao
    private let lock = NSLock()
    var assigned: [Ticket] = []
    var detail: Ticket?
    var comments: [Comment] = []
    var activity: [ActivityEvent] = []
    var delay: Duration = .zero
    var listCalls = 0
    var imageBytes: Data?
    var imageCalls = 0
    var failure: Failure?

    func testConnection() async -> Outcome<ConnectionCheck> { .success(ConnectionCheck(ok: true)) }
    func listAssignedTickets(sinceCursor: String?) async -> Outcome<TicketPage> {
        lock.withLock { listCalls += 1 }
        try? await Task.sleep(for: delay)
        if let failure { return .failure(failure) }
        return .success(TicketPage(tickets: assigned))
    }
    func getTicket(_ ticket: Ticket) async -> Outcome<Ticket> { .success(detail ?? ticket) }
    func listComments(_ ticket: Ticket) async -> Outcome<[Comment]> { .success(comments) }
    func postComment(_ ticket: Ticket, body: String) async -> Outcome<Comment> {
        .success(Comment(id: "new", ticketId: ticket.id, authorName: "me", body: body, createdAt: Date()))
    }
    func listActivity(_ ticket: Ticket) async -> Outcome<[ActivityEvent]> { .success(activity) }
    func listUsers() async -> Outcome<[ProviderUser]> { .success([]) }
    func assignTicket(_ ticket: Ticket, assignee: String, comment: String?, left: Double?) async -> Outcome<Bool> { .success(true) }
    func fetchBytes(url: String, projectPath: String?, projectId: String?) async -> Data? {
        lock.withLock { imageCalls += 1 }
        return imageBytes
    }
    func downloadBytes(url: String) async -> Data? { imageBytes }
    func streamRequest(url: String) async -> MediaRequest? { nil }
}

final class FakeRegistry: ProviderAdapterRegistry, @unchecked Sendable {
    var adapter: ProviderAdapter?
    var created = 0
    func createAdapter(account: Account, secret: String) -> ProviderAdapter? { created += 1; return adapter }
}
