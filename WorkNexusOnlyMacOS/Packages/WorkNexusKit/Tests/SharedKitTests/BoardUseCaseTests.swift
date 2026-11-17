import CoreDomain
import XCTest
@testable import SharedKit

/// Ported from: test/domain/{build_paged_table,build_saved_filter,is_saved_filter_applied,switch_board_filter,
/// search_local_tickets,scope_provider_tickets,is_assigned_to_me,related_to_me}_test.dart, test/unit/board_filter_memory_test.dart
final class BoardUseCaseTests: XCTestCase {
    // MARK: BuildPagedTable
    private func task(_ key: String, title: String = "", priority: Priority = .medium) -> Ticket {
        makeTicket("zt:task:\(key)", account: "zt", project: "p", provider: .zentao, key: key, providerStatus: "wait",
                   priority: priority, title: title.isEmpty ? key : title, type: "Task")
    }
    private func build(_ segments: [PagedTableSegment<String>], _ sort: TicketSort = .newest) -> PagedTable<String> {
        BuildPagedTable<String>()(PagedTableQuery(segments: segments, sort: sort))
    }
    private func keys(_ t: PagedTable<String>) -> [String] { t.rows.map(\.externalKey) }

    func testPagedTableListsViewByViewNewestFirst() {
        let t = build([PagedTableSegment(view: "wait", tickets: [task("9"), task("120"), task("31")], complete: true),
                       PagedTableSegment(view: "doing", tickets: [task("200"), task("7")], complete: true)])
        XCTAssertEqual(keys(t), ["120", "31", "9", "200", "7"])
        XCTAssertNil(t.pending)
    }

    func testPagedTableStopsAtFirstViewWithPagesLeft() {
        let t = build([PagedTableSegment(view: "wait", tickets: [task("5")], complete: true),
                       PagedTableSegment(view: "doing", tickets: [task("4")], complete: false),
                       PagedTableSegment(view: "done", tickets: [task("3")], complete: true)])
        XCTAssertEqual(keys(t), ["5", "4"])
        XCTAssertEqual(t.pending, "doing")
    }

    func testPagedTableEmptyUnfinishedFirstViewStillAsksForMore() {
        let t = build([PagedTableSegment(view: "wait", tickets: [], complete: false), PagedTableSegment(view: "doing", tickets: [task("1")], complete: true)])
        XCTAssertTrue(t.rows.isEmpty)
        XCTAssertEqual(t.pending, "wait")
    }

    func testPagedTableSortsWithinEachViewIdsBreakingTies() {
        let t = build([PagedTableSegment(view: "wait", tickets: [task("1", priority: .low), task("2", priority: .urgent), task("3", priority: .low)], complete: true),
                       PagedTableSegment(view: "doing", tickets: [task("8", title: "beta"), task("9", title: "Alpha")], complete: true)],
                      TicketSort(.priority))
        XCTAssertEqual(keys(t), ["2", "3", "1", "9", "8"])
    }

    func testPagedTableStatusDescendingReversesViews() {
        let t = build([PagedTableSegment(view: "wait", tickets: [task("1")], complete: true),
                       PagedTableSegment(view: "doing", tickets: [task("2")], complete: false)], TicketSort(.status, descending: true))
        XCTAssertEqual(keys(t), ["2"])
        XCTAssertEqual(t.pending, "doing")
    }

    func testHeaderClickTogglesSort() {
        let byId = TicketSort.newest
        XCTAssertFalse(byId.toggled(.id).descending)
        XCTAssertFalse(byId.toggled(.title).descending)
        XCTAssertTrue(byId.toggled(.updated).descending)
    }

    // MARK: BuildSavedFilter / IsSavedFilterApplied
    func testBuildSavedFilter() {
        var urgent = FilterState(); urgent.priorities = [.urgent]
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let make = BuildSavedFilter()
        let p = make(name: "  Urgent only  ", filter: urgent, existing: [], now: now)
        XCTAssertEqual(p?.name, "Urgent only"); XCTAssertEqual(p?.filter, urgent); XCTAssertEqual(p?.createdAt, now)
        XCTAssertNil(make(name: "   ", filter: urgent, existing: [], now: now))
        let existing = SavedFilter(id: "sf-1", name: "Urgent only", filter: FilterState(), createdAt: Date(timeIntervalSince1970: 0))
        XCTAssertEqual(make(name: "URGENT ONLY", filter: urgent, existing: [existing], now: now)?.id, "sf-1")
        XCTAssertNotEqual(make(name: "Blocked", filter: urgent, existing: [existing], now: now)?.id, "sf-1")
    }

    private func preset(_ f: FilterState) -> SavedFilter { SavedFilter(id: "sf-1", name: "MyTeam", filter: f, createdAt: Date(timeIntervalSince1970: 0)) }

