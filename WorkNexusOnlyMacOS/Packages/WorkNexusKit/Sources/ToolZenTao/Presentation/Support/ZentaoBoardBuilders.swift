/// Ported from: lib/tools/zentao/domain/usecases/{build_zentao_bug_board,build_zentao_task_board,build_zentao_facet_catalog,
/// compute_zentao_metrics}.dart. Pure functions; they sit in Presentation only because the Domain folder of this tool
/// is not editable in this pass (they depend on SharedKit's `BoardQuery` / facet types and CoreTools' `ToolMetrics`).
import CoreDomain
import CoreTools
import CoreUI
import Foundation
import SharedKit

public struct ZenTaoBugBoardColumn: Identifiable {
    public let column: ZenTaoBugColumn
    public let tickets: [Ticket]
    public var id: ZenTaoBugColumn { column }
    public var count: Int { tickets.count }
}

public struct ZenTaoBugBoardModel {
    public var columns: [ZenTaoBugBoardColumn]
    public var total: Int { columns.reduce(0) { $0 + $1.count } }
    public func column(_ c: ZenTaoBugColumn) -> ZenTaoBugBoardColumn? { columns.first { $0.column == c } }
}

/// Sorts a column: priority first, then most recently updated.
func zentaoByPriorityThenUpdated(_ a: Ticket, _ b: Ticket) -> Bool {
    if a.priority.level != b.priority.level { return a.priority.level < b.priority.level }
    return (a.updatedAt ?? .distantPast) > (b.updatedAt ?? .distantPast)
}

private func isZenTao(_ t: Ticket, _ type: String) -> Bool {
    t.providerType == .zentao && (t.externalType ?? "").lowercased() == type
}

/// Groups the filtered bugs into ZenTao's bug columns; without `includeClosed` (the Unclosed tab) there is no Closed column.
public struct BuildZenTaoBugBoard: Sendable {
    public var filter = FilterTickets()
    public var includeClosed = true
    public init(includeClosed: Bool = true) { self.includeClosed = includeClosed }

    public func callAsFunction(_ q: BoardQuery) -> ZenTaoBugBoardModel {
        var by: [ZenTaoBugColumn: [Ticket]] = [:]
        for t in filter(q) where isZenTao(t, "bug") { by[zentaoBugColumnFor(t), default: []].append(t) }
        return ZenTaoBugBoardModel(columns: ZenTaoBugColumn.columns.compactMap { c in
            includeClosed || c != .closed ? ZenTaoBugBoardColumn(column: c, tickets: (by[c] ?? []).sorted(by: zentaoByPriorityThenUpdated)) : nil
        })
    }
}

public struct ZenTaoTaskBoardColumn: Identifiable {
    public let column: ZenTaoTaskColumn
    public let tickets: [Ticket]
    public var id: ZenTaoTaskColumn { column }
    public var count: Int { tickets.count }
}

public struct ZenTaoTaskBoardModel {
    public var columns: [ZenTaoTaskBoardColumn]
    public var total: Int { columns.reduce(0) { $0 + $1.count } }
    public func column(_ c: ZenTaoTaskColumn) -> ZenTaoTaskBoardColumn? { columns.first { $0.column == c } }
}

/// Groups the filtered tasks into ZenTao's task columns; `dueThisWeekOnly` keeps those whose deadline is this week.
public struct BuildZenTaoTaskBoard: Sendable {
    public var filter = FilterTickets()
    public var dueThisWeekOnly = false
    public init(dueThisWeekOnly: Bool = false) { self.dueThisWeekOnly = dueThisWeekOnly }

    public func callAsFunction(_ q: BoardQuery) -> ZenTaoTaskBoardModel {
        var by: [ZenTaoTaskColumn: [Ticket]] = [:]
        for t in filter(q) where isZenTao(t, "task") {
            if dueThisWeekOnly {
                guard let d = extractZenTaoDeadline(t), IsDueThisWeek()(d, now: q.now) else { continue }
            }
            by[zentaoTaskColumnFor(t), default: []].append(t)
        }
        return ZenTaoTaskBoardModel(columns: ZenTaoTaskColumn.columns.map {
            ZenTaoTaskBoardColumn(column: $0, tickets: (by[$0] ?? []).sorted(by: zentaoByPriorityThenUpdated))
        })
    }
}

