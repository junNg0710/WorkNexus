import CoreDomain
import Foundation
import Observation

/// Ported from: lib/shared/board/presentation/paged_views_controller.dart
/// What a paged board (ZenTao bug views / task statuses) has loaded of each server view. A tool creates one with its
/// `fetchPage` and calls `open(...)` when the board opens or the scope changes; columns call `loadMore`.
@MainActor @Observable
public final class PagedViewsController<V: Hashable & Sendable> {
    public typealias PageFetcher = @Sendable (_ view: V, _ page: Int, _ limit: Int, _ cancel: CancelSignal) async -> Outcome<ViewPage>

    public private(set) var views: [V: PagedViewState] = [:]
    private let fetchPage: PageFetcher
    private let isFiltered: @MainActor () -> Bool
    private var generation = 0
    private var cancel = CancelSignal()

    /// - Parameters:
    ///   - isFiltered: whether the board's filter can hide tickets (`FilterState.narrowsTickets`): a filtered board scans several pages per load.
    public init(isFiltered: @escaping @MainActor () -> Bool, fetchPage: @escaping PageFetcher) {
        self.isFiltered = isFiltered; self.fetchPage = fetchPage
    }

    /// What each view has loaded (feeds `ScopePagedViewTickets`).
    public var loads: PagedViewLoads<V> { PagedViewLoads.of(views) }

    /// Resets to fresh views (`finished` for views known to be empty) and starts loading the `opening` ones.
    public func open(views list: [V], opening: [V] = [], finished: Bool = false) {
        generation += 1
        cancel.cancel()
        cancel = CancelSignal()
        views = Dictionary(list.map { ($0, PagedViewState(hasMore: !finished)) }, uniquingKeysWith: { a, _ in a })
        for v in opening { Task { await loadMore(v) } }
    }

    /// Loads the next page(s) of `view`; `visible` is how many of its cards the column shows now (filtered scans).
    public func loadMore(_ view: V, visible: Int? = nil) async {
        guard let current = views[view],
              let plan = PlanViewLoad()(ViewLoadRequest(state: current, filtered: isFiltered(), visible: visible)) else { return }
        let gen = generation, cancel = self.cancel, fetch = fetchPage
        views[view] = plan.loading
        let pages = await withTaskGroup(of: (Int, Outcome<ViewPage>).self) { group in
            for page in plan.pages {
                group.addTask { (page, await fetch(view, page, kPagedViewPageSize, cancel)) }
            }
            var out: [(Int, Outcome<ViewPage>)] = []
            for await r in group { out.append(r) }
            return out.sorted { $0.0 < $1.0 }.map(\.1)
        }
        if cancel.isCancelled || gen != generation { return }
        views[view] = ApplyViewPages()(ViewPagesResult(state: views[view] ?? plan.loading, pages: pages))
    }

    /// Reads the first page of every view that has loaded again and adds what is new (a ticket made elsewhere since),
    /// keeping the pages already loaded: the board picks up new work without losing its place. A view that is loading,
    /// failed or not started is left alone; a failed read changes nothing (the next one tries again).
    public func refreshHeads() async {
        let gen = generation, cancel = self.cancel, fetch = fetchPage
        let ready = views.filter { $0.value.started && !$0.value.loading && $0.value.failure == nil }.map(\.key)
        guard !ready.isEmpty else { return }
        let heads = await withTaskGroup(of: (V, Outcome<ViewPage>).self) { group in
            for view in ready { group.addTask { (view, await fetch(view, 1, kPagedViewPageSize, cancel)) } }
            var out: [(V, Outcome<ViewPage>)] = []
            for await r in group { out.append(r) }
            return out
        }
        if cancel.isCancelled || gen != generation { return }
        for (view, result) in heads {
            guard case .success(let head) = result, let state = views[view], !state.loading else { continue }
            views[view] = ApplyViewHead()(state, head)
        }
    }

    /// Clears a failed page and tries again.
    public func retry(_ view: V) async {
        if var s = views[view] { s.failure = nil; views[view] = s }
        await loadMore(view)
    }
}
