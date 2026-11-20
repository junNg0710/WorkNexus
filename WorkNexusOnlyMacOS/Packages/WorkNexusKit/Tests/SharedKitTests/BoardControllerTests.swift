import CoreDomain
import CoreTools
import XCTest
@testable import SharedKit

/// The board controller's filter + derivation logic against in-memory repositories (rule 13.2: mock at the boundary).
@MainActor
final class BoardControllerTests: XCTestCase {
    final class FakeSettings: SettingsRepository, @unchecked Sendable {
        var current = AppSettings()
        func load() async -> AppSettings { current }
        func save(_ s: AppSettings) async -> Outcome<Void> { current = s; return .success(()) }
        func watch() -> AsyncStream<AppSettings> { AsyncStream { $0.yield(self.current); $0.finish() } }
    }
    struct NoopSync: AccountSyncService, TicketDetailService {
        func sync(accountId: String) async -> Outcome<Void> { .success(()) }
        func adapter(for account: Account) async -> ProviderAdapter? { nil }
        func refresh(ticket: Ticket) async -> Outcome<Void> { .success(()) }
        func postComment(ticket: Ticket, body: String) async -> Outcome<Void> { .success(()) }
    }

    private func make(tickets: [Ticket]) -> (BoardController, FakeStore) {
        let store = FakeStore()
        for t in tickets { store.tickets[t.id] = t }
        store.accounts["ghP"] = Account(id: "ghP", workspaceId: "w1", providerType: .github, handle: "me")
        let registry = ToolRegistry()
        let services = AppServices(tickets: store, workspaces: store, comments: store, activity: store, syncStatus: SyncSuite.RecordingStatusRef(),
                                   settings: FakeSettings(), credentials: store, sync: NoopSync(), ticketDetail: NoopSync(), adapters: FakeRegistry())
        let nav = AppNavController { _ in "default" }
        return (BoardController(services: services, nav: nav, registry: registry), store)
    }

    private func waitFor(_ cond: @escaping () -> Bool) async {
        for _ in 0..<100 where !cond() { try? await Task.sleep(for: .milliseconds(10)) }
    }

    func testBoardDerivesFromWatchedTicketsAndFilter() async {
        let (c, _) = make(tickets: [makeTicket("a", priority: .low), makeTicket("b", priority: .urgent), makeTicket("c", status: .done)])
        c.start()
        await waitFor { c.board.total == 3 }
        XCTAssertEqual(c.board.total, 3)
        c.togglePriority(.urgent)
        XCTAssertEqual(c.resultCount, 1)
        XCTAssertEqual(c.filter.activeTokenCount, 1)
        c.togglePriority(.urgent)
        XCTAssertEqual(c.resultCount, 3)
        c.setSearch("zzz"); XCTAssertEqual(c.resultCount, 0)
        c.clearAll(); XCTAssertEqual(c.resultCount, 3)
        c.stop()
    }

    /// The card order is the session's (`AppNavController.boardSort`): picking another re-sorts a running board.
    func testPickingAnotherCardOrderReSortsTheBoard() async {
        let (c, _) = make(tickets: [makeTicket("a", key: "1", priority: .urgent, title: "zeta"), makeTicket("b", key: "2", priority: .low, title: "alpha")])
        c.start(); await waitFor { c.board.total == 2 }
        func todo() -> [String] { ids(c.board.columns.first { $0.status == .todo }!.tickets) }
        XCTAssertEqual(todo(), ["a", "b"])
        c.nav.sortBoardCards(by: .title)
        await waitFor { todo() == ["b", "a"] }
        XCTAssertEqual(todo(), ["b", "a"])
        XCTAssertEqual(c.boardQuery.sort, TicketSort(.title))
        c.stop()
    }

    /// A scope that reads the settings (a team view leaving executions out) follows a change of them.
    func testASettingsChangeReScopes() async {
        let (c, _) = make(tickets: [makeTicket("a"), makeTicket("b", project: "p2")])
        c.start(); await waitFor { c.tickets.count == 2 }
        c.scopeTickets = { [unowned c] in c.settings.teamExecutionVisibility["p2"] == false ? $0.filter { $0.projectId != "p2" } : $0 }
        XCTAssertEqual(Set(ids(c.scoped)), ["a", "b"])
        c.updateSettings { $0.teamExecutionVisibility["p2"] = false }
        XCTAssertEqual(ids(c.scoped), ["a"])
        c.stop()
    }

    func testScopeHookNarrowsTheTickets() async {
        let (c, _) = make(tickets: [makeTicket("a"), makeTicket("b", project: "p2")])
        c.start(); await waitFor { c.tickets.count == 2 }
        c.scopeTickets = { $0.filter { $0.projectId == "p2" } }
        XCTAssertEqual(ids(c.scoped), ["b"])
        c.scopedTicketsOverride = [makeTicket("z")]
        XCTAssertEqual(ids(c.scoped), ["z"])
        c.stop()
    }

