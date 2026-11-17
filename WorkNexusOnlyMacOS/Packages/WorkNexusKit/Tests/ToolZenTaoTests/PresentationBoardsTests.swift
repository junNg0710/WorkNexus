import CoreDomain
import CoreTools
import SharedKit
import XCTest
@testable import ToolZenTao

/// The ZenTao boards' state: selection and scope titles, parent / child scoping, the paged streams (what opens, what a
/// tab change restarts, fetch order), keeping a board on a product / execution, the board models, drops, the metrics.
/// Ports of test/unit/zentao_scope_title_test.dart, zentao_parent_child_scoping_test.dart and
/// test/widget/{zentao_bug_streams,zentao_task_streams,keep_task_board_scope,zentao_board_refresh_button}_test.dart.
@MainActor
final class PresentationBoardsTests: XCTestCase {
    // MARK: Scope title

    func testBugBoardIsTitledByThePickedProduct() {
        let env = BoardsEnv()
        env.state.openProduct(env.product("p-1", "VN_Socialfi"))
        XCTAssertEqual(env.state.scopeTitle(accountId: "zt1", scopeId: "p-1", bugs: true), "VN_Socialfi")
    }

    func testBugBoardNotYetPickedIsTitledByItsProductFromTheList() async {
        let env = BoardsEnv()
        env.pages.products = [env.product("p-1", "VN_Socialfi")]
        env.state.loadProducts("zt1")
        await env.wait { env.state.products["zt1"]?.value != nil }
        XCTAssertEqual(env.state.scopeTitle(accountId: "zt1", scopeId: "p-1", bugs: true), "VN_Socialfi")
    }

    func testASelectionOfAnotherAccountOrScopeIsNotTheTitle() {
        let env = BoardsEnv()
        env.state.openProduct(env.product("p-1", "VN_Socialfi"))
        env.state.openExecution(env.execution("e-1", "Sprint 12"))
        XCTAssertNil(env.state.scopeTitle(accountId: "other", scopeId: "p-1", bugs: true))
        XCTAssertNil(env.state.scopeTitle(accountId: "zt1", scopeId: "e-2", bugs: false))
    }

    func testTaskBoardIsTitledByThePickedExecution() {
        let env = BoardsEnv(section: ZentaoSection.tasks)
        env.state.openExecution(env.execution("e-1", "Sprint 12"))
        XCTAssertEqual(env.state.scopeTitle(accountId: "zt1", scopeId: "e-1", bugs: false), "Sprint 12")
        XCTAssertNil(env.state.product, "opening an execution clears the product: the two boards are exclusive")
    }

    // MARK: Parent vs child execution scoping

    private func scopingEnv() -> BoardsEnv {
        let env = BoardsEnv(tickets: [boardBug("1", execution: "exec_1"), boardBug("2", execution: "exec_2"), boardBug("3")])
        env.state.openProduct(env.product("p1", "VN_IM_Chat"))
        return env
    }

    func testParentProductWithNoExecutionScopesAllItsBugs() {
        let env = scopingEnv()
        let all = [boardBug("1", execution: "exec_1"), boardBug("2", execution: "exec_2"), boardBug("3")]
        XCTAssertEqual(Set(env.state.scopeBugs(all).map(\.externalKey)), ["1", "2", "3"])
    }

    func testChildExecutionNarrowsBugsExclusivelyToThatExecution() {
        let env = scopingEnv()
        env.state.selectExecution(env.execution("exec_1", "Sprint 1"))
        let all = [boardBug("1", execution: "exec_1"), boardBug("2", execution: "exec_2"), boardBug("3")]
        XCTAssertEqual(env.state.scopeBugs(all).map(\.externalKey), ["1"])
    }

    func testAnotherProductsBugsAndAnUnpickedBoardScopeToNothing() {
        let env = scopingEnv()
        XCTAssertTrue(env.state.scopeBugs([boardBug("9", product: "other")]).isEmpty)
        env.state.clearProduct()
        XCTAssertTrue(env.state.scopeBugs([boardBug("1")]).isEmpty, "bugs are listed per product: none until one is picked")
        XCTAssertTrue(env.state.scopeTasks([boardTask("1")]).isEmpty, "tasks are listed per execution")
    }

