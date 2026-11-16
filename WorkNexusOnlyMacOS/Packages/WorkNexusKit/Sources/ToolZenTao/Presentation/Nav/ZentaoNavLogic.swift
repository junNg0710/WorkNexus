/// Ported from: lib/tools/zentao/presentation/nav/{zentao_bug_module_pane,zentao_task_module_pane,zentao_pinned_branch}.dart,
/// widgets/{zentao_product_popover_list,zentao_execution_list}.dart and providers/zentao_module_tree_provider.dart.
/// The decisions of the ZenTao nav pane, as pure functions of values so they are tested without a view or a database:
/// which rows the Bugs / Tasks panes list and in what order, how the pins are toggled, what the module tree counts,
/// and what the product / execution pickers offer for a search and a Mine / Others tab.
import CoreDomain
import Foundation
import SharedKit

/// The two tabs of the product and execution pickers: where the user has work, and everything else.
enum ZentaoPickerTab: Hashable { case mine, others }

/// One product of the picker with the open bugs it holds.
struct ZentaoProductChoice: Identifiable, Equatable {
    let product: ProviderProduct
    let openCount: Int
    var id: String { product.id }
}

/// One project of the picker with the open tasks it holds.
struct ZentaoProjectChoice: Identifiable, Equatable {
    let project: ProviderProject
    let openCount: Int
    var id: String { project.id }
}

enum ZentaoNavLogic {
    // MARK: Pins

    /// Pinned products are stored as bare `accountId:productId` keys.
    static func productKey(accountId: String, productId: String) -> String { "\(accountId):\(productId)" }
    /// Pinned executions are stored as `accountId:executionId` (the execution id is unique within an account).
    static func executionKey(accountId: String, executionId: String) -> String { "\(accountId):\(executionId)" }

    /// `keys` with `key` removed when it is there, else appended (a pin keeps its place among the others).
    static func toggled(_ keys: [String], _ key: String) -> [String] {
        var next = keys
        if let i = next.firstIndex(of: key) { next.remove(at: i) } else { next.append(key) }
        return next
    }

    /// The execution ids pinned for `accountId`, in pin order.
    static func pinnedExecutionIds(_ pinned: [String], accountId: String) -> [String] {
        let prefix = "\(accountId):"
        return pinned.compactMap { $0.hasPrefix(prefix) ? String($0.dropFirst(prefix.count)) : nil }
    }

    // MARK: Pane rows

    /// The Bugs pane's products: the open one first when it is not pinned (so opening a product never reorders
    /// the pinned ones), then the pinned ones in the account's product order.
    static func productRows(products: [ProviderProduct], pinned: [String], accountId: String, openId: String?) -> [ProviderProduct] {
        let keys = Set(pinned)
        func isPinned(_ p: ProviderProduct) -> Bool { keys.contains(productKey(accountId: accountId, productId: p.id)) }
        return products.filter { $0.id == openId && !isPinned($0) } + products.filter(isPinned)
    }

    /// The Tasks pane's executions: the open one first when it is not pinned, then the pinned ones in the order they
    /// were pinned. A pin carries only its key, so it is resolved against the executions loaded so far; one that
    /// is not (yet) loaded, or no longer exists, is left out.
    static func executionRows(open: ProviderExecution?, pinned: [String], known: [ProviderExecution], accountId: String) -> [ProviderExecution] {
        let ids = pinnedExecutionIds(pinned, accountId: accountId)
        var rows: [ProviderExecution] = []
        if let open, !ids.contains(open.id) { rows.append(open) }
        var seen = Set<String>()
        for id in ids where seen.insert(id).inserted {
            if let e = known.first(where: { $0.id == id && $0.accountId == accountId }) { rows.append(e) }
        }
        return rows
    }

    /// The pinned execution ids of `accountId` that none of the `known` executions matches (and that are not the open one).
    /// Only meaningful once every execution list is in (`ZentaoLoad` loaded): such a pin points at an execution that no
    /// longer exists, so the pane lists it as a dead row the user can unpin - Flutter's pins carried their own name.
    static func staleExecutionIds(open: ProviderExecution?, pinned: [String], known: [ProviderExecution], accountId: String) -> [String] {
        var seen = Set<String>()
        return pinnedExecutionIds(pinned, accountId: accountId).filter { id in
            seen.insert(id).inserted && id != open?.id && !known.contains { $0.id == id && $0.accountId == accountId }
        }
    }

    // MARK: Module tree

