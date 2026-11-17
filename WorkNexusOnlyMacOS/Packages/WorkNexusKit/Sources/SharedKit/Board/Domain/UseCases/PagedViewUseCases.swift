import CoreDomain
import Foundation

/// Ported from: lib/shared/board/domain/usecases/{merge_view_pages,apply_view_pages,plan_view_load,should_auto_load}.dart

/// Merges the pages fetched side by side for one load: first failure wins; tickets de-duplicated by id (first kept).
public struct MergeViewPages: Sendable {
    public init() {}
    public func callAsFunction(_ pages: [Outcome<ViewPage>]) -> Outcome<ViewPage> {
        var tickets: [Ticket] = []
        var seen = Set<String>()
        var total = 0
        var hasMore = false
        for page in pages {
            switch page {
            case .failure: return page
            case .success(let v):
                for t in v.tickets where seen.insert(t.id).inserted { tickets.append(t) }
                total += v.total
                hasMore = hasMore || v.hasMore
            }
        }
        return .success(ViewPage(tickets: tickets, total: total, hasMore: hasMore))
    }
}

public struct ViewPagesResult: Sendable {
    public var state: PagedViewState
    public var pages: [Outcome<ViewPage>]
    public init(state: PagedViewState, pages: [Outcome<ViewPage>]) { self.state = state; self.pages = pages }
}

/// Folds loaded pages into a view's state; a failing page stops there and records the failure.
public struct ApplyViewPages: Sendable {
    public init() {}
    public func callAsFunction(_ r: ViewPagesResult) -> PagedViewState {
        var next = r.state
        for res in r.pages {
            switch res {
            case .success(let v):
                next.ids.formUnion(v.tickets.map(\.id))
                next.page += 1; next.total = v.total; next.hasMore = v.hasMore
            case .failure(let f):
                next.loading = false; next.failure = f
                return next
            }
        }
        next.loading = false
        return next
    }
}

/// Folds a fresh read of a view's first page into what it has loaded (not in the Flutter app): tickets made since join it,
/// the pages already loaded stay, and the total follows the server. New tickets come first in the fetch order (newest), so
/// the pages after the first only shift down onto tickets already loaded: nothing is skipped.
public struct ApplyViewHead: Sendable {
    public init() {}
    public func callAsFunction(_ state: PagedViewState, _ head: ViewPage) -> PagedViewState {
        var next = state
        next.ids.formUnion(head.tickets.map(\.id))
        next.total = head.total
        // A view that had been read to its end has more again when it grew past what was read.
        if !next.hasMore, head.hasMore, next.page * kPagedViewPageSize < head.total { next.hasMore = true }
        return next
    }
}

public struct ViewLoadRequest: Sendable {
    public var state: PagedViewState
    public var filtered: Bool
    public var visible: Int?
    public init(state: PagedViewState, filtered: Bool, visible: Int? = nil) { self.state = state; self.filtered = filtered; self.visible = visible }
}

public struct ViewLoadPlan: Sendable {
    public var pages: [Int]
    public var loading: PagedViewState
}

/// Decides which pages the next load fetches (several side by side when filtered) and the state to show meanwhile.
public struct PlanViewLoad: Sendable {
    public init() {}
    public func callAsFunction(_ r: ViewLoadRequest) -> ViewLoadPlan? {
        let state = r.state
        guard state.canLoadMore else { return nil }
        var asked = state
        if let visible = r.visible {
            asked.scanVisible = visible
            asked.dryLoads = visible == state.scanVisible ? state.dryLoads + 1 : 0
        }
        let first = state.page + 1
        let lastPage = Int((Double(state.total) / Double(kPagedViewPageSize)).rounded(.up))
        let last = state.started && r.filtered ? min(first + kFilteredPagesPerLoad - 1, max(lastPage, first)) : first
        asked.loading = true
        return ViewLoadPlan(pages: Array(first...last), loading: asked)
    }
}

public struct AutoLoadQuery: Sendable {
    public var state: PagedViewState
    public var filtered: Bool
    public var visible: Int
    public init(state: PagedViewState, filtered: Bool, visible: Int) { self.state = state; self.filtered = filtered; self.visible = visible }
}

/// Whether a column should load its next page by itself (a filtered one gives up after `kMaxDryLoads` dry loads).
public struct ShouldAutoLoad: Sendable {
    public init() {}
    public func callAsFunction(_ q: AutoLoadQuery) -> Bool {
        q.state.canLoadMore && (!q.filtered || q.visible != q.state.scanVisible || q.state.dryLoads < kMaxDryLoads)
    }
}
