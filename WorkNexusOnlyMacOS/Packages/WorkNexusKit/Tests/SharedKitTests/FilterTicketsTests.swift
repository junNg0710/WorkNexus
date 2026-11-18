import CoreDomain
import XCTest
@testable import SharedKit

/// Ported from: test/domain/board_logic_test.dart (FilterTickets, BuildBoard), board_query_equality_test.dart
final class FilterTicketsTests: XCTestCase {
    private let filter = FilterTickets()
    private let now = Date(timeIntervalSince1970: 1_784_289_600)

    private func q(_ tickets: [Ticket], _ f: FilterState, ws: [String: String]? = nil, now: Date? = nil, accounts: [String: Account] = [:]) -> BoardQuery {
        BoardQuery(tickets: tickets, filter: f, accountWorkspace: ws ?? ["ghP": "personal", "ghA": "compA", "ztB": "compB"],
                   now: now ?? self.now, accounts: accounts)
    }
    private func f(_ build: (inout FilterState) -> Void) -> FilterState { var s = FilterState(); build(&s); return s }

    func testWorkspaceScopeExcludesOthers() {
        let t = [makeTicket("a"), makeTicket("b", account: "ghA")]
        XCTAssertEqual(ids(filter(q(t, f { $0.workspaceId = "compA" }))), ["b"])
    }

    func testProviderFilter() {
        let t = [makeTicket("a"), makeTicket("b", account: "ztB", provider: .zentao)]
        XCTAssertEqual(ids(filter(q(t, f { $0.providers = [.zentao] }))), ["b"])
    }

    func testStatusAndPriorityCombine() {
        let t = [makeTicket("a", status: .done, priority: .low), makeTicket("b", status: .done, priority: .urgent), makeTicket("c", priority: .urgent)]
        XCTAssertEqual(ids(filter(q(t, f { $0.statuses = [.done]; $0.priorities = [.urgent] }))), ["b"])
    }

    func testSearchMatchesTitleKeyAndLabelsCaseInsensitively() {
        let t = [makeTicket("a", title: "Fix websocket reconnect"), makeTicket("b", title: "Add shortcuts", labels: ["enhancement"]),
                 makeTicket("c", key: "SILVER-142", title: "Payments")]
        XCTAssertEqual(ids(filter(q(t, f { $0.search = "WEBSOCKET" }))), ["a"])
        XCTAssertEqual(ids(filter(q(t, f { $0.search = "enhancement" }))), ["b"])
        XCTAssertEqual(ids(filter(q(t, f { $0.search = "silver-142" }))), ["c"])
    }

    func testSeverityFilter() {
        let t = [ztBug("crit", providerStatus: "active", severity: 1), ztBug("minor", providerStatus: "active", severity: 3)]
        XCTAssertEqual(ids(filter(q(t, f { $0.severities = [1] }))), ["crit"])
    }

    func testAssigneeFilterAndUnassignedSentinel() {
        let t = [ztBug("mine", providerStatus: "active", assignee: "Thanh"), ztBug("none", providerStatus: "active")]
        XCTAssertEqual(ids(filter(q(t, f { $0.assignees = ["Thanh"] }))), ["mine"])
        XCTAssertEqual(ids(filter(q(t, f { $0.assignees = [""] }))), ["none"])
    }

    func testMyTicketsKeepsBugsIResolvedOrOpened() {
        let resolvedByMe = ztBug("resolved-by-me", providerStatus: "resolved", resolution: "fixed", assignee: "reporter",
                                 entity: ZenTaoBugEntity(resolvedByHandle: "thanh"))
        let openedByMe = ztBug("opened-by-me", providerStatus: "active", assignee: "someoneelse", entity: ZenTaoBugEntity(openedByHandle: "thanh"))
        let theirs = ztBug("theirs", providerStatus: "active", assignee: "someoneelse",
                           entity: ZenTaoBugEntity(openedByHandle: "someoneelse", resolvedByHandle: "someoneelse"))
        XCTAssertEqual(ids(filter(q([resolvedByMe, openedByMe, theirs], f { $0.assignees = ["thanh"] }))), ["resolved-by-me", "opened-by-me"])
    }