    func testTasksScopeToTheOpenExecutionWhileItsPlaceMatches() {
        let env = BoardsEnv(section: ZentaoSection.tasks)
        env.state.openExecution(env.execution("e1"))
        let mine = boardTask("1", execution: "e1"), other = boardTask("2", execution: "e2")
        XCTAssertEqual(env.state.scopeTasks([mine, other]).map(\.externalKey), ["1"])
        env.nav.setScope("e2", accountId: "zt1")
        XCTAssertTrue(env.state.scopeTasks([mine, other]).isEmpty, "a reset or another scope must not keep showing the selection")
    }

    // MARK: Bug streams

    private func manyBugs(_ n: Int, status: String = "active") -> [Ticket] { (1...n).map { boardBug("\($0)", providerStatus: status) } }

    func testOpeningAProductLoadsTheThreeBugViewsAndNotTheClosedOne() async {
        let env = BoardsEnv()
        env.state.openProduct(env.product())
        await env.wait { env.pages.calls.count >= 3 }
        XCTAssertEqual(Set(env.pages.calls.map(\.browseType)), ["unconfirmed", "unresolved", "toclosed"])
        XCTAssertEqual(env.pages.calls.first?.limit, kPagedViewPageSize)
        XCTAssertEqual(env.pages.calls.first?.page, 1)
        XCTAssertNil(env.state.bugStreams.views[.all].flatMap { $0.started ? $0 : nil }, "Closed's view waits for its column")
    }

    func testTheRelatedTabLoadsOneMergedViewReadWhole() async {
        let env = BoardsEnv()
        env.pages.script = ["assigntome": [boardBug("1")], "openedbyme": [boardBug("2")], "resolvedbyme": [boardBug("3", providerStatus: "resolved", resolution: "fixed")]]
        env.state.setBugTab(.relatedToMe)
        env.state.openProduct(env.product())
        await env.wait { env.state.bugStreams.views[.relatedToMe]?.started == true }
        XCTAssertEqual(Set(env.pages.calls.map(\.browseType)), ["assigntome", "openedbyme", "resolvedbyme"])
        let view = env.state.bugStreams.views[.relatedToMe]
        XCTAssertEqual(view?.ids.count, 3)
        XCTAssertEqual(view?.hasMore, false, "a merged view is read to its end as one page")
        XCTAssertEqual(ZenTaoBugStream.of(.closed, related: env.state.bugRelated), .relatedToMe)
    }

    func testChangingTheRelatedTabRestartsTheViewsButOtherTabsDoNot() async {
        let env = BoardsEnv()
        env.state.openProduct(env.product())
        await env.wait { env.pages.calls.count >= 3 }
        let before = env.pages.calls.count
        env.state.setBugTab(.all)
        XCTAssertEqual(env.pages.calls.count, before, "All vs Unclosed share the views")
        env.state.setBugTab(.relatedToMe)
        await env.wait { env.pages.calls.count > before }
        XCTAssertGreaterThan(env.pages.calls.count, before)
        XCTAssertTrue(env.state.bugRelated)
    }

    func testAColumnPagesItsViewOnDemandAndFilteredBoardsScanSeveralPages() async {
        let env = BoardsEnv()
        env.pages.script = ["unresolved": manyBugs(120)]
        env.state.openProduct(env.product())
        env.state.bugBoard.clearAll()   // from the default open statuses to no filter: one page per load
        await env.wait { env.state.bugStreams.views[.unresolved]?.started == true }
        XCTAssertEqual(env.state.bugStreams.views[.unresolved]?.ids.count, 50)
        XCTAssertTrue(env.state.bugStream(.confirmedToFix).hasMore)
        await env.state.bugStreams.loadMore(.unresolved, visible: 50)
        XCTAssertEqual(env.state.bugStreams.views[.unresolved]?.ids.count, 100)
        env.state.bugBoard.toggleSeverity(1)
        XCTAssertTrue(env.state.bugBoard.filter.narrowsTickets)
    }

