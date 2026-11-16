import CoreDomain
import CoreTools
import Foundation
@testable import ToolZenTao

/// In-memory fakes of the interfaces the ZenTao detail presentation depends on (tests mock at the interface boundary).
final class DetailFakeStore: TicketRepository, WorkspaceRepository, CommentRepository, ActivityRepository, CredentialStore,
                             SettingsRepository, SyncStatusRepository, @unchecked Sendable {
    var tickets: [String: Ticket] = [:]
    var accounts: [String: Account] = [:]
    var settings = AppSettings()
    private func once<T>(_ v: T) -> AsyncStream<T> { AsyncStream { $0.yield(v); $0.finish() } }

    func watchTickets() -> AsyncStream<[Ticket]> { once(Array(tickets.values)) }
    func ticket(id: String) async -> Outcome<Ticket?> { .success(tickets[id]) }
    func upsertTickets(_ list: [Ticket]) async -> Outcome<Void> { for t in list { tickets[t.id] = t }; return .success(()) }
    func moveTicket(id: String, to status: UnifiedStatus) async -> Outcome<Void> { .success(()) }
    func watchWorkspaces() -> AsyncStream<[Workspace]> { once([]) }
    func watchAccounts() -> AsyncStream<[Account]> { once(Array(accounts.values)) }
    func watchProjects() -> AsyncStream<[Project]> { once([]) }
    func createWorkspace(_ workspace: Workspace) async -> Outcome<Void> { .success(()) }
    func updateWorkspace(_ workspace: Workspace) async -> Outcome<Void> { .success(()) }
    func upsertAccount(_ account: Account) async -> Outcome<Void> { .success(()) }
    func deleteAccount(id: String) async -> Outcome<Void> { .success(()) }
    func upsertProjects(_ projects: [Project]) async -> Outcome<Void> { .success(()) }
    func watchComments(ticketId: String) -> AsyncStream<[Comment]> { once([]) }
    func upsertComments(_ comments: [Comment]) async -> Outcome<Void> { .success(()) }
    func watchActivity(ticketId: String) -> AsyncStream<[ActivityEvent]> { once([]) }
    func upsertActivity(_ events: [ActivityEvent]) async -> Outcome<Void> { .success(()) }
    func read(_ key: String) async -> String? { nil }
    func write(_ key: String, value: String) async -> Outcome<Void> { .success(()) }
    func delete(_ key: String) async -> Outcome<Void> { .success(()) }
    func load() async -> AppSettings { settings }
    func save(_ s: AppSettings) async -> Outcome<Void> { settings = s; return .success(()) }
    func watch() -> AsyncStream<AppSettings> { once(settings) }
    func watch(accountId: String) -> AsyncStream<AccountSyncStatus> { once(.idle(lastSyncedAt: nil)) }
    func status(accountId: String) async -> AccountSyncStatus { .idle(lastSyncedAt: nil) }
    func report(accountId: String, status: AccountSyncStatus) {}
}

/// A scripted adapter: users, assign calls, bytes and a stream request.
final class DetailFakeAdapter: ProviderAdapter, @unchecked Sendable {
    let providerType: ProviderType = .zentao
    var users: [ProviderUser] = []
    var assigned: [(assignee: String, comment: String?, left: Double?)] = []
    var bytes: Data?
    var stream: MediaRequest?
    func testConnection() async -> Outcome<ConnectionCheck> { .success(ConnectionCheck(ok: true)) }
    func listAssignedTickets(sinceCursor: String?) async -> Outcome<TicketPage> { .success(TicketPage(tickets: [])) }
    func getTicket(_ ticket: Ticket) async -> Outcome<Ticket> { .success(ticket) }
    func listComments(_ ticket: Ticket) async -> Outcome<[Comment]> { .success([]) }
    func postComment(_ ticket: Ticket, body: String) async -> Outcome<Comment> { .failure(.unexpected("n/a")) }
    func listActivity(_ ticket: Ticket) async -> Outcome<[ActivityEvent]> { .success([]) }
    func listUsers() async -> Outcome<[ProviderUser]> { .success(users) }
    func assignTicket(_ ticket: Ticket, assignee: String, comment: String?, left: Double?) async -> Outcome<Bool> {
        assigned.append((assignee, comment, left)); return .success(true)
    }
    func fetchBytes(url: String, projectPath: String?, projectId: String?) async -> Data? { bytes }
    func downloadBytes(url: String) async -> Data? { bytes }
    func streamRequest(url: String) async -> MediaRequest? { stream }
}

final class DetailFakeSync: AccountSyncService, TicketDetailService, @unchecked Sendable {
    let adapter: DetailFakeAdapter
    var refreshed: [String] = []
    init(adapter: DetailFakeAdapter) { self.adapter = adapter }
    func sync(accountId: String) async -> Outcome<Void> { .success(()) }
    func adapter(for account: Account) async -> ProviderAdapter? { adapter }
    func refresh(ticket: Ticket) async -> Outcome<Void> { refreshed.append(ticket.id); return .success(()) }
    func postComment(ticket: Ticket, body: String) async -> Outcome<Void> { .success(()) }
}