    func testIsSavedFilterApplied() {
        let applied = IsSavedFilterApplied()
        var team = FilterState(); team.assignees = ["thanh", "an"]; team.severities = [1]
        let myTeam = preset(team)
        XCTAssertTrue(applied(myTeam, team))
        var more = team; more.severities = [1, 2]
        XCTAssertFalse(applied(myTeam, more))
        XCTAssertFalse(applied(myTeam, FilterState()))
        var onView = team; onView.savedView = .related     // a preset saved on All matches on any tab
        XCTAssertTrue(applied(myTeam, onView))
        var related = FilterState(); related.savedView = .related
        XCTAssertTrue(applied(preset(related), related)); XCTAssertFalse(applied(preset(related), FilterState()))
        var ws = team; ws.workspaceId = "ws-2"; XCTAssertTrue(applied(myTeam, ws))          // the workspace never counts
        var search = team; search.search = "login"; XCTAssertTrue(applied(myTeam, search))   // search over a preset without one
        var module = team; module.modules = ["12"]; XCTAssertTrue(applied(myTeam, module))
        var inFeed = FilterState(); inFeed.modules = ["12"]
        var other = FilterState(); other.modules = ["13"]
        XCTAssertFalse(applied(preset(inFeed), other))
        var withSearch = FilterState(); withSearch.search = "login"
        XCTAssertTrue(applied(preset(withSearch), withSearch)); XCTAssertFalse(applied(preset(withSearch), FilterState()))
    }

