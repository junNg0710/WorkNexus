import CoreDomain
import CoreTools
import Foundation
import Observation

public enum BoardViewStyle: Sendable { case kanban, table }

/// Ported from: lib/shared/board/presentation/providers/{board_providers,board_loading_provider,saved_filter_providers,
/// assigned_counts_provider}.dart. One controller per board host (a tool's tickets section): it watches the DB-backed
/// ticket / account / workspace / settings streams (local-first), scopes the tickets (the tool supplies `scopeTickets`
/// or an `scopedTicketsOverride`), applies the `FilterState` and publishes the derived `board`.
/// Filter mutations live in `BoardController+Filters.swift`.
@MainActor @Observable
public final class BoardController {
    public let services: AppServices
    public let nav: AppNavController
    public let registry: ToolRegistry
    let savedFilterRepo: SavedFilterRepository

    // MARK: Inputs
    /// Every ticket in the local DB.
    /// Every ticket, as the repository last sent them. Not compared with the list it replaces before the observers are
    /// told (what a stored property of an `@Observable` class does): the repository only sends a list that differs, and
    /// comparing some twelve thousand tickets here, on the main thread, for every board at every write of a sync, cost
    /// more than everything else a ticket change did.
    public private(set) var tickets: [Ticket] {
        get { access(keyPath: \.tickets); return allTickets }
        set { withMutation(keyPath: \.tickets) { allTickets = newValue }; ticketsChanged() }
    }
    @ObservationIgnored private var allTickets: [Ticket] = []
    public private(set) var accounts: [String: Account] = [:] { didSet { recompute() } }
    public private(set) var workspaces: [String: Workspace] = [:]
    public private(set) var projects: [String: Project] = [:]
    /// A tool's scope can depend on the settings (which executions a team view leaves out): a change re-scopes.
    public private(set) var settings = AppSettings() { didSet { if oldValue != settings, scopeTickets != nil { recompute() } } }
    public private(set) var savedFilters: [SavedFilter] = []
    /// Replaces the tickets the board scopes from (a paged tool board that loads its own slice).
    public var scopedTicketsOverride: [Ticket]? { didSet { ticketsChanged() } }
    /// Tool hook (Flutter: `ToolModule.scopeTickets`): narrows all tickets to the section / scope on screen.
    public var scopeTickets: (([Ticket]) -> [Ticket])? { didSet { ticketsChanged() } }
    /// Which facet groups the filter popover offers (bug / task / MR boards); `.none` uses the generic groups.
    public var facetScope: BoardFacetScope = .none
    /// Account-wide "mine" board: hides the status / priority groups (the saved views cover them).
    public var isMineBoard = false
    public var usesFacetFilters = false

    // MARK: State
    public internal(set) var filter = FilterState() { didSet { recompute() } }
    public var viewStyle: BoardViewStyle = .kanban
    /// Tickets with a running action (cards dim, taps ignored).
    public private(set) var pendingTicketIds: Set<String> = []
    /// True for a moment after a workspace switch so the board shows its skeleton.
    public private(set) var loading = true

    // MARK: Derived (recomputed when an input changes)
    public private(set) var scoped: [Ticket] = []
    public private(set) var board: BoardModel = .empty
    public private(set) var resultCount = 0
    /// Goes up each time the tickets in scope or the filter change: what derived from them can be kept until it does.
    public private(set) var revision = 0
    /// False while the board's section is kept mounted behind another one: it then stops recomputing on every ticket
    /// change (a sync writes many) and catches up once when it is shown again.
    public var isActive = true {
        didSet {
            if isActive, !oldValue, stale { recompute() }
            if isActive != oldValue { describeForPerformanceLog() }
        }
    }
    /// What the performance log calls this board ("zentao tasks"): its work and what it holds are written under it.
    public var perfName = "board"
    @ObservationIgnored private var stale = false
    /// Whether the derived values were worked out at least once (until then nothing can be skipped).
    @ObservationIgnored private var computed = false