    /// A bug filed elsewhere shows on the board once it is read again, and the pages already scrolled through stay.
    func testRefreshingTheBoardOnScreenAddsNewTicketsAndKeepsTheLoadedPages() async {
        let env = BoardsEnv()
        let bugs = manyBugs(120)
        env.pages.script = ["unresolved": bugs]
        env.state.openProduct(env.product())
        env.state.bugBoard.clearAll()
        await env.wait { env.state.bugStreams.views[.unresolved]?.started == true }
        await env.state.bugStreams.loadMore(.unresolved, visible: 50)
        XCTAssertEqual(env.state.bugStreams.views[.unresolved]?.ids.count, 100)
        // Bug 500 is filed on the web: the newest first, at the top of the view.
        env.pages.script = ["unresolved": [boardBug("500")] + bugs]
        let before = env.pages.calls.count
        await env.state.refreshShownBoards()
        let unresolved = env.state.bugStreams.views[.unresolved]
        XCTAssertTrue(unresolved?.ids.contains(boardBug("500").id) == true)
        XCTAssertEqual(unresolved?.ids.count, 101, "the two pages already read are kept")
        XCTAssertEqual(unresolved?.page, 2)
        XCTAssertEqual(unresolved?.total, 121)
        XCTAssertTrue(env.pages.calls.dropFirst(before).allSatisfy { $0.page == 1 }, "only first pages are read again")
        // A board that is not on screen is not read.
        env.state.bugBoard.isActive = false
        let quiet = env.pages.calls.count
        await env.state.refreshShownBoards()
        XCTAssertEqual(env.pages.calls.count, quiet)
    }

    func testAFailedViewWaitsForRetryAndTheSliceReportsLoadingThenData() async {
        let env = BoardsEnv()
        env.pages.failing = ["toclosed"]
        env.state.openProduct(env.product())
        await env.wait { env.state.bugStreams.views[.toClose]?.failure != nil }
        XCTAssertNotNil(env.state.bugStream(.resolvedVerify).failure)
        XCTAssertFalse(env.state.bugStream(.resolvedVerify).canLoadMore)
        env.pages.failing = []
        await env.state.bugStreams.retry(.toClose)
        XCTAssertNil(env.state.bugStream(.resolvedVerify).failure)
        XCTAssertNotNil(env.state.bugSlice.value)
    }

    func testTheSliceIsAnErrorOnlyWhenEveryOpeningViewFailed() async {
        let env = BoardsEnv()
        env.pages.failing = ["unconfirmed", "unresolved", "toclosed"]
        env.state.openProduct(env.product())
        await env.wait { env.state.bugSlice.failure != nil }
        XCTAssertNotNil(env.state.bugSlice.failure)
    }

    func testBugFetchSortIsNewestUnlessTheListIsShownAndStatusSortsNever() {
        let env = BoardsEnv()
        env.state.bugSort = TicketSort(.priority)
        XCTAssertEqual(env.state.bugFetchSort, .newest)
        env.state.bugListMode = true
        XCTAssertEqual(env.state.bugFetchSort, TicketSort(.priority))
        env.state.bugSort = TicketSort(.status)
        XCTAssertEqual(env.state.bugFetchSort, .newest, "sorting by status orders the views, not the tickets within one")
    }

    func testANewTableOrderStartsEveryViewOverFromItsFirstPage() async {
        let env = BoardsEnv()
        env.state.refreshFetchSorts()
        env.state.openProduct(env.product())
        await env.wait { env.pages.calls.count >= 3 }
        let before = env.pages.calls.count
        env.state.bugListMode = true
        env.state.bugSort = TicketSort(.title)
        env.state.refreshFetchSorts()
        await env.wait { env.pages.calls.count >= before + 3 }
        XCTAssertEqual(env.pages.calls.last?.sort, TicketSort(.title))
    }

