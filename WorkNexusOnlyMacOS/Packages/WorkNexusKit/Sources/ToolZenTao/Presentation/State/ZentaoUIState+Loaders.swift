/// Ported from: lib/tools/zentao/presentation/providers/{zentao_board_providers (products / projects / executions),
/// bug_module_names_provider,task_module_names_provider,zentao_facet_catalog_provider}.dart
import CoreDomain
import Foundation
import SharedKit

extension ZentaoUIState {
    static func executionsKey(_ accountId: String, _ projectId: String) -> String { "\(accountId):\(projectId)" }

    /// Loads the account's products once (cached list first, then the server's); `force` fetches again.
    public func loadProducts(_ accountId: String, force: Bool = false) {
        if !force, products[accountId] != nil { return }
        if products[accountId] == nil { products[accountId] = .loading }
        Task {
            let stored = await deps.tickets.cachedProducts(accountId: accountId)
            if let stored { products[accountId] = .loaded(stored) }
            switch await deps.tickets.listProducts(accountId: accountId) {
            case .success(let v): products[accountId] = .loaded(v)
            case .failure(let f): if stored == nil { products[accountId] = .failed(f) }
            }
        }
    }

    public func loadProjects(_ accountId: String, force: Bool = false) {
        if !force, projects[accountId] != nil { return }
        if projects[accountId] == nil { projects[accountId] = .loading }
        Task {
            let stored = await deps.tickets.cachedProjects(accountId: accountId)
            if let stored { projects[accountId] = .loaded(stored) }
            switch await deps.tickets.listProjects(accountId: accountId) {
            case .success(let v): projects[accountId] = .loaded(v)
            case .failure(let f): if stored == nil { projects[accountId] = .failed(f) }
            }
        }
    }

    /// The executions of one project (fetched on first ask; `force` / a failed load fetch again).
    public func loadExecutions(accountId: String, projectId: String, force: Bool = false) {
        let key = Self.executionsKey(accountId, projectId)
        if !force, let cur = executions[key], cur.failure == nil { return }
        executions[key] = .loading
        Task {
            switch await deps.tickets.listProjectExecutions(accountId: accountId, projectId: projectId) {
            case .success(let v): executions[key] = .loaded(v)
            case .failure(let f): executions[key] = .failed(f)
            }
        }
    }

    public func executionsOf(accountId: String, projectId: String) -> ZentaoLoad<[ProviderExecution]>? {
        executions[Self.executionsKey(accountId, projectId)]
    }

    // MARK: Module names

    private func moduleKey(_ bugs: Bool) -> (key: String, accountId: String, id: String)? {
        if bugs, let p = product { return ("b:\(p.accountId):\(p.productId)", p.accountId, p.productId) }
        if !bugs, let e = execution { return ("t:\(e.accountId):\(e.executionId)", e.accountId, e.executionId) }
        return nil
    }

    /// A product's bug modules / an execution's task modules as id -> path ("Livestream/Share"), from the bug or task
    /// form's module list. Kept once loaded (the list costs a whole form page); a failed fetch is retried on reopen.
    public func loadModuleNames(bugs: Bool) {
        guard let (key, accountId, id) = moduleKey(bugs) else { return }
        if let cur = moduleNames[key], cur.failure == nil { return }
        moduleNames[key] = .loading
        Task {
            let paths: Outcome<[FormOption]>
            if bugs { paths = await deps.editor.bugModules(accountId: accountId, productId: id) }
            else { paths = await deps.editor.taskOptions(accountId: accountId, executionId: id).map(\.modules) }
            switch paths {
            case .success(let list):
                moduleNames[key] = .loaded(list.map { ZentaoModulePath(id: $0.value, path: Self.stripLeadingSlash($0.label)) })
            case .failure(let f): moduleNames[key] = .failed(f)
            }
        }
    }

    /// The module names of the board on screen (the bug board's product when `bugs`, else the task board's execution).
    public func boardModuleNames(bugs: Bool) -> ZentaoLoad<[ZentaoModulePath]> {
        guard let (key, _, _) = moduleKey(bugs) else { return .loaded([]) }
        return moduleNames[key] ?? .loading
    }

    static func stripLeadingSlash(_ s: String) -> String { s.hasPrefix("/") ? String(s.dropFirst()) : s }

    // MARK: Board members + facet catalog

    /// Loads the people of the open board's product / execution (for the assignee / opener facet choices).
    public func loadBoardMembers(bugs: Bool) {
        // A team brings its own people (`openTeam`).
        guard team(bugs: bugs) == nil, let (key, accountId, id) = moduleKey(bugs), membersFor != key else { return }
        membersFor = key
        Task {
            let r = bugs ? await deps.teamMembers.productMembers(accountId: accountId, productId: id)
                         : await deps.teamMembers.executionMembers(accountId: accountId, executionId: id)
            if membersFor == key { boardMembers = r.value ?? [] }
        }
    }

    /// Every choice the bug board (`bugs`) or task board can be filtered by.
    public func facetCatalog(bugs: Bool) -> BoardFacetCatalog {
        BuildZenTaoFacetCatalog()(ZenTaoFacetCatalogInput(bugs: bugs, members: boardMembers,
                                                           modules: orderedModules(bugs: bugs)))
    }

    private func orderedModules(bugs: Bool) -> [ZentaoModulePath] { boardModuleNames(bugs: bugs).value ?? [] }
}