    /// Tickets picked for a bulk action (⌘-click, ⇧-click); cards and rows draw them selected.
    public internal(set) var selectedIds: Set<String> = []
    /// The ticket picked last: where a ⇧-click starts its range.
    var selectionAnchor: String?
    /// Picking mode, turned on from the board's Select button: a plain click picks instead of opening, and cards and
    /// rows show a checkbox.
    public internal(set) var isSelecting = false

    var memory: [String: FilterState] = [:]
    var setAside: [String: FilterState] = [:]
    var activeKey: String?
    private var tasks: [Task<Void, Never>] = []
    private var loadingTask: Task<Void, Never>?

    public init(services: AppServices, nav: AppNavController, registry: ToolRegistry,
                savedFilters: SavedFilterRepository = SavedFilterStorage.shared) {
        self.services = services; self.nav = nav; self.registry = registry; savedFilterRepo = savedFilters
    }

    /// Starts watching the repositories (idempotent). Call from `.task` / `onAppear` of the board host.
    public func start() {
        guard tasks.isEmpty else { return }
        tasks = [
            Task { [weak self] in
                guard let s = self?.services.tickets.watchTickets() else { return }
                for await v in s { self?.tickets = v }
            },
            Task { [weak self] in
                guard let s = self?.services.workspaces.watchAccounts() else { return }
                for await v in s { self?.accounts = Dictionary(v.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a }) }
            },
            Task { [weak self] in
                guard let s = self?.services.workspaces.watchWorkspaces() else { return }
                for await v in s { self?.workspaces = Dictionary(v.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a }) }
            },
            Task { [weak self] in
                guard let s = self?.services.workspaces.watchProjects() else { return }
                for await v in s { self?.projects = Dictionary(v.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a }) }
            },
            Task { [weak self] in
                guard let s = self?.services.settings.watch() else { return }
                for await v in s { self?.settings = v }
            },
            Task { [weak self] in
                guard let s = self?.savedFilterRepo.watchSavedFilters() else { return }
                for await v in s { self?.savedFilters = v }
            },
        ]
        watchSort()
        pulse()
    }

    /// The card order is the session's (`AppNavController.boardSort`, shared by every board): a change re-sorts.
    private func watchSort() {
        withObservationTracking { _ = nav.boardSort } onChange: { [weak self] in
            Task { @MainActor [weak self] in
                guard let self, !self.tasks.isEmpty else { return }
                self.recompute(); self.watchSort()
            }
        }
    }

    public func stop() { tasks.forEach { $0.cancel() }; tasks = []; loadingTask?.cancel() }

    /// Shows the board skeleton for ~480 ms (Flutter `BoardLoading.pulse`).
    public func pulse() {
        loading = true
        loadingTask?.cancel()
        loadingTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(480))
            if !Task.isCancelled { self?.loading = false }
        }
    }

    // MARK: Derivations

    var accountWorkspace: [String: String] { accounts.mapValues(\.workspaceId) }

    /// The query `FilterTickets` / `BuildBoard` run on.
    public var boardQuery: BoardQuery {
        BoardQuery(tickets: scoped, filter: filter, accountWorkspace: accountWorkspace, now: Date(),
                   workspaceOrder: workspaces.keys.sorted(), accounts: accounts, sort: nav.boardSort)
    }

    func recompute() {
        guard isActive else { stale = true; return }
        apply(scoped: scope())
    }

    /// The store's tickets changed, or the tool scoped again (a page of another view arrived). A sync writes tickets of
    /// every board; when those in this board's scope are the same as before, nothing it shows changes, so nothing is
    /// rebuilt or redrawn (it used to rebuild and redraw the whole board on every write, which stuttered while a sync ran).
    private func ticketsChanged() {
        guard isActive else { stale = true; return }
        let next = scope()
        if computed, !stale, next == scoped { describeForPerformanceLog(); return }
        apply(scoped: next)
    }

    private func scope() -> [Ticket] {
        let all = tickets.count
        return PerformanceLog.measureSync("board: scope \(perfName)", detail: "of \(all) tickets") {
            scopedTicketsOverride ?? scopeTickets?(tickets) ?? tickets
        }
    }

    private func apply(scoped next: [Ticket]) {
        stale = false; computed = true
        revision &+= 1
        scoped = next
        board = PerformanceLog.measureSync("board: build \(perfName)", detail: "\(scoped.count) tickets") { BuildBoard()(boardQuery) }
        resultCount = board.total
        describeForPerformanceLog()
    }

    /// While the board is on screen, the performance log says how much it holds with each entry.
    private func describeForPerformanceLog() {
        guard PerformanceLog.isEnabled, perfName != "board" else { return }
        PerformanceLog.setContext("board.\(perfName)", isActive ? "\(perfName): \(scoped.count) of \(tickets.count) tickets in scope" : nil)
    }

    /// Facet groups (with counts) for the tickets in scope.
    public func facets(catalog: BoardFacetCatalog? = nil) -> BoardFacets {
        facetScope == .none ? .empty : DeriveBoardFacets()(BoardFacetsInput(tickets: scoped, scope: facetScope, catalog: catalog))
    }

    /// Provider / account / project ids present in scope (the generic filter groups offer only those).
    public var genericScope: (providers: Set<ProviderType>, accountIds: Set<String>, projectIds: Set<String>) {
        (Set(scoped.map(\.providerType)), Set(scoped.map(\.accountId)), Set(scoped.map(\.projectId)))
    }

    public var filterHasGroups: Bool { facetScope != .none || usesFacetFilters || genericScope.projectIds.count >= 2 }

    /// Open assigned-to-me counts for the sources tree.
    public func assignedCounts() -> AssignedCounts {
        CountAssignedToMe()(tickets: tickets, accounts: Array(accounts.values), pinnedProjects: Set(settings.pinnedProjects),
                            pinnedExecutions: Set(settings.pinnedExecutions))
    }

    /// Tool hook: the cached tickets the ⌘K search looks through, narrowed from every ticket. Nil searches only the
    /// tickets in scope (the board on screen); a tool whose boards each show one slice sets it to search its whole account.
    public var searchPool: (([Ticket]) -> [Ticket])?
    /// Tool hook: finds the ticket whose id was typed (`123`, `#123`) when no cached one has it - fetches it from the
    /// server and returns its local ticket id (nil when there is none).
    public var fetchTicketByKey: ((String) async -> String?)?

    /// Quick search over cached tickets (⌘K field): in scope, or in the tool's `searchPool`.
    public func search(_ query: String) -> [Ticket] {
        SearchLocalTickets()(tickets: searchPool?(tickets) ?? scoped, query: query)
    }

    /// The id typed into the search (`123` or `#123`), when that is all it holds.
    public static func ticketKey(typed query: String) -> String? {
        let q = query.trimmingCharacters(in: .whitespaces)
        let digits = q.hasPrefix("#") ? String(q.dropFirst()) : q
        return !digits.isEmpty && digits.allSatisfy(\.isNumber) ? digits : nil
    }

    // MARK: Actions

    public func openTicket(_ id: String) { nav.openTicket(id) }
    /// The ticket open at the boards' place, to mark its card (also while another place is on screen).
    public var openTicketId: String? { nav.toolOpenTicketId }

    /// Drag & drop a card onto a column: writes the new status to the DB (the board reacts to the change).
    public func moveTicket(_ id: String, to status: UnifiedStatus) {
        Task { _ = await services.tickets.moveTicket(id: id, to: status) }
    }

    public func beginAction(_ id: String) { pendingTicketIds.insert(id) }
    public func endAction(_ id: String) { pendingTicketIds.remove(id) }

    public func setBoardLayout(_ layout: BoardLayout) { updateSettings { $0.boardLayout = layout } }
    public func setTableColumnWidth(_ key: String, _ width: Double?) { updateSettings { $0.tableColumnWidths[key] = width } }

    func updateSettings(_ change: (inout AppSettings) -> Void) {
        var s = settings; change(&s); settings = s
        Task { _ = await services.settings.save(s) }
    }

    /// The workspace colour of a ticket's account (fallback grey is the caller's).
    public func workspaceColorValue(of ticket: Ticket) -> Int? {
        accounts[ticket.accountId].flatMap { workspaces[$0.workspaceId]?.colorValue }
    }
}