    func testHasMoreIgnoresTheClosedViewUnlessTheAllTabShowsIt() async {
        let env = BoardsEnv()
        env.pages.script = ["all": manyBugs(80, status: "closed")]
        env.state.openProduct(env.product())
        await env.wait { env.pages.calls.count >= 3 }
        await env.state.bugStreams.loadMore(.all)
        XCTAssertTrue(env.state.bugStreams.views[.all]?.hasMore == true)
        XCTAssertFalse(env.state.bugHasMore, "Unclosed has no Closed column")
        env.state.setBugTab(.all)
        XCTAssertTrue(env.state.bugHasMore)
    }

    // MARK: Task streams

    func testOpeningAnExecutionLoadsEveryStatusViewWithItsBrowseType() async {
        let env = BoardsEnv(section: ZentaoSection.tasks)
        env.state.openExecution(env.execution())
        await env.wait { env.pages.calls.count >= 6 }
        XCTAssertEqual(Set(env.pages.calls.map(\.browseType)), ["wait", "doing", "pause", "done", "closed", "cancel"])
        XCTAssertEqual(Set(env.pages.calls.map(\.scope)), ["e1"])
        XCTAssertTrue(env.state.taskSlice.value != nil || env.state.taskSlice.isLoading)
        await env.wait { env.state.taskSlice.value != nil }
        XCTAssertNotNil(env.state.taskSlice.value)
    }

    func testNoExecutionMeansNothingToPageAndAFinishedSlice() {
        let env = BoardsEnv(section: ZentaoSection.tasks)
        XCTAssertEqual(env.state.taskSlice.value, [])
        XCTAssertFalse(env.state.taskHasMore, "no views are open")
        XCTAssertTrue(env.pages.calls.isEmpty)
    }

    func testSelectingTheOpenExecutionAgainKeepsItsLoadedPages() async {
        let env = BoardsEnv(section: ZentaoSection.tasks)
        env.state.openExecution(env.execution())
        await env.wait { env.pages.calls.count >= 6 }
        let n = env.pages.calls.count
        env.state.openExecution(env.execution())
        try? await Task.sleep(for: .milliseconds(80))
        XCTAssertEqual(env.pages.calls.count, n)
    }

    // MARK: Keep the board on a product / execution

    func testKeepBugBoardPicksTheScopedProductElseAPinnedElseTheFirst() async {
        let env = BoardsEnv()
        env.pages.products = [env.product("p1", "A"), env.product("p2", "B"), env.product("p3", "C")]
        env.state.keepBugBoardProduct(account: env.store.accounts["zt1"]!, location: env.nav.location(for: "zt1"))
        await env.wait { env.state.products["zt1"]?.value != nil }
        env.state.keepBugBoardProduct(account: env.store.accounts["zt1"]!, location: env.nav.location(for: "zt1"))
        XCTAssertEqual(env.state.product?.productId, "p1", "the first when nothing is scoped or pinned")

        let pinned = BoardsEnv()
        pinned.pages.products = env.pages.products
        pinned.store.settings.pinnedProjects = ["zt1:p3"]
        pinned.state.bugBoard.start()
        await pinned.wait { pinned.state.bugBoard.settings.pinnedProjects == ["zt1:p3"] }
        pinned.state.loadProducts("zt1")
        await pinned.wait { pinned.state.products["zt1"]?.value != nil }
        pinned.state.keepBugBoardProduct(account: pinned.store.accounts["zt1"]!, location: ToolLocation(section: ZentaoSection.bugs))
        XCTAssertEqual(pinned.state.product?.productId, "p3")

        pinned.nav.setScope("p2", accountId: "zt1")
        pinned.state.keepBugBoardProduct(account: pinned.store.accounts["zt1"]!, location: pinned.nav.location(for: "zt1"))
        XCTAssertEqual(pinned.state.product?.productId, "p2", "the scope's own product wins")
    }

