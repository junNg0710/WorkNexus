/// Ported from: lib/core/di/locator.dart (the ZenTao slice of `getIt` that tools/zentao/presentation reads through providers)
import CoreDomain
import CoreTools
import Foundation

/// Everything the ZenTao tool's Presentation layer needs, as interfaces only (rules 1.3 / 8.2). The composition root
/// builds it once - either from the `ZentaoModuleData.Wiring` it got from `ZentaoModuleData.wire(...)` (see
/// `init(wiring:...)`) or field by field - and hands it to `ZentaoModule`.
public struct ZentaoDependencies {
    public let services: AppServices
    public let nav: AppNavController
    /// The registry the module is registered in (the boards need it for `BoardController`); a closure because the
    /// registry is built from the modules.
    public let registry: @MainActor () -> ToolRegistry
    /// Products / projects / executions, one ticket fetch (`fetchZenTaoTicket`), messages.
    public let tickets: ZenTaoTicketService
    /// Pages of the server-side bug / task views (the paged boards).
    public let viewPages: ZenTaoViewPages
    /// Brings a task's related bugs into the local database.
    public let taskBugs: ZenTaoTaskBugs
    /// Bug / task forms; the board reads module names and the detail the form lists from it.
    public let editor: ZenTaoTicketEditor
    public let teamMembers: ZenTaoTeamMembers
    /// The team groups a leader follows (kept on this Mac).
    public let teamGroups: ZenTaoTeamGroupRepository
    /// Bug confirm / resolve / close / activate and the task actions (optimistic).
    public let workflow: ZenTaoWorkflowService
    public let docs: ZenTaoDocRepository
    public let exportDoc: ExportZenTaoDoc
    /// The people a leader keeps at the front of the people strip.
    public let pinnedPeople: ZenTaoPinnedPeopleStore
    /// What each account's boards were last scoped to (Only me, a team, or the execution / product).
    public let boardScopes: ZenTaoBoardScopeStore
    /// The people each account handed tickets to lately (the quick Assign menu).
    public let recentAssignees: ZenTaoRecentAssigneesStore
    /// ZenTao's departments as ready-made teams.
    public let departmentTeams: ZenTaoDepartmentTeamSource
    /// The teams kept at the top of the Team menu.
    public let pinnedTeams: ZenTaoPinnedTeamsStore
    /// Adds a module to a board's tree.
    public let moduleEditor: ZenTaoModuleEditor

    public init(services: AppServices, nav: AppNavController, registry: @escaping @MainActor () -> ToolRegistry,
                tickets: ZenTaoTicketService, viewPages: ZenTaoViewPages, taskBugs: ZenTaoTaskBugs,
                editor: ZenTaoTicketEditor, teamMembers: ZenTaoTeamMembers, workflow: ZenTaoWorkflowService,
                docs: ZenTaoDocRepository, exportDoc: ExportZenTaoDoc, teamGroups: ZenTaoTeamGroupRepository = NoTeamGroups(),
                pinnedPeople: ZenTaoPinnedPeopleStore = InMemoryPinnedPeople(),
                boardScopes: ZenTaoBoardScopeStore = InMemoryBoardScopes(),
                recentAssignees: ZenTaoRecentAssigneesStore = InMemoryRecentAssignees(),
                departmentTeams: ZenTaoDepartmentTeamSource = NoDepartmentTeams(),
                pinnedTeams: ZenTaoPinnedTeamsStore = InMemoryPinnedTeams(),
                moduleEditor: ZenTaoModuleEditor = NoZenTaoModuleEditor()) {
        self.services = services; self.nav = nav; self.registry = registry; self.tickets = tickets
        self.viewPages = viewPages; self.taskBugs = taskBugs; self.editor = editor; self.teamMembers = teamMembers
        self.workflow = workflow; self.docs = docs; self.exportDoc = exportDoc; self.teamGroups = teamGroups
        self.pinnedPeople = pinnedPeople; self.boardScopes = boardScopes
        self.recentAssignees = recentAssignees; self.departmentTeams = departmentTeams; self.pinnedTeams = pinnedTeams
        self.moduleEditor = moduleEditor
    }

    /// The usual composition: `wiring` from `ZentaoModuleData.wire(...)`, `workflow` from
    /// `ZentaoModuleData.workflow(sync:workspaces:runner:)`.
    public init(wiring: ZentaoModuleData.Wiring, workflow: ZenTaoWorkflowService, services: AppServices,
                nav: AppNavController, registry: @escaping @MainActor () -> ToolRegistry) {
        self.init(services: services, nav: nav, registry: registry, tickets: wiring.tickets, viewPages: wiring.tickets,
                  taskBugs: wiring.tickets, editor: wiring.editor, teamMembers: wiring.teamMembers, workflow: workflow,
                  docs: wiring.docs, exportDoc: ZentaoModuleData.exportDoc(wiring.docs), teamGroups: wiring.teamGroups,
                  pinnedPeople: wiring.pinnedPeople, boardScopes: wiring.boardScopes,
                  recentAssignees: wiring.recentAssignees, departmentTeams: wiring.departmentTeams, pinnedTeams: wiring.pinnedTeams,
                  moduleEditor: wiring.modules)
    }

    /// Opens ZenTao ticket `type` (`task`, `story`, `bug`) `id` linked from `from` in the detail panel, on `from`'s
    /// account and host, fetching it from ZenTao first when it has not been synced (Flutter `openZenTaoLinked`).
    @MainActor
    public func openLinked(from: Ticket, type: String, id: String) async -> Outcome<Void> {
        let host = URL(string: from.url ?? "")?.host ?? ""
        let local = zenTaoTicketId(accountId: from.accountId, type: type, id: id)
        if case .success(let t) = await services.tickets.ticket(id: local), t != nil {
            nav.openTicket(local)
            return .success(())
        }
        switch await tickets.fetchZenTaoTicket(host: host, type: type, id: id) {
        case .success(let ticketId): nav.openTicket(ticketId); return .success(())
        case .failure(let f): return .failure(f)
        }
    }

    /// The account of `id` (first value of the workspace repository's account stream).
    public func account(id: String) async -> Account? {
        var it = services.workspaces.watchAccounts().makeAsyncIterator()
        return await it.next()?.first { $0.id == id }
    }
}
