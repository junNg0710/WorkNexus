import CoreDomain
import XCTest
@testable import SharedKit

/// Ported from: test/domain/{paged_view_loads,paged_view_loads_value,scope_paged_view_tickets}_test.dart
final class PagedViewTests: XCTestCase {
    private func t(_ id: String, _ status: String = "wait") -> Ticket {
        makeTicket(id, account: "zt", project: "p", provider: .zentao, key: id, providerStatus: status, title: id)
    }
    private func page(_ ids: [String], total: Int = 500) -> Outcome<ViewPage> { .success(ViewPage(tickets: ids.map { t($0) }, total: total, hasMore: true)) }

    func testPlanFirstLoadFetchesPageOne() {
        let p = PlanViewLoad()(ViewLoadRequest(state: PagedViewState(), filtered: true))!
        XCTAssertEqual(p.pages, [1]); XCTAssertTrue(p.loading.loading)
    }

    func testPlanFilteredBoardFansOutWithinTheView() {
        let plan = PlanViewLoad()
        XCTAssertEqual(plan(ViewLoadRequest(state: PagedViewState(page: 1, total: 120), filtered: true))!.pages, [2, 3])
        let big = PagedViewState(page: 1, total: 5000)
        XCTAssertEqual(plan(ViewLoadRequest(state: big, filtered: true))!.pages.count, kFilteredPagesPerLoad)
        XCTAssertEqual(plan(ViewLoadRequest(state: big, filtered: false))!.pages, [2])
    }

    func testPlanDryLoadsCountUntilCardsShow() {
        let plan = PlanViewLoad()
        let asked = PagedViewState(page: 1, total: 500, scanVisible: 3)
        let dry = plan(ViewLoadRequest(state: asked, filtered: true, visible: 3))!
        XCTAssertEqual(dry.loading.dryLoads, 1)
        var idle = dry.loading; idle.loading = false
        let fresh = plan(ViewLoadRequest(state: idle, filtered: true, visible: 5))!
        XCTAssertEqual(fresh.loading.dryLoads, 0); XCTAssertEqual(fresh.loading.scanVisible, 5)
    }

    func testPlanNothingWhileLoadingFailedOrDone() {
        for s in [PagedViewState(loading: true), PagedViewState(failure: .network("offline")), PagedViewState(page: 2, hasMore: false)] {
            XCTAssertNil(PlanViewLoad()(ViewLoadRequest(state: s, filtered: false)))
        }
    }

    func testApplyViewPagesKeepsPagesBeforeAFailure() {
        let next = ApplyViewPages()(ViewPagesResult(state: PagedViewState(ids: ["a"], page: 1, loading: true),
                                                    pages: [page(["b"]), .failure(.network("offline")), page(["c"])]))
        XCTAssertEqual(next.ids, ["a", "b"]); XCTAssertEqual(next.page, 2); XCTAssertFalse(next.loading); XCTAssertEqual(next.failure, .network("offline"))
    }

    func testMergeViewPages() {
        let merged = MergeViewPages()([page(["a", "b"], total: 10), page(["b", "c"], total: 5)]).value!
        XCTAssertEqual(ids(merged.tickets), ["a", "b", "c"]); XCTAssertEqual(merged.total, 15); XCTAssertTrue(merged.hasMore)
        XCTAssertEqual(MergeViewPages()([page(["a"]), .failure(.network("x"))]).failure, .network("x"))
    }

    func testShouldAutoLoad() {
        func auto(_ s: PagedViewState, filtered: Bool = true, visible: Int = 0) -> Bool {
            ShouldAutoLoad()(AutoLoadQuery(state: s, filtered: filtered, visible: visible))
        }
        let dry = PagedViewState(page: 3, scanVisible: 0, dryLoads: kMaxDryLoads)
        XCTAssertFalse(auto(dry)); XCTAssertTrue(auto(dry, visible: 1)); XCTAssertTrue(auto(dry, filtered: false))
        XCTAssertFalse(auto(PagedViewState(loading: true), filtered: false)); XCTAssertFalse(auto(PagedViewState(hasMore: false), filtered: false))
    }