    func testKeepTaskBoardPicksTheFirstExecutionOfTheFirstProjectAndNeverAProject() async {
        let env = BoardsEnv(section: ZentaoSection.tasks)
        env.pages.projects = [ProviderProject(id: "pj1", name: "Alpha", accountId: "zt1")]
        env.pages.executions = ["pj1": [env.execution("e7", "Sprint 7")]]
        let account = env.store.accounts["zt1"]!
        for _ in 0..<6 where env.state.execution == nil {
            env.state.keepTaskBoardScope(account: account, location: env.nav.location(for: "zt1"))
            try? await Task.sleep(for: .milliseconds(30))
        }
        XCTAssertEqual(env.state.execution?.executionId, "e7")
        XCTAssertEqual(env.nav.location(for: "zt1").scopeId, "e7")
        XCTAssertTrue(env.state.taskBoardHasExecution(account: account, location: env.nav.location(for: "zt1")))
        XCTAssertFalse(env.state.taskBoardHasExecution(account: account, location: ToolLocation(section: ZentaoSection.tasks, scopeId: "pj1")))
    }

    func testKeepTaskBoardPrefersAPinnedExecution() async {
        let env = BoardsEnv(section: ZentaoSection.tasks)
        env.pages.projects = [ProviderProject(id: "pj1", name: "Alpha", accountId: "zt1")]
        env.pages.executions = ["pj1": [env.execution("e1"), env.execution("e2", "Two")]]
        env.store.settings.pinnedExecutions = ["zt1:e2"]
        env.state.taskBoard.start()
        await env.wait { env.state.taskBoard.settings.pinnedExecutions == ["zt1:e2"] }
        let account = env.store.accounts["zt1"]!
        for _ in 0..<6 where env.state.execution == nil {
            env.state.keepTaskBoardScope(account: account, location: env.nav.location(for: "zt1"))
            try? await Task.sleep(for: .milliseconds(30))
        }
        XCTAssertEqual(env.state.execution?.executionId, "e2")
    }

    // MARK: Board models

    private let now = Date()
    private func query(_ t: [Ticket], filter: FilterState = FilterState()) -> BoardQuery {
        BoardQuery(tickets: t, filter: filter, accountWorkspace: ["zt1": "w1"], now: now)
    }

    func testBugBoardGroupsByColumnWithPriorityThenRecencyAndDropsClosedOnUnclosed() {
        let t = [boardBug("1", status: .inbox), boardBug("2"), boardBug("3", providerStatus: "resolved", resolution: "fixed"),
                 boardBug("4", providerStatus: "resolved", resolution: "postponed"), boardBug("5", providerStatus: "resolved", resolution: "bydesign"),
                 boardBug("6", providerStatus: "closed"), boardBug("7", updated: now), boardBug("8", updated: now.addingTimeInterval(-60)),
                 boardBug("9", priority: .urgent)]
        let all = BuildZenTaoBugBoard(includeClosed: true)(query(t))
        XCTAssertEqual(all.columns.map(\.column), ZenTaoBugColumn.columns)
        XCTAssertEqual(all.column(.newUnconfirmed)?.tickets.map(\.externalKey), ["1"])
        XCTAssertEqual(all.column(.confirmedToFix)?.tickets.map(\.externalKey), ["9", "7", "8", "2"], "priority first, then newest")
        XCTAssertEqual(all.column(.resolvedVerify)?.count, 1)
        XCTAssertEqual(all.column(.postponed)?.count, 1)
        XCTAssertEqual(all.column(.nonFix)?.count, 1)
        XCTAssertEqual(all.column(.closed)?.count, 1)
        let unclosed = BuildZenTaoBugBoard(includeClosed: false)(query(t))
        XCTAssertNil(unclosed.column(.closed))
        XCTAssertEqual(unclosed.total, all.total - 1)
    }

