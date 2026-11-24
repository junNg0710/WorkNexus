/// Not in the Flutter app: the team leader's view of the Tasks / Bugs boards - whose work, quick filters, a keyword,
/// the load of each person - on top of the boards' own filters.
import CoreDomain
import Foundation
import SharedKit

extension ZentaoUIState {
    /// The most tickets of one view the leader's "load everything" reads (ten pages).
    static let leaderLoadCap = 500

    // MARK: The filter

    /// The board's own key, also while the other section is on screen (`BoardController.boardKey(of:)`).
    private func leaderKey(_ bugs: Bool) -> String {
        (bugs ? bugBoard : taskBoard).boardKey(of: bugs ? ZentaoSection.bugs : ZentaoSection.tasks)
    }

    /// The leader's filter of the board on screen (each board keeps its own).
    public func leader(bugs: Bool) -> ZenTaoLeaderFilter { leaders[leaderKey(bugs)] ?? ZenTaoLeaderFilter() }

    public func setLeader(_ filter: ZenTaoLeaderFilter, bugs: Bool) {
        let key = leaderKey(bugs)
        if filter.isActive { leaders[key] = filter } else { leaders[key] = nil }
        // A board that hides tickets must look further than its first pages for them (and loads whole to count).
        if filter.isActive { loadEverything(bugs: bugs) }
    }

    public func updateLeader(bugs: Bool, _ change: (inout ZenTaoLeaderFilter) -> Void) {
        var f = leader(bugs: bugs)
        change(&f)
        setLeader(f, bugs: bugs)
    }

    /// Whether the Tasks board is set to the tasks due this week.
    public var dueThisWeek: Bool { leader(bugs: false).quick.contains(.dueThisWeek) }

    // MARK: Derived

    /// Login -> the name the person goes by, from the people of the open board.
    public var memberNames: [String: String] {
        // Names only: either board's people may name someone, so both are read.
        Dictionary((taskMembers + bugMembers).map { ($0.account, $0.displayName) }, uniquingKeysWith: { a, _ in a })
    }

    /// The board's tickets after its own filters but before the leader's: what the people strip and chips count.
    public func leaderPool(bugs: Bool) -> [Ticket] {
        (bugs ? bugCache : taskCache).pool(cacheKey(bugs: bugs)) {
            let type = bugs ? "bug" : "task"
            return FilterTickets()((bugs ? bugBoard : taskBoard).boardQuery)
                .filter { $0.providerType == .zentao && ($0.externalType ?? "").lowercased() == type }
        }
    }

    /// The pool narrowed by everything the leader picked except the part being counted.
    private func narrowed(bugs: Bool, dropping: (inout ZenTaoLeaderFilter) -> Void) -> [Ticket] {
        var f = leader(bugs: bugs)
        dropping(&f)
        return ApplyLeaderFilter()(leaderPool(bugs: bugs), f, names: memberNames)
    }

    /// Each person's load under the chips and keyword picked (the people pick itself does not narrow it, so a
    /// person can be swapped for another). Members of the board are listed even when they hold nothing.
    public func workload(bugs: Bool) -> [ZenTaoWorkload] {
        (bugs ? bugCache : taskCache).workload(cacheKey(bugs: bugs)) {
            SummarizeWorkload()(narrowed(bugs: bugs) { $0.people = [] }, roster: boardMembers(bugs: bugs).map(\.account))
        }
    }

    /// What each quick chip would keep, under the people and keyword picked.
    public func quickCounts(bugs: Bool) -> [ZenTaoQuickFilter: Int] {
        (bugs ? bugCache : taskCache).counts(cacheKey(bugs: bugs)) {
            CountQuickFilters()(narrowed(bugs: bugs) { $0.quick = [] })
        }
    }

    // MARK: Loading everything

    private var leaderTaskViews: [ZenTaoTaskColumn] { [.notStarted, .inProgress, .paused] }
    private var leaderBugViews: [ZenTaoBugStream] {
        Self.openingBugStreams(related: bugRelated) + (bugTab == .all ? [.all] : [])
    }

    /// How much of the open views is loaded: the tickets, the tickets the server holds, and whether more is waiting.
    public func leaderCoverage(bugs: Bool) -> (loaded: Int, total: Int, more: Bool) {
        let states: [PagedViewState] = bugs ? leaderBugViews.compactMap { bugStreams.views[$0] }
                                            : leaderTaskViews.compactMap { taskStreams.views[$0] }
        let ids = states.reduce(into: Set<String>()) { $0.formUnion($1.ids) }
        return (ids.count, states.reduce(0) { $0 + $1.total }, states.contains { $0.hasMore && $0.failure == nil })
    }

    /// Loads the board's open views to their end (at most `leaderLoadCap` tickets each), so counts and filters see
    /// all of the work rather than the first pages.
    public func loadEverything(bugs: Bool) {
        let key = bugs ? "bugs" : "tasks"
        // A team's people are read whole already.
        guard team(bugs: bugs) == nil, !loadingEverything.contains(key) else { return }
        loadingEverything.insert(key)
        let streamsOfBugs = bugStreams, streamsOfTasks = taskStreams, bugViews = leaderBugViews, taskViews = leaderTaskViews
        Task {
            await withTaskGroup(of: Void.self) { group in
                if bugs { for v in bugViews { group.addTask { await Self.drain(streamsOfBugs, v) } } }
                else { for v in taskViews { group.addTask { await Self.drain(streamsOfTasks, v) } } }
            }
            loadingEverything.remove(key)
        }
    }

    /// Pages of `view` one after another until it has no more, fails, reaches the cap or stops advancing.
    @MainActor
    private static func drain<V: Hashable & Sendable>(_ streams: PagedViewsController<V>, _ view: V) async {
        var stalled = 0
        while !Task.isCancelled {
            guard let state = streams.views[view], state.hasMore, state.failure == nil, state.ids.count < leaderLoadCap else { return }
            if state.loading { try? await Task.sleep(for: .milliseconds(150)); continue }
            await streams.loadMore(view)
            if let after = streams.views[view], after.page == state.page, !after.loading { stalled += 1; if stalled >= 2 { return } }
            else { stalled = 0 }
        }
    }
}

// MARK: Finding a ticket by its id

extension ZentaoUIState {
    /// The cached ZenTao tickets of the account on screen, whichever execution or product they belong to.
    func accountZenTaoTickets(_ all: [Ticket]) -> [Ticket] {
        guard let account = placeAccountId else { return [] }
        return all.filter { $0.accountId == account && $0.providerType == .zentao }
    }

    /// Fetches ZenTao ticket `key` from the server (a task first, or a bug first) and returns its local ticket id.
    func fetchByKey(_ key: String, bugsFirst: Bool) async -> String? {
        guard let accountId = placeAccountId, let host = taskBoard.accounts[accountId]?.baseUrl.flatMap({ URL(string: $0)?.host }) else { return nil }
        for type in bugsFirst ? ["bug", "task"] : ["task", "bug"] {
            if case .success(let id) = await deps.tickets.fetchZenTaoTicket(host: host, type: type, id: key) { return id }
        }
        return nil
    }
}