    /// Identity of the module list on screen: changes when the board's product / execution does, so the pane loads
    /// the new module names.
    static func moduleScopeKey(bugs: Bool, product: ZentaoProductSelection?, execution: ZentaoExecutionSelection?) -> String {
        if bugs, let p = product { return "b:\(p.accountId):\(p.productId)" }
        if !bugs, let e = execution { return "t:\(e.accountId):\(e.executionId)" }
        return "none"
    }

    /// The module tree of the board on screen, counted from the tickets the board would show with every filter but
    /// the module one: its columns, so a view without Closed does not count closed bugs.
    static func moduleTree(bugs: Bool, query: BoardQuery, bugTab: ZenTaoBugBrowseType, dueThisWeek: Bool,
                           paths: [ZentaoModulePath], hideEmpty: Bool) -> ZenTaoModuleTree {
        var unpickedFilter = query.filter
        unpickedFilter.modules = []
        let unpicked = query.withFilter(unpickedFilter)
        let shown: [Ticket] = bugs
            ? BuildZenTaoBugBoard(includeClosed: bugTab == .all)(unpicked).columns.flatMap(\.tickets)
            : BuildZenTaoTaskBoard(dueThisWeekOnly: dueThisWeek)(unpicked).columns.flatMap(\.tickets)
        let picked = query.filter.modules
        return BuildZenTaoModuleTree()(paths: paths.map { (id: $0.id, path: $0.path) }, tickets: shown, hideEmpty: hideEmpty,
                                       selected: picked.count == 1 ? picked.first : nil)
    }

    // MARK: Pickers

    private static func matches(_ search: String, _ texts: [String?]) -> Bool {
        let q = search.trimmingCharacters(in: .whitespaces).lowercased()
        return q.isEmpty || texts.contains { ($0 ?? "").lowercased().contains(q) }
    }

    /// Most open work first, then by name.
    private static func ordered<T>(_ items: [(T, Int)], name: (T) -> String) -> [(T, Int)] {
        items.sorted { a, b in
            a.1 != b.1 ? a.1 > b.1 : name(a.0).lowercased() < name(b.0).lowercased()
        }
    }

    /// The products the picker lists for `search` and `tab`. Mine: products with bugs assigned to the user (ZenTao
    /// has no notion of a "zone"); Others: the rest. Each carries its open bug count.
    static func productChoices(products: [ProviderProduct], tickets: [Ticket], account: Account?, accountId: String,
                               search: String, tab: ZentaoPickerTab) -> [ZentaoProductChoice] {
        var open: [String: Int] = [:], mine = Set<String>()
        let assigned = IsAssignedToMe()
        for t in tickets where t.accountId == accountId {
            guard case .zentaoBug(let b) = t.providerEntity, let product = b.product else { continue }
            if t.status != .done { open[product, default: 0] += 1 }
            if let account, assigned(t, account) { mine.insert(product) }
        }
        let rows = products.filter { p in
            matches(search, [p.name]) && (mine.contains(p.id) == (tab == .mine))
        }.map { ($0, open[$0.id] ?? 0) }
        return ordered(rows) { $0.name }.map { ZentaoProductChoice(product: $0.0, openCount: $0.1) }
    }

    /// Whether `t` is a task of ZenTao project `projectId` (information only: a project is never a task board).
    static func isTask(_ t: Ticket, inProject projectId: String) -> Bool {
        if case .zentaoTask(let e) = t.providerEntity { return e.project == projectId }
        return false
    }

    /// The projects the picker lists for `search` (name or program) and `tab`. Mine: projects where the user has
    /// tasks assigned; Others: the rest. Each carries its open task count.
    static func projectChoices(projects: [ProviderProject], tickets: [Ticket], account: Account?, accountId: String,
                               search: String, tab: ZentaoPickerTab) -> [ZentaoProjectChoice] {
        var open: [String: Int] = [:], mine = Set<String>()
        let assigned = IsAssignedToMe()
        for t in tickets where t.accountId == accountId {
            guard case .zentaoTask(let e) = t.providerEntity, let project = e.project else { continue }
            if t.status != .done { open[project, default: 0] += 1 }
            if let account, assigned(t, account) { mine.insert(project) }
        }
        let rows = projects.filter { p in
            matches(search, [p.name, p.programName]) && (mine.contains(p.id) == (tab == .mine))
        }.map { ($0, open[$0.id] ?? 0) }
        return ordered(rows) { $0.name }.map { ZentaoProjectChoice(project: $0.0, openCount: $0.1) }
    }
}