    func testTaskBoardGroupsByColumnAndKeepsOnlyThisWeeksDeadlinesOnTheDueTab() {
        let soon = AppDateFormatBridge.iso(now), late = AppDateFormatBridge.iso(now.addingTimeInterval(-86_400 * 30))
        let t = [boardTask("1"), boardTask("2", providerStatus: "doing", status: .inprogress, deadline: soon),
                 boardTask("3", providerStatus: "pause", status: .blocked, deadline: late), boardTask("4", providerStatus: "done", status: .review),
                 boardTask("5", providerStatus: "closed", status: .done), boardTask("6", providerStatus: "cancel", status: .done), boardBug("7")]
        let all = BuildZenTaoTaskBoard()(query(t))
        XCTAssertEqual(all.total, 6, "bugs are not tasks")
        XCTAssertEqual(all.column(.inProgress)?.count, 1)
        XCTAssertEqual(all.column(.paused)?.count, 1)
        XCTAssertEqual(all.column(.canceled)?.count, 1)
        let due = BuildZenTaoTaskBoard(dueThisWeekOnly: true)(query(t))
        XCTAssertEqual(due.columns.flatMap(\.tickets).map(\.externalKey), ["2"])
    }

    func testFacetCatalogOffersEveryFixedChoiceAndThePeopleOnceTheyLoad() {
        let members = [ProviderUser(account: "bob", displayName: "Bob"), ProviderUser(account: "ann", displayName: "Ann")]
        let bugs = BuildZenTaoFacetCatalog()(ZenTaoFacetCatalogInput(bugs: true, members: members, modules: [ZentaoModulePath(id: "0", path: "/"), ZentaoModulePath(id: "7", path: "Live/Share")])).choices
        XCTAssertEqual(bugs[.status]?.map(\.value), ZenTaoBugColumn.columns.map(\.name))
        XCTAssertEqual(bugs[.assignee]?.map(\.value), ["ann", "bob", ""], "by login, then unassigned")
        XCTAssertEqual(bugs[.assignee]?.first?.label, "Ann")
        XCTAssertEqual(bugs[.openedBy]?.map(\.value), ["Ann", "Bob"], "by name")
        XCTAssertEqual(bugs[.module]?.map(\.value), ["7"], "ZenTao's no-module is not a module to pick")
        XCTAssertEqual(bugs[.severity]?.count, 4)
        XCTAssertEqual(bugs[.confirmed]?.map(\.value), ["1", "0"])
        XCTAssertNotNil(bugs[.resolution]); XCTAssertNotNil(bugs[.bugType])
        let tasks = BuildZenTaoFacetCatalog()(ZenTaoFacetCatalogInput(bugs: false, members: [])).choices
        XCTAssertEqual(tasks[.status]?.map(\.value), ZenTaoTaskColumn.columns.map(\.name))
        XCTAssertNil(tasks[.assignee], "no members, no assignee choices: the tickets' own people stay")
        XCTAssertNil(tasks[.module]); XCTAssertNil(tasks[.severity])
    }

    func testMetricsCountOnlyTheAccountUsersOpenTasksAndBugs() {
        let account = Account(id: "zt1", workspaceId: "w1", providerType: .zentao, handle: "thanh")
        let t = [boardTask("1", assignee: "thanh"), boardTask("2", providerStatus: "done", status: .review, assignee: "thanh"),
                 boardTask("3", assignee: "other"), boardBug("4", assignee: "thanh"), boardBug("5", providerStatus: "closed", status: .done, assignee: "thanh"),
                 boardBug("6", assignee: "thanh")]
        let m = ComputeZentaoMetrics()(tickets: t, account: account)
        XCTAssertEqual(m.primaryCount, 1)
        XCTAssertEqual(m.secondaryCount, 2)
    }

    // MARK: Tables

