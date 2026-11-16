import Foundation

/// Ported from: lib/core/domain/adapters/provider_adapter.dart (+ registry)
public struct ConnectionCheck: Sendable {
    public var ok: Bool
    public var account: String?
    public var serverVersion: String?
    public var baseUrl: String?
    public var error: String?
    public init(ok: Bool, account: String? = nil, serverVersion: String? = nil, baseUrl: String? = nil, error: String? = nil) {
        self.ok = ok; self.account = account; self.serverVersion = serverVersion; self.baseUrl = baseUrl; self.error = error
    }
}

public struct TicketPage: Sendable {
    public var tickets: [Ticket]
    public var nextCursor: String?
    public init(tickets: [Ticket], nextCursor: String? = nil) { self.tickets = tickets; self.nextCursor = nextCursor }
}

public struct ViewPage: Sendable {
    public var tickets: [Ticket]
    public var total: Int
    public var hasMore: Bool
    public init(tickets: [Ticket], total: Int, hasMore: Bool) { self.tickets = tickets; self.total = total; self.hasMore = hasMore }
}

public struct ProviderUser: Sendable, Hashable, Identifiable {
    public var account: String
    public var displayName: String
    public var avatarUrl: String?
    public var id: String { account }
    public init(account: String, displayName: String, avatarUrl: String? = nil) {
        self.account = account; self.displayName = displayName; self.avatarUrl = avatarUrl
    }
}

public struct ProviderLabelOption: Sendable, Hashable {
    public var name: String
    public var color: String?
    public init(name: String, color: String? = nil) { self.name = name; self.color = color }
}

public struct ProviderMilestoneOption: Sendable, Hashable {
    public var id: Int
    public var title: String
    public init(id: Int, title: String) { self.id = id; self.title = title }
}

public struct ProviderProduct: Sendable, Hashable, Identifiable {
    public var id: String, name: String, accountId: String
    public var programId, programName, lineId, lineName: String?
    public init(id: String, name: String, accountId: String, programId: String? = nil, programName: String? = nil,
                lineId: String? = nil, lineName: String? = nil) {
        self.id = id; self.name = name; self.accountId = accountId; self.programId = programId
        self.programName = programName; self.lineId = lineId; self.lineName = lineName
    }
}

public struct ProviderProject: Sendable, Hashable, Identifiable {
    public var id: String, name: String, accountId: String
    public var programId, programName: String?
    public init(id: String, name: String, accountId: String, programId: String? = nil, programName: String? = nil) {
        self.id = id; self.name = name; self.accountId = accountId; self.programId = programId; self.programName = programName
    }
}

public struct ProviderExecution: Sendable, Hashable, Identifiable {
    public var id: String, name: String, projectId: String, accountId: String
    public init(id: String, name: String, projectId: String, accountId: String) {
        self.id = id; self.name = name; self.projectId = projectId; self.accountId = accountId
    }
}