    func testEachBoardKeepsItsOwnFilter() async {
        let (c, _) = make(tickets: [makeTicket("a")])
        c.openBoard("zentao.bugs|a|1")
        c.toggleSeverity(1)
        c.toggleZenTaoStatus("resolvedVerify")
        c.openBoard("gitlab.mrs|a|2")
        XCTAssertTrue(c.filter.severities.isEmpty)
        XCTAssertTrue(c.filter.zentaoStatuses.isEmpty, "only ZenTao boards start on statuses")
        c.openBoard("zentao.bugs|a|1")
        XCTAssertEqual(c.filter.severities, [1])
        XCTAssertEqual(c.filter.zentaoStatuses, BoardController.openBugStatuses.union(["resolvedVerify"]))
    }

    func testAZenTaoTaskBoardOpensOnTheWorkStillToDoAndKeepsWhatTheUserMadeOfIt() {
        let (c, _) = make(tickets: [])
        c.openBoard("zentao.tasks|a|5")
        XCTAssertEqual(c.filter.zentaoStatuses, ["notStarted", "inProgress", "paused"])
        XCTAssertEqual(c.filter.activeTokenCount, 3)
        // Cleared by the user: it stays cleared when the board is left and opened again.
        c.clearAll()
        c.openBoard("zentao.bugs|a|1")
        XCTAssertEqual(c.filter.zentaoStatuses, ["newUnconfirmed", "confirmedToFix"], "bugs open on the ones still to fix")
        c.openBoard("zentao.tasks|a|5")
        XCTAssertTrue(c.filter.zentaoStatuses.isEmpty)
        // Another execution is another board: it starts on the default.
        c.openBoard("zentao.tasks|a|6")
        XCTAssertEqual(c.filter.zentaoStatuses, BoardController.openTaskStatuses)
    }

    func testOwnViewSetsFilterAsideAndRestoresIt() {
        let (c, _) = make(tickets: [])
        c.openBoard("k")
        c.toggleAssignee("thanh")
        c.enterOwnView(.related)
        XCTAssertEqual(c.filter.savedView, .related); XCTAssertTrue(c.filter.assignees.isEmpty)
        c.leaveOwnView()
        XCTAssertEqual(c.filter.assignees, ["thanh"]); XCTAssertEqual(c.filter.savedView, .all)
    }

    func testSavedPresetsRoundTripAndApply() async {
        let (c, _) = make(tickets: [])
        c.start()
        c.togglePriority(.high)
        let saved = await c.saveCurrentFilter(named: "  Hot ")
        XCTAssertNotNil(saved.value)
        await waitFor { !c.savedFilters.isEmpty }
        XCTAssertEqual(c.savedFilters.map(\.name), ["Hot"])
        c.clearAll()
        c.setWorkspace("w9")
        c.apply(c.savedFilters[0])
        XCTAssertEqual(c.filter.priorities, [.high]); XCTAssertEqual(c.filter.workspaceId, "w9", "a preset never moves you to another workspace")
        let deleted = await c.deleteSavedFilter(c.savedFilters[0].id)
        XCTAssertNotNil(deleted.value)
        await waitFor { c.savedFilters.isEmpty }
        XCTAssertTrue(c.savedFilters.isEmpty)
        c.stop()
    }

    func testFilterGroupsAvailability() async {
        let (c, _) = make(tickets: [makeTicket("a", project: "p1"), makeTicket("b", project: "p2")])
        c.start(); await waitFor { c.tickets.count == 2 }
        XCTAssertTrue(c.filterHasGroups, "two projects in scope offer the generic groups")
        c.scopedTicketsOverride = [makeTicket("a", project: "p1")]
        XCTAssertFalse(c.filterHasGroups)
        c.facetScope = .task; XCTAssertTrue(c.filterHasGroups)
        c.stop()
    }

    func testMoveTicketWritesTheStatus() async {
        let (c, store) = make(tickets: [makeTicket("a")])
        c.moveTicket("a", to: .done)
        await waitFor { store.tickets["a"]?.status == .done }
        XCTAssertEqual(store.tickets["a"]?.status, .done)
    }

    func testSelectionIsBuiltUpAndClearedWhenTheBoardChanges() {
        let (c, _) = make(tickets: [makeTicket("a"), makeTicket("b"), makeTicket("c")])
        c.toggleSelected("a"); c.toggleSelected("b")
        XCTAssertEqual(c.selectedIds, ["a", "b"])
        c.toggleSelected("a")
        XCTAssertEqual(c.selectedIds, ["b"])
        c.select(["a", "c"])
        XCTAssertEqual(c.selectedIds, ["a", "c"])
        // With something picked a plain click picks too, instead of opening the ticket.
        c.tapTicket("b")
        XCTAssertEqual(c.selectedIds, ["a", "b", "c"])
        XCTAssertNil(c.openTicketId)
        c.openBoard("zentao.tasks|acc|1")
        XCTAssertTrue(c.selectedIds.isEmpty)
        // With nothing picked a plain click opens it.
        c.tapTicket("a")
        XCTAssertTrue(c.selectedIds.isEmpty)
        XCTAssertEqual(c.openTicketId, "a")
    }