public struct ZenTaoFacetCatalogInput {
    public var bugs: Bool
    public var members: [ProviderUser]
    public var modules: [ZentaoModulePath]
    public init(bugs: Bool, members: [ProviderUser], modules: [ZentaoModulePath] = []) {
        self.bugs = bugs; self.members = members; self.modules = modules
    }
}

/// Every choice a ZenTao bug or task board can be filtered by, so a filter can name one no loaded ticket carries yet.
public struct BuildZenTaoFacetCatalog: Sendable {
    public init() {}
    public func callAsFunction(_ input: ZenTaoFacetCatalogInput) -> BoardFacetCatalog {
        let members = input.members.sorted { $0.displayName.lowercased() < $1.displayName.lowercased() }
        // Assignees are stored by login; the opener and resolver by the name the person goes by.
        let assignees = members.map { BoardFacetChoice($0.account, label: $0.displayName) } + [BoardFacetChoice("")]
        var seen = Set<String>()
        let names = members.map(\.displayName).filter { seen.insert($0).inserted }.map { BoardFacetChoice($0) }
        let priorities = Priority.allCases.map { BoardFacetChoice($0.rawValue) }
        // ZenTao's "no module" ('0', path "/") is not a module to pick.
        let modules = input.modules.filter { $0.id != "0" && !$0.path.trimmingCharacters(in: .whitespaces).isEmpty }
            .map { BoardFacetChoice($0.id, label: $0.path) }
        var out: [BoardFacetKind: [BoardFacetChoice]] = [:]
        if !modules.isEmpty { out[.module] = modules }
        if input.bugs {
            out[.status] = ZenTaoBugColumn.columns.map { BoardFacetChoice($0.name) }
            if !members.isEmpty { out[.assignee] = assignees; out[.resolvedBy] = names; out[.openedBy] = names }
            out[.confirmed] = [BoardFacetChoice("1"), BoardFacetChoice("0")]
            out[.severity] = [1, 2, 3, 4].map { BoardFacetChoice("\($0)") }
            out[.priority] = priorities
            out[.bugType] = zentaoBugTypeCodes.map { BoardFacetChoice($0) }
            out[.resolution] = zentaoResolutionCodes.map { BoardFacetChoice($0) }
        } else {
            out[.status] = ZenTaoTaskColumn.columns.map { BoardFacetChoice($0.name) }
            if !members.isEmpty { out[.assignee] = assignees }
            out[.priority] = priorities
        }
        return BoardFacetCatalog(out)
    }
}

/// The overview card numbers: the open tasks and bugs assigned to the account's own user.
public struct ComputeZentaoMetrics: Sendable {
    public init() {}
    public func callAsFunction(tickets: [Ticket], account: Account) -> ToolMetrics {
        var tasks = 0, bugs = 0
        for t in tickets where t.accountId == account.id && t.providerType == .zentao && IsAssignedToMe()(t, account) {
            var isTask = (t.externalType ?? "").lowercased() == "task", isBug = (t.externalType ?? "").lowercased() == "bug"
            if case .zentaoTask? = t.providerEntity { isTask = true }
            if case .zentaoBug? = t.providerEntity { isBug = true }
            let raw = t.providerStatus.lowercased()
            let open = t.status != .done && raw != "closed" && raw != "done" && raw != "cancel"
            if isTask && open { tasks += 1 } else if isBug && open { bugs += 1 }
        }
        return ToolMetrics(primaryCount: tasks, primaryLabel: appString("zentaoMyOpenTasks", "My open tasks"),
                           secondaryCount: bugs, secondaryLabel: appString("zentaoMyOpenBugs", "My open bugs"))
    }
}