    func testTaskTableStopsAtTheFirstViewThatHasMorePages() async {
        let env = BoardsEnv(section: ZentaoSection.tasks, tickets: [boardTask("1"), boardTask("2", providerStatus: "doing", status: .inprogress)])
        env.pages.script = ["wait": (1...60).map { boardTask("w\($0)") }]
        env.state.openExecution(env.execution())
        await env.wait { env.state.taskStreams.views[.notStarted]?.started == true && env.state.taskBoard.tickets.count == 2 }
        let table = ZentaoBoards.taskTable(env.state)
        XCTAssertEqual(table.pending, .notStarted, "Not started still has pages, so later statuses wait")
        XCTAssertTrue(table.rows.allSatisfy { zentaoTaskColumnFor($0) == .notStarted })
    }

    func testBugTableGroupsViewsAndSortsRowsWithinAView() async {
        let bugs = [boardBug("1"), boardBug("2"), boardBug("3", providerStatus: "resolved", resolution: "fixed")]
        let env = BoardsEnv(tickets: bugs)
        // A view that has loaded keeps only the tickets it holds: the views must hold these.
        env.pages.script = ["unresolved": Array(bugs[0...1]), "toclosed": [bugs[2]]]
        env.state.openProduct(env.product())
        env.state.bugBoard.clearAll()   // the resolved bug is outside the default open statuses
        await env.wait { env.state.bugBoard.scoped.count == 3 }
        let table = ZentaoBoards.bugTable(env.state)
        XCTAssertNil(table.pending)
        XCTAssertEqual(table.rows.map(\.externalKey), ["2", "1", "3"], "newest id first within a view, views in column order")
        env.state.bugSort = TicketSort(.id)
        XCTAssertEqual(ZentaoBoards.bugTable(env.state).rows.map(\.externalKey), ["1", "2", "3"])
    }

    func testShownCountComparesTheFilteredBoardWithTheUnfilteredOne() async {
        let bugs = [boardBug("1", severity: 1), boardBug("2", severity: 2), boardBug("3", severity: 2)]
        let env = BoardsEnv(tickets: bugs)
        env.pages.script = ["unresolved": bugs]
        env.state.openProduct(env.product())
        await env.wait { env.state.bugBoard.scoped.count == 3 }
        env.state.bugBoard.toggleSeverity(2)
        let n = ZentaoBoards.bugShownCount(env.state)
        XCTAssertEqual(n.shown, 2); XCTAssertEqual(n.total, 3)
    }

    // MARK: Drops

    func testDropRulesFollowTheBugWorkflow() {
        let new = boardBug("1", status: .inbox), active = boardBug("2"), resolved = boardBug("3", providerStatus: "resolved", resolution: "fixed"),
            closed = boardBug("4", providerStatus: "closed")
        XCTAssertFalse(ZentaoBugDrops.canDrop(active, onto: .newUnconfirmed), "ZenTao has no un-confirm")
        XCTAssertFalse(ZentaoBugDrops.canDrop(active, onto: .closed))
        XCTAssertFalse(ZentaoBugDrops.canDrop(active, onto: .confirmedToFix), "already there")
        XCTAssertTrue(ZentaoBugDrops.canDrop(new, onto: .confirmedToFix))
        XCTAssertTrue(ZentaoBugDrops.canDrop(resolved, onto: .confirmedToFix))
        XCTAssertTrue(ZentaoBugDrops.canDrop(active, onto: .resolvedVerify))
        XCTAssertEqual(ZentaoBugDrops.kind(new, onto: .confirmedToFix), .confirm)
        XCTAssertEqual(ZentaoBugDrops.kind(closed, onto: .confirmedToFix), .activate)
        XCTAssertEqual(ZentaoBugDrops.kind(active, onto: .resolvedVerify), .resolve("fixed"))
        XCTAssertEqual(ZentaoBugDrops.kind(active, onto: .postponed), .resolve("postponed"))
        XCTAssertEqual(ZentaoBugDrops.kind(active, onto: .nonFix), .askNonFix)
        XCTAssertNil(ZentaoBugDrops.kind(active, onto: .closed))
    }

