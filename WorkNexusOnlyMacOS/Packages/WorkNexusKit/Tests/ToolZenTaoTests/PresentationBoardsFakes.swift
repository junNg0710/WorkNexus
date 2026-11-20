import CoreDomain
import CoreTools
import Foundation
@testable import ToolZenTao

/// A scripted source of pages for the paged boards: records every call and answers from `script`
/// (`browseType` -> tickets of the whole view, paged by `limit`).
final class FakeViewPages: ZenTaoTicketService, ZenTaoViewPages, ZenTaoTaskBugs, @unchecked Sendable {
    struct Call: Equatable { var kind: String, scope: String, browseType: String, page: Int, limit: Int, sort: TicketSort }
    private let lock = NSLock()
    private var _calls: [Call] = []
    var calls: [Call] { lock.withLock { _calls } }
    /// Tickets of each view by browse type.
    var script: [String: [Ticket]] = [:]
    var failing: Set<String> = []
    var products: [ProviderProduct] = []
    var projects: [ProviderProject] = []
    var executions: [String: [ProviderExecution]] = [:]

    private func page(_ call: Call, _ all: [Ticket]) -> Outcome<ViewPage> {
        lock.withLock { _calls.append(call) }
        if failing.contains(call.browseType) { return .failure(.network("down")) }
        let from = (call.page - 1) * call.limit
        let slice = from < all.count ? Array(all[from..<min(from + call.limit, all.count)]) : []
        return .success(ViewPage(tickets: slice, total: all.count, hasMore: from + call.limit < all.count))
    }
    func syncProductBugsPage(accountId: String, productId: String, browseType: String, page: Int, limit: Int, sort: TicketSort, cancel: CancelSignal?) async -> Outcome<ViewPage> {
        self.page(Call(kind: "bugs", scope: productId, browseType: browseType, page: page, limit: limit, sort: sort), script[browseType] ?? [])
    }
    func syncExecutionTasksPage(accountId: String, executionId: String, browseType: String, page: Int, limit: Int, sort: TicketSort, cancel: CancelSignal?) async -> Outcome<ViewPage> {
        self.page(Call(kind: "tasks", scope: executionId, browseType: browseType, page: page, limit: limit, sort: sort), script[browseType] ?? [])
    }
    /// What `syncAssignedWork` answers per login, and the logins it refuses; every call is recorded as `login|bugs`.
    var personWork: [String: ZenTaoPersonWork] = [:]
    var personFailures: [String: Failure] = [:]
    private var _personCalls: [String] = []
    var personCalls: [String] { lock.withLock { _personCalls } }
    func syncAssignedWork(accountId: String, login: String, bugs: Bool, cap: Int, cancel: CancelSignal?) async -> Outcome<ZenTaoPersonWork> {
        lock.withLock { _personCalls.append("\(login)|\(bugs)") }
        if let f = personFailures[login] { return .failure(f) }
        return .success(personWork[login] ?? ZenTaoPersonWork(ids: [], total: 0, truncated: false))
    }
    func fetchZenTaoTicket(host: String, type: String, id: String) async -> Outcome<String> { .success("") }
    func listProducts(accountId: String) async -> Outcome<[ProviderProduct]> { .success(products) }
    func cachedProducts(accountId: String) async -> [ProviderProduct]? { nil }
    func listProjects(accountId: String) async -> Outcome<[ProviderProject]> { .success(projects) }
    func cachedProjects(accountId: String) async -> [ProviderProject]? { nil }
    func listProjectExecutions(accountId: String, projectId: String) async -> Outcome<[ProviderExecution]> { .success(executions[projectId] ?? []) }
    func fetchZenTaoMessages(accountId: String) async -> Outcome<ZenTaoRawReply> { .success(ZenTaoRawReply([:])) }
    func zenTaoMessageAction(accountId: String, action: String) async -> Outcome<Void> { .success(()) }
    func fetchZenTaoUserInfo(accountId: String, fields: String, limit: Int) async -> Outcome<ZenTaoRawReply> { .success(ZenTaoRawReply([:])) }
    func syncTaskBugs(accountId: String, executionId: String, taskId: String) async -> Outcome<Void> { .success(()) }
}

/// The ZenTao board environment over fakes: one account `zt1` on the rail, in the Tasks section.
@MainActor
struct BoardsEnv {
    let store = DetailFakeStore()
    let pages = FakeViewPages()
    let workflow = DetailFakeWorkflow()
    let adapter = DetailFakeAdapter()
    let nav: AppNavController
    let deps: ZentaoDependencies
    let state: ZentaoUIState

