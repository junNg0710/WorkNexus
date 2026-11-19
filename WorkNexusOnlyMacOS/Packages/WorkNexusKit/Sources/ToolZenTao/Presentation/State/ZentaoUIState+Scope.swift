/// Ported from: lib/tools/zentao/presentation/providers/zentao_scope_providers.dart (+ keep_bug_board_product /
/// keep_task_board_scope utils, zentao_scope_title_provider.dart)
import CoreDomain
import CoreTools
import Foundation
import SharedKit

extension ZentaoUIState {
    /// The rail's account and the open scope. The product / execution selections apply only while they match this
    /// place: another account, or a scope reset to "All", must not keep showing them.
    var place: (accountId: String?, scopeId: String?) {
        let s = deps.nav.state
        guard case .account(let id) = s.rail else { return (nil, nil) }
        return (id, s.locations[id]?.scopeId)
    }

    /// The tasks the Tasks section shows before the user's filters: the open execution's cached tasks, narrowed
    /// view by view to what each status view has loaded. Tasks are listed per execution: none until one is picked.
    func scopeTasks(_ tickets: [Ticket]) -> [Ticket] {
        let place = place
        // A team replaces the execution: the tasks read from each person, wherever they are.
        if let team = taskTeam {
            guard team.accountId == place.accountId else { return [] }
            // Routine executions (daily reports) stay out of it; they are seen by opening the execution.
            let choices = taskBoard.settings.teamExecutionVisibility, shown = IsShownInTeamView()
            return team.tickets(in: tickets, bugs: false).filter { t in
                guard case .zentaoTask(let e)? = t.providerEntity else { return true }
                return shown(accountId: t.accountId, executionId: e.execution, executionName: e.executionName, choices: choices)
            }
        }
        guard let e = execution, e.accountId == place.accountId, e.executionId == place.scopeId else { return [] }
        return ScopePagedViewTickets<ZenTaoTaskColumn>()(PagedViewScopeQuery(
            tickets: ScopeProviderTickets()(tickets: tickets, accountId: e.accountId, providerType: .zentao, externalType: "task",
                                            slice: nil, membershipLabel: zentaoExecutionLabel(e.executionId)),
            loads: taskStreams.loads, viewOf: zentaoTaskColumnFor))
    }

    /// The bugs the Bugs section shows before the user's filters: the cached bugs tagged with the open product,
    /// narrowed view by view to what each bug view has loaded. The Tasks board's execution does not narrow it: the two
    /// boards keep their own scope, so going from one to the other changes neither.
    func scopeBugs(_ tickets: [Ticket]) -> [Ticket] {
        let place = place
        if let team = bugTeam { return team.accountId == place.accountId ? team.tickets(in: tickets, bugs: true) : [] }
        guard let product, product.accountId == place.accountId, product.productId == place.scopeId else { return [] }
        let related = bugRelated
        var tickets = tickets
        // Until Related to me's view loads, its cached bugs are those that concern the user locally.
        if related, let account = bugBoard.accounts[product.accountId], !(bugStreams.views[.relatedToMe]?.started ?? false) {
            tickets = tickets.filter { IsRelatedToMe()($0, account) }
        }
        return ScopePagedViewTickets<ZenTaoBugStream>()(PagedViewScopeQuery(
            tickets: ScopeProviderTickets()(tickets: tickets, accountId: product.accountId, providerType: .zentao,
                                            externalType: "bug", slice: nil, membershipLabel: zentaoProductLabel(product.productId)),
            loads: bugStreams.loads, viewOf: { ZenTaoBugStream.of(zentaoBugColumnFor($0), related: related) },
            columnOf: { AnyHashable(zentaoBugColumnFor($0)) }))
    }

    /// The name of what a ZenTao board is scoped to - the picked execution, else the product (bugs).
    public func scopeTitle(accountId: String, scopeId: String?, bugs: Bool) -> String? {
        let exec = execution?.accountId == accountId ? execution : nil
        if !bugs { return exec?.executionId == scopeId ? exec?.executionName : nil }
        if let p = product, p.accountId == accountId, p.productId == scopeId { return p.productName }
        guard let scopeId else { return nil }
        return products[accountId]?.value?.first { $0.id == scopeId }?.name
    }

    /// Keeps the Bugs board on a product of `account`: ZenTao lists bugs per product only, so there is no board
    /// without one. The scope's product when it has one; otherwise a pinned product, else the first. Idempotent;
    /// call from the section's `.task` while it is on screen.
    public func keepBugBoardProduct(account: Account, location: ToolLocation) {
        loadProducts(account.id)
        guard let list = products[account.id]?.value, !list.isEmpty else { return }
        let scoped = list.first { $0.id == location.scopeId }
        let pinned = Set(bugBoard.settings.pinnedProjects)
        let pick = scoped ?? list.first { pinned.contains("\(account.id):\($0.id)") } ?? list[0]
        // Product ids are per server: another account's product 1 is not this one.
        let current = product?.accountId == account.id && product?.productId == pick.id
        if scoped != nil && current { return }
        // The Tasks board's execution is left alone: it does not narrow the bugs.
        if scoped == nil { deps.nav.setScope(pick.id, accountId: account.id) }
        selectProduct(pick)
        bugBoard.openBoard(bugBoard.currentBoardKey)
        rescope()
    }

    /// Whether the Tasks board of `account` at `location` has its execution: tasks are listed per execution only.
    public func taskBoardHasExecution(account: Account, location: ToolLocation) -> Bool {
        location.scopeId != nil && execution?.accountId == account.id && execution?.executionId == location.scopeId
    }

    /// Keeps the Tasks board on an execution: the one picked while it still is; else a pinned execution of the
    /// account (the scope's own when pinned); else the first execution of the first project, loaded on demand.
    /// Never a project: it holds executions, not a task list. Idempotent; call from the section's `.task`.
    public func keepTaskBoardScope(account: Account, location: ToolLocation) {
        if taskBoardHasExecution(account: account, location: location) { return }
        loadProjects(account.id)
        let pinned = taskBoard.settings.pinnedExecutions.compactMap { key -> String? in
            key.hasPrefix("\(account.id):") ? String(key.dropFirst(account.id.count + 1)) : nil
        }
        for p in projects[account.id]?.value ?? [] { loadExecutions(accountId: account.id, projectId: p.id) }
        let known = (projects[account.id]?.value ?? []).flatMap { executions["\(account.id):\($0.id)"]?.value ?? [] }
        var pick: ProviderExecution?
        if !pinned.isEmpty {
            let id = pinned.first { $0 == location.scopeId } ?? pinned[0]
            pick = known.first { $0.id == id }
        }
        if pick == nil, let first = projects[account.id]?.value?.first {
            pick = executions["\(account.id):\(first.id)"]?.value?.first
        }
        guard let pick else { return }
        deps.nav.setScope(pick.id, accountId: account.id)
        selectExecution(pick)
        taskBoard.openBoard(taskBoard.currentBoardKey)
        rescope()
    }
}