struct DetailFakeRegistry: ProviderAdapterRegistry { func createAdapter(account: Account, secret: String) -> ProviderAdapter? { nil } }

final class DetailFakeWorkflow: ZenTaoWorkflowService, @unchecked Sendable {
    var taskCalls: [(Ticket, ZenTaoTaskAction, ZenTaoTaskActionInput)] = []
    var bugCalls: [String] = []
    var failure: Failure?
    private func result() -> Outcome<Void> { failure.map { .failure($0) } ?? .success(()) }
    func confirmBug(_ ticket: Ticket, assignee: String?, comment: String?) async -> Outcome<Void> { bugCalls.append("confirm"); return result() }
    func activateBug(_ ticket: Ticket, build: String?, assignee: String?, comment: String?) async -> Outcome<Void> { bugCalls.append("activate:\(build ?? "")"); return result() }
    func resolveBug(_ ticket: Ticket, resolution: String, build: String?, assignee: String?, comment: String?) async -> Outcome<Void> {
        bugCalls.append("resolve:\(resolution)"); return result()
    }
    func closeBug(_ ticket: Ticket, comment: String?) async -> Outcome<Void> { bugCalls.append("close"); return result() }
    func runTaskAction(_ ticket: Ticket, _ action: ZenTaoTaskAction, _ input: ZenTaoTaskActionInput) async -> Outcome<Void> {
        taskCalls.append((ticket, action, input)); return result()
    }
}

final class DetailFakeTicketService: ZenTaoTicketService, ZenTaoTaskBugs, ZenTaoViewPages, @unchecked Sendable {
    var fetched: [(host: String, type: String, id: String)] = []
    var onFetch: ((String, String, String) async -> String)?
    var bugSyncs: [(String, String, String)] = []
    var bugSyncFailure: Failure?
    func fetchZenTaoTicket(host: String, type: String, id: String) async -> Outcome<String> {
        fetched.append((host, type, id))
        return .success(await onFetch?(host, type, id) ?? zenTaoTicketId(accountId: "zt", type: type, id: id))
    }
    func listProducts(accountId: String) async -> Outcome<[ProviderProduct]> { .success([]) }
    func cachedProducts(accountId: String) async -> [ProviderProduct]? { nil }
    func listProjects(accountId: String) async -> Outcome<[ProviderProject]> { .success([]) }
    func cachedProjects(accountId: String) async -> [ProviderProject]? { nil }
    func listProjectExecutions(accountId: String, projectId: String) async -> Outcome<[ProviderExecution]> { .success([]) }
    func fetchZenTaoMessages(accountId: String) async -> Outcome<ZenTaoRawReply> { .success(ZenTaoRawReply([:])) }
    func zenTaoMessageAction(accountId: String, action: String) async -> Outcome<Void> { .success(()) }
    func fetchZenTaoUserInfo(accountId: String, fields: String, limit: Int) async -> Outcome<ZenTaoRawReply> { .success(ZenTaoRawReply([:])) }
    func syncTaskBugs(accountId: String, executionId: String, taskId: String) async -> Outcome<Void> {
        bugSyncs.append((accountId, executionId, taskId)); return bugSyncFailure.map { .failure($0) } ?? .success(())
    }
    func syncProductBugsPage(accountId: String, productId: String, browseType: String, page: Int, limit: Int, sort: TicketSort, cancel: CancelSignal?) async -> Outcome<ViewPage> {
        .success(ViewPage(tickets: [], total: 0, hasMore: false))
    }
    func syncExecutionTasksPage(accountId: String, executionId: String, browseType: String, page: Int, limit: Int, sort: TicketSort, cancel: CancelSignal?) async -> Outcome<ViewPage> {
        .success(ViewPage(tickets: [], total: 0, hasMore: false))
    }
}

struct DetailFakeEditor: ZenTaoTicketEditor {
    func newBugForm(accountId: String, productId: String, copyOf: String?, executionId: String?, taskId: String?) async -> Outcome<BugForm> { .failure(.unexpected("n/a")) }
    func editBugForm(accountId: String, bugId: String) async -> Outcome<BugForm> { .failure(.unexpected("n/a")) }
    func bugOptions(accountId: String, productId: String, projectId: String, executionId: String) async -> Outcome<BugFormOptions> { .failure(.unexpected("n/a")) }
    func bugModules(accountId: String, productId: String) async -> Outcome<[FormOption]> {
        .success([FormOption(value: "0", label: "/"), FormOption(value: "7", label: "/Livestream/Share")])
    }
    func saveBug(accountId: String, form: BugForm, draft: BugDraft, uid: String) async -> Outcome<String> { .failure(.unexpected("n/a")) }
    func newTaskForm(accountId: String, executionId: String, parentId: String?, copyOf: String?) async -> Outcome<TaskForm> { .failure(.unexpected("n/a")) }
    func editTaskForm(accountId: String, taskId: String) async -> Outcome<TaskForm> { .failure(.unexpected("n/a")) }
    func taskOptions(accountId: String, executionId: String) async -> Outcome<TaskFormOptions> { .failure(.unexpected("n/a")) }
    func saveTask(accountId: String, form: TaskForm, draft: TaskDraft, uid: String) async -> Outcome<String> { .failure(.unexpected("n/a")) }
    func loadImage(accountId: String, url: String) async -> Data? { nil }
    func uploadImage(accountId: String, uid: String, bytes: Data, fileName: String) async -> Outcome<String> { .success("/file-read-1.png") }
}

