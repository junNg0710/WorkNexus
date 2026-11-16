/// Ported from: lib/tools/zentao/presentation/providers/{zentao_bug_streams,zentao_task_streams}.dart
import CoreDomain
import Foundation
import SharedKit

extension ZentaoUIState {
    /// The views loaded as soon as a product's bug board opens. `ZenTaoBugStream.all` only feeds the Closed column, so
    /// it waits until that column is shown; on the Related-to-me tab one merged view feeds every column.
    static func openingBugStreams(related: Bool) -> [ZenTaoBugStream] {
        related ? [.relatedToMe] : [.unconfirmed, .unresolved, .toClose]
    }

    func reopenBugStreams() {
        let none = product == nil
        bugStreams.open(views: ZenTaoBugStream.allCases, opening: none ? [] : Self.openingBugStreams(related: bugRelated), finished: none)
    }

    func reopenTaskStreams() {
        let none = execution == nil
        taskStreams.open(views: ZenTaoTaskColumn.allCases, opening: none ? [] : ZenTaoTaskColumn.allCases, finished: none)
    }

    func fetchBugPage(_ view: ZenTaoBugStream, page: Int, limit: Int, cancel: CancelSignal) async -> Outcome<ViewPage> {
        guard let product else { return .failure(.cancelled("No product is selected")) }
        let sort = bugFetchSort, pages = deps.viewPages
        @Sendable func fetch(_ code: String, _ page: Int) async -> Outcome<ViewPage> {
            await pages.syncProductBugsPage(accountId: product.accountId, productId: product.productId, browseType: code,
                                            page: page, limit: limit, sort: sort, cancel: cancel)
        }
        if view.also.isEmpty { return await fetch(view.code, page) }
        // A view made of several (Related to me) is read whole, each of its views to its own end, as one page: paged
        // together, page N of each would not be the top of their merged order.
        var results: [Outcome<ViewPage>] = []
        for code in view.codes { results.append(await Self.wholeView { await fetch(code, $0) }) }
        return MergeViewPages()(results)
    }

    /// Every page of one view, one after another, as a single last page.
    static func wholeView(_ fetch: (Int) async -> Outcome<ViewPage>) async -> Outcome<ViewPage> {
        var tickets: [Ticket] = []
        var page = 1
        while true {
            switch await fetch(page) {
            case .failure(let f): return .failure(f)
            case .success(let v):
                tickets.append(contentsOf: v.tickets)
                // An empty page ends it too: a view that claims more but sends nothing must not be asked forever.
                if !v.hasMore || v.tickets.isEmpty { return .success(ViewPage(tickets: tickets, total: v.total, hasMore: false)) }
            }
            page += 1
        }
    }

    func fetchTaskPage(_ view: ZenTaoTaskColumn, page: Int, limit: Int, cancel: CancelSignal) async -> Outcome<ViewPage> {
        guard let execution else { return .failure(.cancelled("No execution is selected")) }
        return await deps.viewPages.syncExecutionTasksPage(
            accountId: execution.accountId, executionId: execution.executionId, browseType: view.browseType, page: page,
            limit: limit, sort: taskFetchSort, cancel: cancel)
    }

    // MARK: Derived stream state (zentaoBugSliceProvider / HasMore / ColumnStream)

    /// What has been loaded of the view `column` draws on.
    public func bugStream(_ column: ZenTaoBugColumn) -> PagedViewState {
        bugStreams.views[ZenTaoBugStream.of(column, related: bugRelated)] ?? PagedViewState()
    }
    public func taskStream(_ column: ZenTaoTaskColumn) -> PagedViewState { taskStreams.views[column] ?? PagedViewState() }

    /// Loading until each opening view has its first page; an error when none of them could be loaded.
    public var bugSlice: ZentaoLoad<Set<String>> {
        if product == nil { return .loaded([]) }
        let opening = Self.openingBugStreams(related: bugRelated).compactMap { bugStreams.views[$0] }
        if let first = opening.first?.failure, opening.allSatisfy({ $0.failure != nil }) { return .failed(first) }
        if opening.contains(where: { !$0.started && $0.failure == nil }) { return .loading }
        return .loaded(bugStreams.views.values.reduce(into: Set<String>()) { $0.formUnion($1.ids) })
    }

    public var taskSlice: ZentaoLoad<Set<String>> {
        if execution == nil { return .loaded([]) }
        let all = Array(taskStreams.views.values)
        if let first = all.first?.failure, all.allSatisfy({ $0.failure != nil }) { return .failed(first) }
        if all.contains(where: { !$0.started && $0.failure == nil }) { return .loading }
        return .loaded(all.reduce(into: Set<String>()) { $0.formUnion($1.ids) })
    }

    /// Whether a column on screen can still load more bugs (the board stays up even while every loaded bug is filtered out).
    public var bugHasMore: Bool {
        let closedShown = bugTab == .all
        let shown = Set(ZenTaoBugColumn.allCases.filter { closedShown || $0 != .closed }.map { ZenTaoBugStream.of($0, related: bugRelated) })
        return shown.contains { bugStreams.views[$0]?.hasMore ?? false }
    }
    public var taskHasMore: Bool { taskStreams.views.values.contains { $0.hasMore } }
}
