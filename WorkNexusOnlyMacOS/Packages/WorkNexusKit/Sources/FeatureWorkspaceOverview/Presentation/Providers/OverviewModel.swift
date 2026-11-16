/// Ported from: lib/features/workspace_overview/presentation/providers/{dashboard_providers,overview_providers}.dart
import CoreDomain
import CoreTools
import CoreUI
import Foundation
import Observation

/// Fetch state of one account's dashboard / assigned-work sync (Flutter: the `AsyncValue` of the refresh providers).
public enum FetchState: Equatable, Sendable {
    case idle, loading
    case failed(String)

    public var isLoading: Bool { self == .loading }
    public var hasFailed: Bool { if case .failed = self { true } else { false } }
}

/// The full "my work" list shown in place of the Overview: whose and which kind first.
public struct MyWorkTarget: Equatable, Sendable {
    public var account: Account
    public var kind: DashboardItemKind
    public init(account: Account, kind: DashboardItemKind) { self.account = account; self.kind = kind }
}

/// Reactive snapshot of everything the overview pages render, fed by the local database (local-first) through an
/// `OverviewRepository`, plus the commands the pages invoke (refresh, sync, open an item, navigate).
@MainActor @Observable
public final class OverviewModel {
    public private(set) var workspace: Workspace?
    /// Accounts of the active workspace.
    public private(set) var accounts: [Account] = []
    public private(set) var tickets: [Ticket] = []
    /// Open work assigned to the user or awaiting their review, across all tools of the workspace.
    public private(set) var assignedWork: [AssignedWorkItem] = []
    public private(set) var dashboards: [String: ZenTaoDashboard] = [:]
    public private(set) var dashboardState: [String: FetchState] = [:]
    public private(set) var workSyncState: [String: FetchState] = [:]
    public private(set) var dateFormat = "iso"
    /// The full "my work" list opened from a ZenTao section's "Show all" (nil = the Overview).
    public var myWorkTarget: MyWorkTarget?
    /// Whether the full "my work" list shows only unfinished items.
    public var openOnly = true

    public let nav: AppNavController
    public let registry: ToolRegistry
    let refreshDashboard: RefreshDashboard
    let syncAssignedWork: SyncAssignedWork
    let openDashboardItem: OpenDashboardItem
    private let repository: OverviewRepository
    private let activeWorkspaceId: String?
    private var allAccounts: [Account] = []
    private var tasks: [Task<Void, Never>] = []
    private var dashboardTasks: [String: Task<Void, Never>] = [:]

    /// - Parameter activeWorkspaceId: the workspace the overview shows; the first one when nil (as the shell does).
    public init(repository: OverviewRepository, nav: AppNavController, registry: ToolRegistry, activeWorkspaceId: String? = nil,
                refreshDashboard: RefreshDashboard? = nil) {
        self.repository = repository; self.nav = nav; self.registry = registry; self.activeWorkspaceId = activeWorkspaceId
        self.refreshDashboard = refreshDashboard ?? RefreshDashboard(repository)
        syncAssignedWork = SyncAssignedWork(repository)
        openDashboardItem = OpenDashboardItem(repository)
    }

    public func start() {
        guard tasks.isEmpty else { return }
        tasks = [
            Task { [weak self] in
                guard let s = self?.repository.watchWorkspaces() else { return }
                for await v in s { self?.setWorkspaces(v) }
            },
            Task { [weak self] in
                guard let s = self?.repository.watchAccounts() else { return }
                for await v in s { self?.setAccounts(v) }
            },
            Task { [weak self] in
                guard let s = self?.repository.watchTickets() else { return }
                for await v in s { self?.setTickets(v) }
            },
            Task { [weak self] in
                guard let s = self?.repository.watchDateFormat() else { return }
                for await v in s { self?.dateFormat = v }
            },
        ]
    }

    public func stop() {
        tasks.forEach { $0.cancel() }; tasks = []
        dashboardTasks.values.forEach { $0.cancel() }; dashboardTasks = [:]
    }

    // MARK: state feeds

    func setWorkspaces(_ v: [Workspace]) {
        workspace = activeWorkspaceId.flatMap { id in v.first { $0.id == id } } ?? v.first
        recompute()
    }
    func setAccounts(_ v: [Account]) { allAccounts = v; recompute() }
    func setTickets(_ v: [Ticket]) { tickets = v; recompute() }