    func testLoadsProjectionAndValueEquality() {
        let loads = PagedViewLoads.of(["wait": PagedViewState(ids: ["1", "2"], page: 1), "pause": PagedViewState(loading: true),
                                       "done": PagedViewState(failure: .network("offline"))])
        XCTAssertEqual(loads.ids["wait"]!, Set(["1", "2"])); XCTAssertNil(loads.ids["pause"]!); XCTAssertNil(loads.ids["done"]!)
        let before = PagedViewState(ids: ["1"], page: 1)
        var busy = before; busy.loading = true; busy.scanVisible = 3
        let a = PagedViewLoads.of(["wait": before, "pause": PagedViewState()])
        let b = PagedViewLoads.of(["wait": busy, "pause": PagedViewState(failure: .network("offline"))])
        XCTAssertEqual(a, b); XCTAssertEqual(a.hashValue, b.hashValue)
        XCTAssertNotEqual(PagedViewLoads.of(["wait": PagedViewState()]), PagedViewLoads.of(["wait": PagedViewState(page: 1)]))
        XCTAssertNotEqual(PagedViewLoads.of(["wait": PagedViewState(page: 1)]), PagedViewLoads.of(["wait": PagedViewState(ids: ["1"], page: 1)]))
    }

    // MARK: ScopePagedViewTickets
    private var cached: [Ticket] { [t("1", "wait"), t("2", "wait"), t("3", "pause"), t("4", "done")] }
    private func scoped(_ views: [String: PagedViewState]) -> [String] {
        ids(ScopePagedViewTickets<String>()(PagedViewScopeQuery(tickets: cached, loads: PagedViewLoads.of(views), viewOf: { $0.providerStatus })))
    }

    func testFullyLoadedViewShowsOnlyWhatItLoaded() {
        XCTAssertEqual(scoped(["wait": PagedViewState(ids: ["1"], page: 1, hasMore: false), "pause": PagedViewState(ids: ["3"], page: 1, hasMore: false),
                               "done": PagedViewState(ids: ["4"], page: 1, hasMore: false)]), ["1", "3", "4"])
    }

    func testViewWithPagesLeftPrunesTheColumnsItsPagesReach() {
        XCTAssertEqual(scoped(["wait": PagedViewState(ids: ["1"], page: 1), "pause": PagedViewState(ids: ["3"], page: 1, hasMore: false),
                               "done": PagedViewState(ids: ["4"], page: 1, hasMore: false)]), ["1", "3", "4"])
    }

    func testSharedViewKeepsCachedTicketsOfUnreachedColumns() {
        let shared = [t("r1", "resolved"), t("r2", "resolved"), t("n1", "nonfix")]
        let shown = ScopePagedViewTickets<String>()(PagedViewScopeQuery(tickets: shared, loads: PagedViewLoads.of(["toclosed": PagedViewState(ids: ["r1"], page: 1)]),
                                                                       viewOf: { _ in "toclosed" }, columnOf: { AnyHashable($0.providerStatus) }))
        XCTAssertEqual(ids(shown), ["r1", "n1"])
    }

    func testFailedOrUnloadedViewKeepsItsCachedTickets() {
        XCTAssertEqual(scoped(["wait": PagedViewState(ids: ["1"], page: 1, hasMore: false), "pause": PagedViewState(failure: .network("offline")), "done": PagedViewState()]),
                       ["1", "3", "4"])
    }

    func testTicketLoadedUnderOneViewShowsAfterItsStatusMoves() {
        XCTAssertEqual(scoped(["wait": PagedViewState(ids: ["4"], page: 1, hasMore: false), "pause": PagedViewState(page: 1, hasMore: false),
                               "done": PagedViewState(page: 1, hasMore: false)]), ["4"])
    }
}
