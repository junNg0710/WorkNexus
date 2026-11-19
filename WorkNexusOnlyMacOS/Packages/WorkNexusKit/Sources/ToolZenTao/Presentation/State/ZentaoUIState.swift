/// Ported from: lib/tools/zentao/presentation/providers/{zentao_board_providers,bug_module_names_provider,
/// task_module_names_provider,zentao_module_tree_provider,zentao_facet_catalog_provider}.dart and the
/// `select_bug_board_product` / `open_execution_board` util. The session state of the ZenTao tool: which product /
/// execution is open, the tab strips, the sidebar's expanded folders, and the cached-then-fresh source lists.
import CoreDomain
import CoreTools
import Foundation
import Observation
import SharedKit

@MainActor @Observable
public final class ZentaoUIState {
    @ObservationIgnored public let deps: ZentaoDependencies
    /// The two boards (one `BoardController` each, so each keeps its own filter memory).
    @ObservationIgnored public let taskBoard: BoardController
    @ObservationIgnored public let bugBoard: BoardController
    @ObservationIgnored public let bugStreams: PagedViewsController<ZenTaoBugStream>
    @ObservationIgnored public let taskStreams: PagedViewsController<ZenTaoTaskColumn>
    /// What each board derives from its tickets, kept until an input changes (`ZentaoBoardCache`).
    @ObservationIgnored let taskCache = ZentaoBoardCache()
    @ObservationIgnored let bugCache = ZentaoBoardCache()

    // MARK: Selection
    public internal(set) var product: ZentaoProductSelection?
    public internal(set) var execution: ZentaoExecutionSelection?
    /// The bug board's browse tab; `relatedToMe` feeds every column from one merged view.
    public internal(set) var bugTab: ZenTaoBugBrowseType = .unclosed
    /// The team leader's filter of each board (people, quick chips, keyword), by `BoardController.currentBoardKey`.
    public internal(set) var leaders: [String: ZenTaoLeaderFilter] = [:]
    /// The team groups saved for each account (watched from the store once an account's board opens).
    public internal(set) var teamGroups: [String: [ZenTaoTeamGroup]] = [:]
    /// The team a board shows instead of one execution / product, with what was read of each person.
    public internal(set) var taskTeam: ZentaoTeamScope?
    public internal(set) var bugTeam: ZentaoTeamScope?
    var teamGeneration = 0
    /// Bumped when the pinned people change, so the people strip reads them again.
    var pinnedPeopleRevision = 0
    var observedTeamAccounts: Set<String> = []
    /// A bulk dialog asked for from a card's menu; the bar of the board it names opens it and clears this.
    var bulkRequest: ZentaoBulkRequest?
    /// Boards (`"bugs"` / `"tasks"`) whose views the leader asked to load whole, so the counts cover everything.
    public internal(set) var loadingEverything: Set<String> = []
    public var hideEmptyModules = false
    /// Table sorts (kept for the session, apart for tasks and bugs).
    public var taskSort = TicketSort.newest
    public var bugSort = TicketSort.newest
    /// Whether each section shows as the list (table): the views are then fetched in the table's order.
    public var taskListMode = false
    public var bugListMode = false

    // MARK: Sidebar expansion (kept here so the pane survives being rebuilt on a section / account switch)
    public var projectsGroupExpanded: Set<String> = []
    public var executionsGroupExpanded: Set<String> = []
    /// `accountId:projectId` of the projects whose executions are open.
    public var expandedProjects: Set<String> = []
    public var collapsedProjectSets: Set<String> = []
    public var collapsedProductSets: Set<String> = []

    // MARK: Source lists (cached first, then fresh)
    public internal(set) var products: [String: ZentaoLoad<[ProviderProduct]>] = [:]
    public internal(set) var projects: [String: ZentaoLoad<[ProviderProject]>] = [:]
    public internal(set) var executions: [String: ZentaoLoad<[ProviderExecution]>] = [:]
    /// Module id + path in ZenTao's order, per `b:account:product` / `t:account:execution`.
    public internal(set) var moduleNames: [String: ZentaoLoad<[ZentaoModulePath]>] = [:]
    /// The people of the open board's product / execution (the facet catalog's assignee / opener choices).
    public internal(set) var boardMembers: [ProviderUser] = []
    var membersFor: String?
    var observing = false

