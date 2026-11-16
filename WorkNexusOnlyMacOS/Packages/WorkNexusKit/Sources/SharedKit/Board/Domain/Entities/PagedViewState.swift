import CoreDomain

/// Ported from: lib/shared/board/domain/entities/paged_view_state.dart
/// What a board has loaded of one paged server view (a ZenTao bug view, a task status).
public struct PagedViewState: Equatable, Sendable {
    /// The ids of the tickets loaded so far.
    public var ids: Set<String> = []
    /// The last page loaded; 0 before the first.
    public var page = 0
    /// How many tickets the view holds on the server, across every page.
    public var total = 0
    public var hasMore = true
    public var loading = false
    /// Why the last page failed to load; cleared by a retry.
    public var failure: Failure?
    /// How many of the view's cards the board showed when its column last asked for more; -1 before it asked.
    public var scanVisible = -1
    /// How many loads in a row the column asked for without a new card showing since the one before.
    public var dryLoads = 0

    public init(ids: Set<String> = [], page: Int = 0, total: Int = 0, hasMore: Bool = true, loading: Bool = false,
                failure: Failure? = nil, scanVisible: Int = -1, dryLoads: Int = 0) {
        self.ids = ids; self.page = page; self.total = total; self.hasMore = hasMore; self.loading = loading
        self.failure = failure; self.scanVisible = scanVisible; self.dryLoads = dryLoads
    }

    public var started: Bool { page > 0 }
    /// Whether the next page can be fetched: a failed page waits for a retry.
    public var canLoadMore: Bool { hasMore && !loading && failure == nil }
}