    init(section: SectionID = ZentaoSection.bugs, tickets: [Ticket] = [], members: [ProviderUser] = [],
         teamGroups: ZenTaoTeamGroupRepository = NoTeamGroups(), boardScopes: ZenTaoBoardScopeStore = BoardsEnv.onTheirScope()) {
        let store = self.store, pages = self.pages, adapter = self.adapter
        store.accounts["zt1"] = Account(id: "zt1", workspaceId: "w1", providerType: .zentao, handle: "thanh", baseUrl: "https://zentao.example.com")
        for t in tickets { store.tickets[t.id] = t }
        let nav = AppNavController { _ in section }
        nav.select(.account("zt1"))
        nav.setSection(section, accountId: "zt1")
        self.nav = nav
        let sync = DetailFakeSync(adapter: adapter)
        let services = AppServices(tickets: store, workspaces: store, comments: store, activity: store, syncStatus: store, settings: store,
                                   credentials: store, sync: sync, ticketDetail: sync, adapters: DetailFakeRegistry())
        let docs = DetailFakeDocs()
        deps = ZentaoDependencies(services: services, nav: nav, registry: { ToolRegistry() }, tickets: pages, viewPages: pages, taskBugs: pages,
                                  editor: DetailFakeEditor(), teamMembers: DetailFakeTeam(members: members), workflow: workflow, docs: docs,
                                  exportDoc: ExportZenTaoDoc(docs), teamGroups: teamGroups, boardScopes: boardScopes)
        state = ZentaoUIState(deps: deps)
        state.start()
    }

    /// Boards that open on their execution / product, as before "Only me" was the first-visit default.
    nonisolated static func onTheirScope() -> InMemoryBoardScopes {
        let scopes = InMemoryBoardScopes()
        for bugs in [false, true] { scopes.setChoice(.scope, accountId: "zt1", bugs: bugs) }
        return scopes
    }

    func product(_ id: String = "p1", _ name: String = "Social") -> ProviderProduct { ProviderProduct(id: id, name: name, accountId: "zt1") }
    func execution(_ id: String = "e1", _ name: String = "Sprint 1", project: String = "pj1") -> ProviderExecution {
        ProviderExecution(id: id, name: name, projectId: project, accountId: "zt1")
    }

    /// Polls `cond` for up to a second (the streams and DB watches run on tasks).
    func wait(_ cond: @escaping @MainActor () -> Bool) async {
        for _ in 0..<150 where !cond() { try? await Task.sleep(for: .milliseconds(10)) }
    }
}

/// A ZenTao bug of product `product` (labelled as the list sync does) in `providerStatus`.
func boardBug(_ key: String, product: String = "p1", providerStatus: String = "active", status: UnifiedStatus = .todo,
              resolution: String? = nil, execution: String? = nil, assignee: String? = nil, severity: Int? = nil,
              updated: Date? = nil, priority: Priority = .medium) -> Ticket {
    var labels = [zentaoProductLabel(product)]
    if let execution { labels.append(zentaoExecutionLabel(execution)) }
    if let resolution { labels.append("resolution:\(resolution)") }
    return Ticket(id: zenTaoTicketId(accountId: "zt1", type: "bug", id: key), accountId: "zt1", projectId: "zt1:P", providerType: .zentao,
                  externalKey: key, title: "Bug \(key)", body: "", priority: priority, status: status, providerStatus: providerStatus,
                  sourceHash: "h", externalType: "Bug", labels: labels, assignee: assignee, severity: severity, updatedAt: updated,
                  providerEntity: .zentaoBug(ZenTaoBugEntity(product: product, execution: execution)))
}

/// A ZenTao task of execution `execution` in `providerStatus`.
func boardTask(_ key: String, execution: String = "e1", providerStatus: String = "wait", status: UnifiedStatus = .todo,
               deadline: String? = nil, assignee: String? = nil, updated: Date? = nil) -> Ticket {
    Ticket(id: zenTaoTicketId(accountId: "zt1", type: "task", id: key), accountId: "zt1", projectId: "zt1:P", providerType: .zentao,
           externalKey: key, title: "Task \(key)", body: "", priority: .medium, status: status, providerStatus: providerStatus,
           sourceHash: "h", externalType: "Task", labels: [zentaoExecutionLabel(execution)], assignee: assignee, updatedAt: updated,
           providerEntity: .zentaoTask(ZenTaoTaskEntity(execution: execution, deadline: deadline)))
}