    func testReviewerFilterMatchesGitLabMergeRequests() {
        func mr(_ id: String, _ reviewers: [String]) -> Ticket {
            makeTicket(id, account: "gl", provider: .gitlab, type: "MergeRequest", entity: .gitlabItem(GitLabItemEntity(reviewers: reviewers)))
        }
        let t = [mr("needs-review", ["Thanh"]), mr("other-reviewer", ["Terry"])]
        XCTAssertEqual(ids(filter(q(t, f { $0.reviewers = ["Thanh"] }, ws: ["gl": "compA"]))), ["needs-review"])
    }

    func testBugTypeAndResolutionReadTheEntity() {
        let t = [ztBug("code", providerStatus: "active", entity: ZenTaoBugEntity(bugType: "codeerror")),
                 ztBug("cfg", providerStatus: "active", entity: ZenTaoBugEntity(bugType: "config")),
                 ztBug("fixed", providerStatus: "resolved", resolution: "fixed", entity: ZenTaoBugEntity(resolution: "fixed"))]
        XCTAssertEqual(ids(filter(q(t, f { $0.bugTypes = ["codeerror"] }))), ["code"])
        XCTAssertEqual(ids(filter(q(t, f { $0.resolutions = ["fixed"] }))), ["fixed"])
    }

    func testZenTaoStatusMatchesTheBoardColumn() {
        let t = [ztBug("open", providerStatus: "active"), ztBug("fixed", providerStatus: "resolved", resolution: "fixed"),
                 ztBug("dup", providerStatus: "resolved", resolution: "duplicate"), ztTask("done", providerStatus: "done"), makeTicket("gh")]
        XCTAssertEqual(ids(filter(q(t, f { $0.zentaoStatuses = ["resolvedVerify", "doneVerify"] }))), ["fixed", "done"])
    }

    func testResolverReporterConfirmationNarrowBugsOnly() {
        func bug(_ id: String, by: String? = nil, opened: String? = nil, confirmed: Int? = nil) -> Ticket {
            ztBug(id, providerStatus: "resolved", entity: ZenTaoBugEntity(confirmed: confirmed, openedBy: opened, resolvedBy: by))
        }
        let t = [bug("a", by: "Thanh", opened: "Ryan", confirmed: 1), bug("b", by: "Luci", opened: "Ryan", confirmed: 0), bug("c", opened: "Cat"), makeTicket("gh")]
        XCTAssertEqual(ids(filter(q(t, f { $0.resolvers = ["Thanh"] }))), ["a"])
        XCTAssertEqual(ids(filter(q(t, f { $0.reporters = ["Ryan"] }))), ["a", "b"])
        XCTAssertEqual(ids(filter(q(t, f { $0.confirmations = ["0"] }))), ["b", "c"])
        XCTAssertEqual(ids(filter(q(t, f { $0.reporters = ["Ryan"]; $0.confirmations = ["1"] }))), ["a"])
    }

    func testModuleNarrowsToPickedModules() {
        func bug(_ id: String, _ module: String?) -> Ticket { ztBug(id, providerStatus: "active", entity: ZenTaoBugEntity(module: module)) }
        let t = [bug("live", "12"), bug("share", "13"), bug("none", "0"), bug("unknown", nil), makeTicket("gh")]
        XCTAssertEqual(ids(filter(q(t, f { $0.modules = ["12"] }))), ["live"])
        XCTAssertEqual(ids(filter(q(t, f { $0.modules = ["12", "13"] }))), ["live", "share"])
        XCTAssertEqual(filter(q(t, FilterState())).count, 5)
        XCTAssertEqual(f { $0.modules = ["12"] }.activeTokenCount, 1)
    }

    func testPeopleFiltersPassWhenAnyMatches() {
        func bug(_ id: String, to: String? = nil, by: String? = nil, opened: String? = nil) -> Ticket {
            ztBug(id, providerStatus: "active", assignee: to, entity: ZenTaoBugEntity(openedBy: opened, resolvedBy: by))
        }
        let t = [bug("x", to: "thanh", opened: "Ryan"), bug("y", by: "Luci", opened: "Cat"), bug("z", to: "bob", opened: "Cat")]
        XCTAssertEqual(ids(filter(q(t, f { $0.assignees = ["thanh"]; $0.resolvers = ["Luci"] }))), ["x", "y"])
        XCTAssertEqual(ids(filter(q(t, f { $0.assignees = ["thanh"]; $0.reporters = ["Cat"] }))), ["x", "y", "z"])
        XCTAssertTrue(filter(q(t, f { $0.assignees = ["thanh"]; $0.reporters = ["Cat"]; $0.search = "nothing-matches-this" })).isEmpty)
    }