    public init(deps: ZentaoDependencies) {
        self.deps = deps
        let registry = deps.registry()
        taskBoard = BoardController(services: deps.services, nav: deps.nav, registry: registry)
        bugBoard = BoardController(services: deps.services, nav: deps.nav, registry: registry)
        let box = WeakBox<ZentaoUIState>()
        bugStreams = PagedViewsController<ZenTaoBugStream>(
            isFiltered: { box.value.map { $0.bugBoard.filter.narrowsTickets || $0.leader(bugs: true).isActive } ?? false },
            fetchPage: { view, page, limit, cancel in
                await box.value?.fetchBugPage(view, page: page, limit: limit, cancel: cancel) ?? .failure(.cancelled("closed"))
            })
        taskStreams = PagedViewsController<ZenTaoTaskColumn>(
            isFiltered: { box.value.map { $0.taskBoard.filter.narrowsTickets || $0.leader(bugs: false).isActive } ?? false },
            fetchPage: { view, page, limit, cancel in
                await box.value?.fetchTaskPage(view, page: page, limit: limit, cancel: cancel) ?? .failure(.cancelled("closed"))
            })
        box.value = self
        taskBoard.scopeTickets = { [weak self] in self?.scopeTasks($0) ?? [] }
        bugBoard.scopeTickets = { [weak self] in self?.scopeBugs($0) ?? [] }
        // ⌘K searches the whole account (every execution / product cached), and an id nothing cached has is fetched.
        taskBoard.searchPool = { [weak self] in self?.accountZenTaoTickets($0) ?? [] }
        bugBoard.searchPool = { [weak self] in self?.accountZenTaoTickets($0) ?? [] }
        taskBoard.fetchTicketByKey = { [weak self] key in await self?.fetchByKey(key, bugsFirst: false) }
        bugBoard.fetchTicketByKey = { [weak self] key in await self?.fetchByKey(key, bugsFirst: true) }
        taskBoard.facetScope = .task
        bugBoard.facetScope = .bug
        taskBoard.perfName = "zentao tasks"; bugBoard.perfName = "zentao bugs"
        bugBoard.usesFacetFilters = true
        taskBoard.usesFacetFilters = true
    }

    /// Starts the boards' DB watches and re-scopes them whenever a paged view loads something.
    public func start() {
        taskBoard.start(); bugBoard.start()
        guard !observing else { return }
        observing = true
        observeStreams()
    }

    private func observeStreams() {
        withObservationTracking {
            _ = bugStreams.loads; _ = taskStreams.loads
        } onChange: { [weak self] in
            Task { @MainActor in self?.rescope(); self?.observeStreams() }
        }
    }

    /// Re-runs both boards' scoping (selection or loaded pages changed).
    public func rescope() {
        taskBoard.scopeTickets = { [weak self] in self?.scopeTasks($0) ?? [] }
        bugBoard.scopeTickets = { [weak self] in self?.scopeBugs($0) ?? [] }
    }

    // MARK: Opening boards

    /// Opens `product`'s bug board: its scope, its selection and its own filter. An execution picked under another
    /// product would narrow this product's bugs to nothing, so it is cleared.
    public func openProduct(_ p: ProviderProduct) {
        closeTeam(bugs: true)
        deps.nav.setScope(p.id, accountId: p.accountId)
        selectProduct(p)
        execution = nil
        bugBoard.openBoard(bugBoard.currentBoardKey)
        rescope()
    }

    /// Opens `execution`'s task board (the sidebar's and a ticket's Execution field's way in).
    public func openExecution(_ e: ProviderExecution) {
        closeTeam(bugs: false)
        deps.nav.select(.account(e.accountId))
        deps.nav.setSection(ZentaoSection.tasks, accountId: e.accountId)
        deps.nav.setScope(e.id, accountId: e.accountId)
        product = nil
        selectExecution(e)
        taskBoard.openBoard(taskBoard.currentBoardKey)
        rescope()
    }

    /// The open board's selection stays when it is picked again, so its loaded pages are kept.
    func selectProduct(_ p: ProviderProduct) {
        guard product?.accountId != p.accountId || product?.productId != p.id else { return }
        product = ZentaoProductSelection(accountId: p.accountId, productId: p.id, productName: p.name)
        reopenBugStreams()
    }

    func selectExecution(_ e: ProviderExecution) {
        guard execution?.accountId != e.accountId || execution?.executionId != e.id else { return }
        execution = ZentaoExecutionSelection(accountId: e.accountId, projectId: e.projectId, executionId: e.id, executionName: e.name)
        reopenTaskStreams()
    }

    public func clearProduct() { if product != nil { product = nil; reopenBugStreams(); rescope() } }
    public func clearExecution() { if execution != nil { execution = nil; reopenTaskStreams(); rescope() } }

    public func setBugTab(_ tab: ZenTaoBugBrowseType) {
        guard tab != bugTab else { return }
        let relatedChanged = (tab == .relatedToMe) != bugRelated
        bugTab = tab
        if relatedChanged { reopenBugStreams() }
        // The Closed column draws on the all-bugs view, which only loads once the tab that shows it is open.
        if tab == .all, bugStreams.views[.all]?.started != true { Task { await bugStreams.loadMore(.all) } }
        rescope()
    }

    public var bugRelated: Bool { bugTab == .relatedToMe }

    /// The order a board's views are fetched in: the table's sort while the section shows as a list, else newest first.
    /// Sorting by status orders the views, not the tickets within one, so each view is still fetched newest first.
    func fetchSort(_ list: Bool, _ chosen: TicketSort) -> TicketSort {
        let sort = list ? chosen : .newest
        return sort.field == .status ? .newest : sort
    }
    var bugFetchSort: TicketSort { fetchSort(bugListMode, bugSort) }
    var taskFetchSort: TicketSort { fetchSort(taskListMode, taskSort) }
    private var lastFetchSorts: [TicketSort] = []

    /// Call when the layout or a table sort changed: a new order starts every view over from its first page.
    public func refreshFetchSorts() {
        let now = [bugFetchSort, taskFetchSort]
        guard !lastFetchSorts.isEmpty, now != lastFetchSorts else { lastFetchSorts = now; return }
        if now[0] != lastFetchSorts[0] { reopenBugStreams() }
        if now[1] != lastFetchSorts[1] { reopenTaskStreams() }
        lastFetchSorts = now
    }
}