    func testSearchPoolWidensWhatQuickSearchLooksThrough() async {
        let (c, _) = make(tickets: [makeTicket("alpha", title: "alpha"), makeTicket("beta", title: "beta")])
        c.start()
        await waitFor { c.tickets.count == 2 }
        c.scopeTickets = { $0.filter { $0.id == "alpha" } }
        XCTAssertEqual(c.search("beta").count, 0)
        c.searchPool = { $0 }
        XCTAssertEqual(c.search("beta").map(\.id), ["beta"])
        XCTAssertEqual(BoardController.ticketKey(typed: " #123 "), "123")
        XCTAssertEqual(BoardController.ticketKey(typed: "45"), "45")
        XCTAssertNil(BoardController.ticketKey(typed: "login"))
        XCTAssertNil(BoardController.ticketKey(typed: "#"))
        c.stop()
    }

    /// A ticket store whose stream carries every write (the shared fake answers once).
    private final class LiveTickets: TicketRepository, @unchecked Sendable {
        private let lock = NSLock()
        private var all: [Ticket]
        private var continuation: AsyncStream<[Ticket]>.Continuation?
        init(_ tickets: [Ticket]) { all = tickets }
        func watchTickets() -> AsyncStream<[Ticket]> {
            AsyncStream { c in lock.withLock { continuation = c; c.yield(all) } }
        }
        func ticket(id: String) async -> Outcome<Ticket?> { .success(lock.withLock { all.first { $0.id == id } }) }
        func upsertTickets(_ list: [Ticket]) async -> Outcome<Void> {
            lock.withLock {
                for t in list { if let i = all.firstIndex(where: { $0.id == t.id }) { all[i] = t } else { all.append(t) } }
                continuation?.yield(all)
            }
            return .success(())
        }
        func moveTicket(id: String, to status: UnifiedStatus) async -> Outcome<Void> { .success(()) }
    }

    /// A sync writes tickets of other boards too: a write that leaves this board's tickets as they were rebuilds nothing.
    func testAWriteOutsideTheScopeRebuildsNothing() async {
        let store = FakeStore(), live = LiveTickets([makeTicket("a"), makeTicket("b"), makeTicket("other")])
        let services = AppServices(tickets: live, workspaces: store, comments: store, activity: store, syncStatus: SyncSuite.RecordingStatusRef(),
                                   settings: FakeSettings(), credentials: store, sync: NoopSync(), ticketDetail: NoopSync(), adapters: FakeRegistry())
        let c = BoardController(services: services, nav: AppNavController { _ in "board" }, registry: ToolRegistry())
        c.scopeTickets = { $0.filter { $0.id != "other" && $0.id != "new" } }
        c.start()
        await waitFor { c.board.total == 2 }
        let revision = c.revision
        var other = makeTicket("other"); other.title = "changed elsewhere"
        _ = await live.upsertTickets([other, makeTicket("new")])
        await waitFor { c.tickets.count == 4 }
        XCTAssertEqual(c.tickets.count, 4)
        XCTAssertEqual(c.revision, revision, "the tickets in scope are the same: nothing is rebuilt")
        // The tool scoping again to the same tickets (a page of another view arrived) rebuilds nothing either.
        c.scopeTickets = { $0.filter { $0.id != "other" && $0.id != "new" } }
        XCTAssertEqual(c.revision, revision)
        var a = makeTicket("a"); a.title = "changed here"
        _ = await live.upsertTickets([a])
        await waitFor { c.revision != revision }
        XCTAssertEqual(c.revision, revision + 1, "a ticket in scope changed: one rebuild")
        XCTAssertEqual(c.scoped.first { $0.id == "a" }?.title, "changed here")
        c.stop()
    }

    /// A board kept mounted behind another section does no work for ticket changes, and catches up once when shown.
    func testAHiddenBoardWaitsAndCatchesUpWhenShown() async {
        let (c, _) = make(tickets: [makeTicket("a"), makeTicket("b")])
        c.start()
        await waitFor { c.board.total == 2 }
        c.isActive = false
        let revision = c.revision
        c.togglePriority(.urgent); c.setSearch("zzz"); c.clearAll(); c.togglePriority(.urgent)
        XCTAssertEqual(c.revision, revision, "nothing is recomputed while hidden")
        XCTAssertEqual(c.resultCount, 2, "and it still shows what it had")
        c.isActive = true
        XCTAssertEqual(c.revision, revision + 1, "one recompute for everything that changed meanwhile")
        XCTAssertEqual(c.resultCount, 0)
        // Shown again with nothing changed: no work.
        c.isActive = false; c.isActive = true
        XCTAssertEqual(c.revision, revision + 1)
        c.stop()
    }

    func testBoardKeyFollowsTheNavLocation() {
        let (c, _) = make(tickets: [])
        XCTAssertEqual(c.currentBoardKey, "default")
        c.nav.select(.account("ghP"))
        c.nav.setSection("zentao.bugs", accountId: "ghP"); c.nav.setScope("7", accountId: "ghP")
        XCTAssertEqual(c.currentBoardKey, "zentao.bugs|ghP|7")
    }
}

/// `SyncStatusRepository` stand-in for the AppServices wiring.
enum SyncSuite {
    static func RecordingStatusRef() -> SyncStatusRepository { SyncTests.RecordingStatus() }
}