/// One instance per account. Provider-specific extras live in tool modules; this is the cross-provider contract.
public protocol ProviderAdapter: Sendable {
    var providerType: ProviderType { get }
    func testConnection() async -> Outcome<ConnectionCheck>
    func listAssignedTickets(sinceCursor: String?) async -> Outcome<TicketPage>
    func getTicket(_ ticket: Ticket) async -> Outcome<Ticket>
    func listComments(_ ticket: Ticket) async -> Outcome<[Comment]>
    func postComment(_ ticket: Ticket, body: String) async -> Outcome<Comment>
    func listActivity(_ ticket: Ticket) async -> Outcome<[ActivityEvent]>
    func listUsers() async -> Outcome<[ProviderUser]>
    func listProducts() async -> Outcome<[ProviderProduct]>
    func listProductBugs(productId: String, browseType: String?) async -> Outcome<TicketPage>
    func listProductBugsPage(productId: String, browseType: String, page: Int, limit: Int,
                             sort: TicketSort, cancel: CancelSignal?) async -> Outcome<ViewPage>
    func listProjects() async -> Outcome<[ProviderProject]>
    func listProjectExecutions(projectId: String) async -> Outcome<[ProviderExecution]>
    func listExecutionTasksPage(executionId: String, browseType: String, page: Int, limit: Int,
                                sort: TicketSort, cancel: CancelSignal?) async -> Outcome<ViewPage>
    func assignTicket(_ ticket: Ticket, assignee: String, comment: String?, left: Double?) async -> Outcome<Bool>
    func resolveBug(_ ticket: Ticket, resolution: String, resolvedBuild: String?, assignee: String?, comment: String?) async -> Outcome<Bool>
    func activateBug(_ ticket: Ticket, openedBuild: String?, assignee: String?, comment: String?) async -> Outcome<Bool>
    func confirmBug(_ ticket: Ticket, assignee: String?, comment: String?) async -> Outcome<Bool>
    func fetchBytes(url: String, projectPath: String?, projectId: String?) async -> Data?
    func downloadBytes(url: String) async -> Data?
    func streamRequest(url: String) async -> MediaRequest?
}

/// Default "not supported by this provider" behaviour so GitHub/GitLab adapters only implement what applies.
public extension ProviderAdapter {
    private func unsupported<T>(_ name: String) -> Outcome<T> { .failure(.unexpected("\(name) not supported by \(providerType.displayName)")) }
    func listUsers() async -> Outcome<[ProviderUser]> { .success([]) }
    func listProducts() async -> Outcome<[ProviderProduct]> { .success([]) }
    func listProductBugs(productId: String, browseType: String?) async -> Outcome<TicketPage> { unsupported("listProductBugs") }
    func listProductBugsPage(productId: String, browseType: String, page: Int, limit: Int, sort: TicketSort, cancel: CancelSignal?) async -> Outcome<ViewPage> { unsupported("listProductBugsPage") }
    func listProjects() async -> Outcome<[ProviderProject]> { .success([]) }
    func listProjectExecutions(projectId: String) async -> Outcome<[ProviderExecution]> { .success([]) }
    func listExecutionTasksPage(executionId: String, browseType: String, page: Int, limit: Int, sort: TicketSort, cancel: CancelSignal?) async -> Outcome<ViewPage> { unsupported("listExecutionTasksPage") }
    func resolveBug(_ ticket: Ticket, resolution: String, resolvedBuild: String?, assignee: String?, comment: String?) async -> Outcome<Bool> { unsupported("resolveBug") }
    func activateBug(_ ticket: Ticket, openedBuild: String?, assignee: String?, comment: String?) async -> Outcome<Bool> { unsupported("activateBug") }
    func confirmBug(_ ticket: Ticket, assignee: String?, comment: String?) async -> Outcome<Bool> { unsupported("confirmBug") }
    func fetchBytes(url: String, projectPath: String?, projectId: String?) async -> Data? { nil }
    func downloadBytes(url: String) async -> Data? { nil }
    func streamRequest(url: String) async -> MediaRequest? { nil }
}

/// Composition root implements this and hands adapters to the sync layer (decouples tools from each other).
public protocol ProviderAdapterRegistry: Sendable {
    func createAdapter(account: Account, secret: String) -> ProviderAdapter?
}

/// Ported from: lib/core/domain/adapters/{account_sync_service,ticket_detail_service}.dart (minimal contract; tools extend).
public protocol AccountSyncService: Sendable {
    /// Fetches this account's assigned tickets and writes them to the DB. Concurrent calls for one account are de-duplicated.
    func sync(accountId: String) async -> Outcome<Void>
    /// Pooled adapter for an account (nil if the secret is missing).
    func adapter(for account: Account) async -> ProviderAdapter?
}

public protocol TicketDetailService: Sendable {
    /// Re-fetches ticket + comments + activity from the provider into the DB.
    func refresh(ticket: Ticket) async -> Outcome<Void>
    func postComment(ticket: Ticket, body: String) async -> Outcome<Void>
}
