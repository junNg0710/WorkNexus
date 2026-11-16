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
        c.openBoard("gitlab.mrs|a|2")
        XCTAssertTrue(c.filter.severities.isEmpty)
        c.openBoard("zentao.bugs|a|1")
        XCTAssertEqual(c.filter.severities, [1])
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