struct DetailFakeTeam: ZenTaoTeamMembers {
    var members: [ProviderUser] = []
    func productMembers(accountId: String, productId: String) async -> Outcome<[ProviderUser]> { .success(members) }
    func executionMembers(accountId: String, executionId: String) async -> Outcome<[ProviderUser]> { .success(members) }
}

struct DetailFakeDocs: ZenTaoDocRepository {
    func watchLibs(accountId: String) -> AsyncStream<[ZenTaoDocLib]> { AsyncStream { $0.finish() } }
    func watchDocs(accountId: String, libId: String) -> AsyncStream<[ZenTaoDocSummary]> { AsyncStream { $0.finish() } }
    func watchDoc(accountId: String, docId: String) -> AsyncStream<ZenTaoDoc?> { AsyncStream { $0.finish() } }
    func refreshLibs(account: Account) async -> Outcome<Void> { .success(()) }
    func refreshDocs(account: Account, libId: String) async -> Outcome<Void> { .success(()) }
    func refreshDoc(account: Account, docId: String) async -> Outcome<Void> { .success(()) }
    func watchHistory(accountId: String, docId: String) -> AsyncStream<[ZenTaoDocAction]> { AsyncStream { $0.finish() } }
    func refreshHistory(account: Account, docId: String) async -> Outcome<Void> { .success(()) }
    func watchPins(accountId: String) -> AsyncStream<ZenTaoDocPins> { AsyncStream { $0.finish() } }
    func savePins(accountId: String, pins: ZenTaoDocPins) async -> Outcome<Void> { .success(()) }
    func fetchImage(account: Account, url: String) async -> Data? { nil }
    func readFile(account: Account, file: TicketAttachment) async -> Outcome<Data> { .failure(.unexpected("n/a")) }
    func saveFile(account: Account, file: TicketAttachment) async -> Outcome<String> { .failure(.unexpected("n/a")) }
    func readBackup(accountId: String, docId: String) async -> Outcome<String> { .failure(.unexpected("n/a")) }
    func saveText(fileName: String, text: String) async -> Outcome<String> { .failure(.unexpected("n/a")) }
}

/// The whole ZenTao detail environment over fakes.
@MainActor
struct DetailEnv {
    let store = DetailFakeStore()
    let adapter = DetailFakeAdapter()
    let workflow = DetailFakeWorkflow()
    let service = DetailFakeTicketService()
    let nav: AppNavController
    let deps: ZentaoDependencies
    let state: ZentaoUIState
    let sync: DetailFakeSync

    init(members: [ProviderUser] = []) {
        let adapter = self.adapter, store = self.store, service = self.service
        sync = DetailFakeSync(adapter: adapter)
        store.accounts["zt"] = Account(id: "zt", workspaceId: "w1", providerType: .zentao, handle: "thanh", baseUrl: "https://zentao.example.com/zentao")
        let nav = AppNavController { _ in ZentaoSection.tasks }
        self.nav = nav
        let services = AppServices(tickets: store, workspaces: store, comments: store, activity: store, syncStatus: store, settings: store,
                                   credentials: store, sync: sync, ticketDetail: sync, adapters: DetailFakeRegistry())
        let docs = DetailFakeDocs()
        deps = ZentaoDependencies(services: services, nav: nav, registry: { ToolRegistry() }, tickets: service, viewPages: service, taskBugs: service,
                                  editor: DetailFakeEditor(), teamMembers: DetailFakeTeam(members: members), workflow: workflow, docs: docs,
                                  exportDoc: ExportZenTaoDoc(docs))
        state = ZentaoUIState(deps: deps)
    }
}

/// A ZenTao ticket of `type` ("Bug" / "Task") in `providerStatus`.
func detailTicket(_ type: String, _ raw: String, key: String = "12", status: UnifiedStatus = .inprogress,
                  entity: TicketProviderEntity? = nil, title: String = "t", url: String? = nil) -> Ticket {
    Ticket(id: zenTaoTicketId(accountId: "zt", type: type.lowercased(), id: key), accountId: "zt", projectId: "zt:P", providerType: .zentao,
           externalKey: key, title: title, body: "", priority: .medium, status: status, providerStatus: raw, sourceHash: "h",
           externalType: type, url: url, providerEntity: entity)
}