    private func recompute() {
        accounts = workspace.map { ws in allAccounts.filter { $0.workspaceId == ws.id } } ?? allAccounts
        assignedWork = ListAssignedWork()(tickets: tickets, accounts: accounts)
        watchDashboards()
        if let target = myWorkTarget, !accounts.contains(where: { $0.id == target.account.id }) { myWorkTarget = nil }
    }

    /// One live dashboard stream per ZenTao account of the workspace.
    private func watchDashboards() {
        let ids = Set(accounts.filter { $0.providerType == .zentao }.map(\.id))
        for id in dashboardTasks.keys where !ids.contains(id) { dashboardTasks[id]?.cancel(); dashboardTasks[id] = nil }
        for id in ids where dashboardTasks[id] == nil {
            dashboardTasks[id] = Task { [weak self] in
                guard let s = self?.repository.watchDashboard(accountId: id) else { return }
                for await d in s { self?.dashboards[id] = d }
            }
        }
    }

    // MARK: derived lists

    /// Every stored ticket of `kind` assigned to the account's user.
    public func myWork(_ account: Account, _ kind: DashboardItemKind, openOnly: Bool) -> [Ticket] {
        FilterMyWork()(tickets, accountId: account.id, userAccount: account.handle, kind: kind, openOnly: openOnly)
    }

    /// The user's open tasks or bugs of an account, in progress first, then not started.
    public func queue(_ account: Account, _ kind: DashboardItemKind) -> WorkQueue {
        BuildWorkQueue()(myWork(account, kind, openOnly: true))
    }

    public func dashboard(_ accountId: String) -> ZenTaoDashboard? { dashboards[accountId] }

    // MARK: commands

    /// Brings an account's section up to date when it appears: the assigned work syncs once per session, the
    /// dashboard refetches only when stale.
    public func prepare(_ account: Account) async {
        await syncMyWork(account.id, force: false)
        await loadDashboard(account.id, force: false)
    }

    public func loadDashboard(_ accountId: String, force: Bool) async {
        if dashboardState[accountId]?.isLoading == true { return }
        dashboardState[accountId] = .loading
        switch await refreshDashboard(accountId, force: force) {
        case .success: dashboardState[accountId] = .idle
        case .failure(let f): dashboardState[accountId] = .failed(f.message)
        }
    }

    public func syncMyWork(_ accountId: String, force: Bool) async {
        if workSyncState[accountId]?.isLoading == true { return }
        if !force, await syncAssignedWork.hasStarted(accountId) { return }
        workSyncState[accountId] = .loading
        switch await syncAssignedWork(accountId, force: force) {
        case .success: workSyncState[accountId] = .idle
        case .failure(let f): workSyncState[accountId] = .failed(f.message)
        }
    }

    /// The refresh button: the dashboard and the assigned work again.
    public func refresh(_ account: Account) async {
        async let a: Void = loadDashboard(account.id, force: true)
        async let b: Void = syncMyWork(account.id, force: true)
        _ = await (a, b)
    }

    /// Opens ZenTao `kind` `id` of `account` in the detail panel; false when it could not be loaded.
    @discardableResult
    public func open(_ account: Account, kind: DashboardItemKind, id: String) async -> Bool {
        switch await openDashboardItem(account: account, kind: kind, id: id) {
        case .success(let ticketId): nav.openTicket(ticketId); return true
        case .failure: return false
        }
    }

    /// Opens the item, showing an error toast when it could not be loaded.
    public func open(_ account: Account, kind: DashboardItemKind, id: String, toasts: AppToastController?) async {
        if await !open(account, kind: kind, id: id) { toasts?.show(OL.dashboardOpenFailed, kind: .error) }
    }

    // MARK: navigation

    public func openTicket(_ id: String) { nav.openTicket(id) }

    /// The account in its tool, optionally in one of its sections.
    public func select(_ account: Account, section: SectionID? = nil) {
        nav.select(.account(account.id))
        if let section { nav.setSection(section, accountId: account.id) }
    }

    /// The Integrations page (where tools are connected and managed).
    public func openIntegrations() { nav.setWorkspaceSection("integrations") }
}