    func testSavedViewMineWithoutAccountIsTodoAndInProgress() {
        let t = [makeTicket("a"), makeTicket("b", status: .inprogress), makeTicket("c", status: .done)]
        XCTAssertEqual(ids(filter(q(t, f { $0.savedView = .mine }))), ["a", "b"])
    }

    func testSavedViewMineWithAccountExcludesOthers() {
        let me = Account(id: "acc1", workspaceId: "compB", providerType: .zentao, handle: "sonvu")
        let t = [makeTicket("mine1", account: "acc1", provider: .zentao, assignee: "sonvu"),
                 makeTicket("other", account: "acc1", provider: .zentao, assignee: "junng"),
                 makeTicket("unassigned", account: "acc1", provider: .zentao),
                 makeTicket("mineDone", account: "acc1", provider: .zentao, status: .done, providerStatus: "closed", assignee: "sonvu")]
        XCTAssertEqual(ids(filter(q(t, f { $0.savedView = .mine }, accounts: ["acc1": me]))), ["mine1"])
    }

    func testSavedViewTodayKeepsRecentlyUpdated() {
        let t = [makeTicket("fresh", updated: now.addingTimeInterval(-2 * 3600)), makeTicket("stale", updated: now.addingTimeInterval(-3 * 86400)), makeTicket("never")]
        XCTAssertEqual(ids(filter(q(t, f { $0.savedView = .today }, now: now))), ["fresh"])
    }

    func testBuildBoardGroupsIntoSixOrderedColumns() {
        let t = [makeTicket("a"), makeTicket("b"), makeTicket("c", status: .done)]
        let board = BuildBoard()(q(t, FilterState()))
        XCTAssertEqual(board.columns.map(\.status), UnifiedStatus.columns)
        XCTAssertEqual(board.total, 3)
        XCTAssertEqual(board.columns.first { $0.status == .todo }?.count, 2)
    }

    func testBuildBoardSortsByPriority() {
        let t = [makeTicket("low", priority: .low), makeTicket("urgent", priority: .urgent), makeTicket("med")]
        let todo = BuildBoard()(q(t, FilterState())).columns.first { $0.status == .todo }!
        XCTAssertEqual(ids(todo.tickets), ["urgent", "med", "low"])
    }

    /// Ported from: test/domain/compare_tickets_test.dart (`BuildBoard orders each column by the query sort`).
    func testBuildBoardOrdersEachColumnByTheQuerySort() {
        let t = [makeTicket("1", key: "1", priority: .urgent, title: "b"), makeTicket("2", key: "2", priority: .low, title: "a")]
        func todo(_ sort: TicketSort) -> [String] {
            var query = q(t, FilterState()); query.sort = sort
            return ids(BuildBoard()(query).columns.first { $0.status == .todo }!.tickets)
        }
        XCTAssertEqual(todo(.boardDefault), ["1", "2"])
        XCTAssertEqual(todo(TicketSort(.title)), ["2", "1"])
    }

    func testAQueryWithAnotherSortIsNotEqualAndAFilterChangeKeepsIt() {
        var other = q([], FilterState()); other.sort = .newest
        XCTAssertEqual(q([], FilterState()).sort, .boardDefault)
        XCTAssertNotEqual(q([], FilterState()), other)
        XCTAssertEqual(other.withFilter(FilterState()).sort, .newest)
    }

    func testQueryEqualityIgnoresNothingRelevant() {
        let a = q([makeTicket("a")], FilterState()), b = q([makeTicket("a")], FilterState())
        XCTAssertEqual(a, b)
        XCTAssertNotEqual(a, a.withFilter(f { $0.search = "x" }))
    }

    func testFilterStateFlags() {
        XCTAssertFalse(FilterState().narrowsTickets)
        XCTAssertTrue(f { $0.workspaceId = "w" }.narrowsTickets)
        XCTAssertTrue(f { $0.savedView = .review }.narrowsTickets)
        XCTAssertFalse(f { $0.search = "  " }.hasActiveFilters)
        XCTAssertEqual(f { $0.providers = [.github]; $0.statuses = [.done, .todo] }.activeTokenCount, 3)
    }
}