    func testSavedFilterMapperRoundTripsAndDropsWorkspace() {
        var f = FilterState()
        f.workspaceId = "ws-9"; f.savedView = .review; f.providers = [.zentao, .gitlab]; f.priorities = [.urgent]; f.severities = [1, 3]
        f.assignees = ["a"]; f.modules = ["12"]; f.search = "x"
        let back = SavedFilterMapper.decode(SavedFilterMapper.encode(f))
        var expected = f; expected.workspaceId = "all"
        XCTAssertEqual(back, expected)
        XCTAssertEqual(SavedFilterMapper.decode("not json"), FilterState())
        XCTAssertEqual(SavedFilterMapper.decode(#"{"savedView":"mine","statuses":["done","nope"]}"#).savedView, .related)
        XCTAssertEqual(SavedFilterMapper.decode(#"{"statuses":["done","nope"]}"#).statuses, [.done])
    }

    // MARK: ApplyViewHead

    func testApplyViewHeadAddsWhatIsNewAndKeepsWhatWasRead() {
        func t(_ id: String) -> Ticket { makeTicket(id) }
        let read = PagedViewState(ids: ["a", "b", "c"], page: 2, total: 60, hasMore: true)
        let next = ApplyViewHead()(read, ViewPage(tickets: [t("new"), t("a")], total: 61, hasMore: true))
        XCTAssertEqual(next.ids, ["a", "b", "c", "new"]); XCTAssertEqual(next.page, 2); XCTAssertEqual(next.total, 61)
        // A view read to its end that grew past what was read has more again; one that did not stays done.
        let done = PagedViewState(ids: ["a"], page: 1, total: 50, hasMore: false)
        XCTAssertTrue(ApplyViewHead()(done, ViewPage(tickets: [t("x")], total: 51, hasMore: true)).hasMore)
        XCTAssertFalse(ApplyViewHead()(done, ViewPage(tickets: [t("x")], total: 50, hasMore: false)).hasMore)
    }

    // MARK: SwitchBoardFilter
    func testSwitchBoardFilter() {
        let sw = SwitchBoardFilter()
        var mine = FilterState(); mine.assignees = ["thanh"]
        var blocked = FilterState(); blocked.statuses = [.blocked]
        XCTAssertEqual(sw(memory: [:], fromKey: nil, toKey: "zentao:bugs:a:1", current: FilterState(), initial: mine).filter, mine)
        let left = sw(memory: [:], fromKey: "zentao:bugs:a:1", toKey: "gitlab:a:9", current: blocked, initial: FilterState())
        XCTAssertEqual(left.memory["zentao:bugs:a:1"], blocked)
        XCTAssertEqual(left.filter, FilterState())
        XCTAssertEqual(sw(memory: left.memory, fromKey: "gitlab:a:9", toKey: "zentao:bugs:a:1", current: left.filter, initial: mine).filter, blocked)
        XCTAssertEqual(sw(memory: [:], fromKey: "k", toKey: "k", current: blocked, initial: mine).filter, blocked)
    }

    // MARK: SearchLocalTickets
    private func t(_ id: String, _ key: String, _ title: String, account: String = "acc-1") -> Ticket {
        makeTicket(id, account: account, provider: .zentao, key: key, status: .inprogress, providerStatus: "doing", priority: .high, title: title)
    }

    func testSearchLocalTickets() {
        let s = SearchLocalTickets()
        XCTAssertTrue(s(tickets: [t("1", "BUG-1", "First bug")], query: "").isEmpty)
        XCTAssertTrue(s(tickets: [t("1", "BUG-1", "First bug")], query: "   ").isEmpty)
        let ranked = s(tickets: [t("1", "TASK-10", "Update product catalog"), t("2", "TASK-20", "Add logging infrastructure"),
                                 t("3", "LOG-45", "Refactor parser"), t("4", "LOG", "Logging epic")], query: "log")
        XCTAssertEqual(ids(ranked), ["4", "3", "2", "1"])
        XCTAssertEqual(s(tickets: (0..<15).map { t("\($0)", "TASK-\($0)", "Task item \($0)") }, query: "TASK").count, 8)
        XCTAssertEqual(ids(s(tickets: [t("1", "TASK-1", "Auth task"), t("2", "TASK-2", "Auth task", account: "acc-2")], query: "Auth", accountId: "acc-1")), ["1"])
        XCTAssertEqual(ids(s(tickets: [t("1", "bug-2041", "Crash on launch")], query: "BUG-2041")), ["1"])
    }

    // MARK: ScopeProviderTickets
    func testScopeProviderTickets() {
        let scope = ScopeProviderTickets()
        let tickets = [makeTicket("a", account: "acc", provider: .gitlab, type: "MergeRequest"),
                       makeTicket("b", account: "acc", provider: .gitlab, labels: ["gitlab-project:7"], type: "mergerequest"),
                       makeTicket("c", account: "other", provider: .gitlab, type: "MergeRequest"),
                       makeTicket("d", account: "acc", provider: .github, type: "MergeRequest")]
        XCTAssertEqual(ids(scope(tickets: tickets, accountId: "acc", providerType: .gitlab, externalType: "MergeRequest", slice: nil)), ["a", "b"])
        XCTAssertEqual(ids(scope(tickets: tickets, accountId: "acc", providerType: .gitlab, externalType: "MergeRequest", slice: nil, membershipLabel: "gitlab-project:7")), ["b"])
        XCTAssertEqual(ids(scope(tickets: tickets, accountId: "acc", providerType: .gitlab, externalType: "MergeRequest", slice: ["a"])), ["a"])
    }

    // MARK: IsAssignedToMe / IsRelatedToMe
    private let me = Account(id: "zt", workspaceId: "ws", providerType: .zentao, handle: "thanh.nguyen")

    func testIsAssignedToMe() {
        let mine = IsAssignedToMe()
        func a(_ name: String?) -> Ticket { makeTicket("zt:bug:1", account: "zt", provider: .zentao, assignee: name) }
        XCTAssertTrue(mine(a("Thanh.Nguyen"), me)); XCTAssertTrue(mine(a("thanh_nguyen"), me))
        XCTAssertFalse(mine(a("thanh.nguyen2"), me)); XCTAssertFalse(mine(a("thanh"), me)); XCTAssertFalse(mine(a("-"), me))
    }

    func testIsRelatedToMeCountsOpenedAndResolved() {
        let related = IsRelatedToMe()
        func bug(_ e: ZenTaoBugEntity) -> Ticket { makeTicket("b", account: "zt", provider: .zentao, assignee: "someone", entity: .zentaoBug(e)) }
        XCTAssertTrue(related(bug(ZenTaoBugEntity(openedByHandle: "thanh.nguyen")), me))
        XCTAssertTrue(related(bug(ZenTaoBugEntity(resolvedByHandle: "Thanh_Nguyen")), me))
        XCTAssertFalse(related(bug(ZenTaoBugEntity(openedByHandle: "x", resolvedByHandle: "y")), me))
        let task = makeTicket("t", account: "zt", provider: .zentao, assignee: "someone", entity: .zentaoTask(ZenTaoTaskEntity(finishedByHandle: "thanh.nguyen")))
        XCTAssertTrue(related(task, me))
    }

    // MARK: Filter memory (BoardController uses the same use case)
    func testFilterMemoryKeepsEachBoardsFilter() {
        let sw = SwitchBoardFilter()
        var urgent = FilterState(); urgent.priorities = [.urgent]
        // Open b1, set a filter, move to b2 (fresh), come back to b1 (restored).
        let toB2 = sw(memory: [:], fromKey: "b1", toKey: "b2", current: urgent, initial: FilterState())
        XCTAssertEqual(toB2.filter, FilterState())
        XCTAssertEqual(toB2.memory["b1"], urgent)
        let backToB1 = sw(memory: toB2.memory, fromKey: "b2", toKey: "b1", current: toB2.filter, initial: FilterState())
        XCTAssertEqual(backToB1.filter, urgent)
    }
}