    func testRunningADropCallsTheWorkflowAndReportsTheOutcome() async {
        let wf = DetailFakeWorkflow()
        let ok = await ZentaoBugDrops.run(.resolve("fixed"), ticket: boardBug("1"), workflow: wf)
        XCTAssertEqual(wf.bugCalls, ["resolve:fixed"]); XCTAssertTrue(ok.ok); XCTAssertTrue(ok.message.contains("Fixed"))
        _ = await ZentaoBugDrops.run(.confirm, ticket: boardBug("1"), workflow: wf)
        _ = await ZentaoBugDrops.run(.activate, ticket: boardBug("1"), workflow: wf)
        XCTAssertEqual(wf.bugCalls, ["resolve:fixed", "confirm", "activate:trunk"])
        wf.failure = .network("boom")
        let bad = await ZentaoBugDrops.run(.confirm, ticket: boardBug("1"), workflow: wf)
        XCTAssertFalse(bad.ok); XCTAssertTrue(bad.message.contains("boom"))
    }

    // MARK: Formatting helpers

    func testTitleTagsAreSplitOffAndAnAllTagTitleKeepsThem() {
        XCTAssertEqual(ZentaoFormatters.extractTags("[Discovery][Change Request] Login").title, "Login")
        XCTAssertEqual(ZentaoFormatters.extractTags("[Discovery][Change Request] Login").tags, ["Discovery", "Change Request"])
        XCTAssertEqual(ZentaoFormatters.extractTags("[Mobile] [SocialFi] Title").tags, ["Mobile", "SocialFi"])
        XCTAssertEqual(ZentaoFormatters.extractTags("[Only]").title, "[Only]")
        XCTAssertEqual(ZentaoFormatters.extractTags("Plain").tags, [])
        XCTAssertEqual(ZentaoFormatters.extractModule("[Mobile] Title").module, "[Mobile]")
        XCTAssertEqual(ZentaoFormatters.extractModule("[Mobile] Title").title, "Title")
        XCTAssertNil(ZentaoFormatters.extractModule("Title").module)
    }

    func testDelayTextCountsWholeDaysAndOnlyForPastDeadlines() {
        let now = Date()
        XCTAssertNil(ZentaoFormatters.delayText(nil))
        XCTAssertNil(ZentaoFormatters.delayText(now.addingTimeInterval(3600), now: now))
        XCTAssertEqual(ZentaoFormatters.delayText(now.addingTimeInterval(-3600), now: now), "Delay 1 day")
        XCTAssertEqual(ZentaoFormatters.delayText(now.addingTimeInterval(-86_400 * 45 - 5), now: now), "Delay 45 days")
    }

    func testCardAgeReadsMinutesHoursOrDays() {
        let now = Date()
        XCTAssertNil(ZentaoCardTopLine.age(nil))
        XCTAssertEqual(ZentaoCardTopLine.age(now.addingTimeInterval(-10), now: now), "1m ago")
        XCTAssertEqual(ZentaoCardTopLine.age(now.addingTimeInterval(-60 * 5), now: now), "5m ago")
        XCTAssertEqual(ZentaoCardTopLine.age(now.addingTimeInterval(-3600 * 3), now: now), "3h ago")
        XCTAssertEqual(ZentaoCardTopLine.age(now.addingTimeInterval(-86_400 * 2), now: now), "2d ago")
    }

    func testViewModeFallsBackToTheRememberedOneThenTheBoard() {
        var settings = AppSettings(); settings.viewModes["zentao.bugs"] = "list"
        XCTAssertEqual(ZentaoSectionMode.mode(ToolLocation(section: ZentaoSection.bugs), ZentaoSection.bugs, settings: settings), "list")
        XCTAssertEqual(ZentaoSectionMode.mode(ToolLocation(section: ZentaoSection.tasks), ZentaoSection.tasks, settings: settings), "board")
        let loc = ToolLocation(section: ZentaoSection.bugs, viewModes: [ZentaoSection.bugs: "board"])
        XCTAssertEqual(ZentaoSectionMode.mode(loc, ZentaoSection.bugs, settings: settings), "board")
    }
}
