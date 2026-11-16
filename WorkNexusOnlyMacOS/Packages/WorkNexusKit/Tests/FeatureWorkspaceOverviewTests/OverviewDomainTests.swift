import CoreDomain
import XCTest
@testable import FeatureWorkspaceOverview

/// Vectors of test/domain/{list_assigned_work,refresh_dashboard,build_work_queue,filter_my_work,group_my_work,
/// rank_dashboard_executions}_test.dart.
final class OverviewDomainTests: XCTestCase {
    private let zt = Account(id: "acc-zt", workspaceId: "ws-1", providerType: .zentao, handle: "thanh")
    private let gh1 = Account(id: "acc-gh-1", workspaceId: "ws-1", providerType: .github, handle: "octocat")
    private let gh2 = Account(id: "acc-gh-2", workspaceId: "ws-1", providerType: .github, handle: "mona")
    private let gl = Account(id: "acc-gl", workspaceId: "ws-1", providerType: .gitlab, handle: "tanuki")
    private let list = ListAssignedWork()
    private func date(_ y: Int, _ m: Int, _ d: Int, _ h: Int = 0) -> Date {
        Calendar.current.date(from: DateComponents(year: y, month: m, day: d, hour: h))!
    }
    private var now: Date { date(2026, 10, 14, 12) }

    // MARK: ListAssignedWork

    func testEmptyWithoutAccountsOrTickets() {
        XCTAssertTrue(list(tickets: [makeTicket("t1")], accounts: [], now: now).isEmpty)
        XCTAssertTrue(list(tickets: [], accounts: [zt], now: now).isEmpty)
    }

    func testSkipsNilAssignee() { XCTAssertTrue(list(tickets: [makeTicket("t1", assignee: nil)], accounts: [zt], now: now).isEmpty) }

    func testCaseInsensitiveAssigneeMatch() {
        let r = list(tickets: [makeTicket("t1", key: "10", title: "Task Alpha", assignee: "THANH"),
                               makeTicket("t2", key: "11", title: "Task Beta", assignee: "Thanh ")], accounts: [zt], now: now)
        XCTAssertEqual(r.count, 2)
        XCTAssertEqual(r[0].title, "Task Alpha"); XCTAssertEqual(r[0].reason, .assignee); XCTAssertEqual(r[0].displayKey, "TASK-10")
        XCTAssertEqual(r[1].title, "Task Beta")
    }

    func testExcludesFinishedItems() {
        let merged = makeTicket("t7", accountId: "acc-gh-1", provider: .github, assignee: "octocat", entity: .githubItem(GitHubItemEntity(merged: true)))
        let r = list(tickets: [makeTicket("t1"), makeTicket("t2", status: .done), makeTicket("t3", raw: "done"),
                               makeTicket("t4", raw: "closed"), makeTicket("t5", raw: "resolved"), makeTicket("t6", raw: "cancel"), merged],
                     accounts: [zt, gh1], now: now)
        XCTAssertEqual(r.map(\.ticketId), ["t1"])
    }

    func testReviewerReasonForPullAndMergeRequests() {
        let pr = makeTicket("gh-pr-1", accountId: "acc-gh-1", provider: .github, key: "42", type: "PullRequest", assignee: "someone_else",
                            entity: .githubItem(GitHubItemEntity(reviewers: ["OCTOCAT", "other_dev"])))
        let mr = makeTicket("gl-mr-1", accountId: "acc-gl", provider: .gitlab, key: "99", type: "MergeRequest", assignee: nil,
                            entity: .gitlabItem(GitLabItemEntity(reviewers: ["tanuki"])))
        let r = list(tickets: [pr, mr], accounts: [gh1, gl], now: now)
        XCTAssertEqual(r.count, 2)
        let g = r.first { $0.ticketId == "gh-pr-1" }!, l = r.first { $0.ticketId == "gl-mr-1" }!
        XCTAssertEqual(g.reason, .reviewer); XCTAssertEqual(g.displayKey, "#42")
        XCTAssertEqual(l.reason, .reviewer); XCTAssertEqual(l.displayKey, "!99")
    }

    func testAssigneeTakesPrecedenceOverReviewer() {
        let pr = makeTicket("both", accountId: "acc-gh-1", provider: .github, assignee: "octocat",
                            entity: .githubItem(GitHubItemEntity(reviewers: ["octocat"])))
        XCTAssertEqual(list(tickets: [pr], accounts: [gh1], now: now).first?.reason, .assignee)
    }

    func testMultipleAccountsOfOneProvider() {
        let r = list(tickets: [makeTicket("gh-1", accountId: "acc-gh-1", provider: .github, title: "Octocat work", assignee: "octocat"),
                               makeTicket("gh-2", accountId: "acc-gh-2", provider: .github, title: "Mona work", assignee: "mona"),
                               makeTicket("gh-3", accountId: "acc-gh-1", provider: .github, title: "Mona on octocat account", assignee: "mona")],
                     accounts: [gh1, gh2], now: now)
        XCTAssertEqual(Set(r.map { $0.title }), ["Octocat work", "Mona work"])
    }

    func testDisplayKeys() {
        let r = list(tickets: [makeTicket("1", key: "101", type: "Bug"), makeTicket("2", key: "102"), makeTicket("3", key: "103", type: "Story"),
                               makeTicket("4", accountId: "acc-gl", provider: .gitlab, key: "201", type: "MergeRequest", assignee: "tanuki"),
                               makeTicket("5", accountId: "acc-gl", provider: .gitlab, key: "202", type: "Issue", assignee: "tanuki"),
                               makeTicket("6", accountId: "acc-gh-1", provider: .github, key: "301", type: nil, assignee: "octocat")],
                     accounts: [zt, gl, gh1], now: now)
        func key(_ id: String) -> String? { r.first { $0.ticketId == id }?.displayKey }
        XCTAssertEqual(key("1"), "BUG-101"); XCTAssertEqual(key("2"), "TASK-102"); XCTAssertEqual(key("3"), "STORY-103")
        XCTAssertEqual(key("4"), "!201"); XCTAssertEqual(key("5"), "#202"); XCTAssertEqual(key("6"), "#301")
    }

    func testSortsOverdueThenDueAscendingThenUpdatedDescending() {
        let tickets = [
            makeTicket("no-due-2", title: "No Due Older", updatedAt: date(2026, 10, 13, 10)),
            makeTicket("upcoming-2", labels: ["deadline:2026-10-20"]),
            makeTicket("overdue-2", labels: ["deadline:2026-10-12"]),
            makeTicket("no-due-1", title: "No Due Recent", updatedAt: date(2026, 10, 14, 10)),
            makeTicket("overdue-1", labels: ["deadline:2026-10-10"]),
            makeTicket("upcoming-1", labels: ["due:2026-10-16"]),
        ]
        XCTAssertEqual(list(tickets: tickets, accounts: [zt], now: now).map(\.ticketId),
                       ["overdue-1", "overdue-2", "upcoming-1", "upcoming-2", "no-due-1", "no-due-2"])
    }

    func testZenTaoNoDeadlineIsNoDueDate() {
        let bug = makeTicket("bug", type: "Bug", entity: .zentaoBug(ZenTaoBugEntity(deadline: "0000-00-00")))
        XCTAssertNil(list(tickets: [bug], accounts: [zt], now: now).first?.due)
    }

    func testDateOnlyDueIsNotOverdueDuringThatDay() {
        let r = list(tickets: [makeTicket("today", labels: ["due:2026-10-14"])], accounts: [zt], now: now)
        XCTAssertGreaterThan(r.first!.due!, now)
    }

    func testGitHubReviewMatchedOnLogin() {
        let pr = makeTicket("pr", accountId: "acc-gh-1", provider: .github, type: "PullRequest", assignee: nil,
                            entity: .githubItem(GitHubItemEntity(reviewers: ["Octo Cat"], reviewerLogins: ["octocat"])))
        XCTAssertEqual(list(tickets: [pr], accounts: [gh1], now: now).first?.reason, .reviewer)
    }

    // MARK: BuildWorkQueue / GroupMyWork / FilterMyWork / RankDashboardExecutions

    private func t(_ id: String, _ status: UnifiedStatus, _ priority: Priority) -> Ticket {
        makeTicket(id, accountId: "a1", key: id, title: id, status: status, raw: "", priority: priority)
    }

    func testQueueSplitsInProgressFromNotStarted() {
        let q = BuildWorkQueue()([t("10", .todo, .medium), t("20", .inprogress, .low), t("5", .inbox, .urgent),
                                  t("30", .todo, .medium), t("40", .inprogress, .high)])
        XCTAssertEqual(q.inProgress.map(\.id), ["40", "20"])
        XCTAssertEqual(q.notStarted.map(\.id), ["5", "30", "10"])
        XCTAssertEqual(q.count, 5); XCTAssertFalse(q.isEmpty)
    }

    func testGroupsOrderedByWhatNeedsTheAssigneeFirst() {
        let groups = GroupMyWork()([t("1", .done, .medium), t("2", .review, .medium), t("3", .todo, .medium),
                                    t("4", .inprogress, .medium), t("5", .inbox, .medium), t("6", .blocked, .medium)])
        XCTAssertEqual(groups.map(\.status), [.inprogress, .todo, .inbox, .blocked, .review, .done])
    }

    func testGroupsSkipEmptySectionsAndSortUrgentThenNewest() {
        let groups = GroupMyWork()([t("10", .todo, .low), t("30", .todo, .low), t("5", .todo, .urgent)])
        XCTAssertEqual(groups.count, 1)
        XCTAssertEqual(groups[0].tickets.map(\.id), ["5", "30", "10"])
        XCTAssertTrue(GroupMyWork()([]).isEmpty)
    }

    private func mine(_ id: String, account: String = "a1", type: String = "Task", assignee: String? = "thanh",
                      status: UnifiedStatus = .todo, raw: String = "wait") -> Ticket {
        makeTicket("\(account):\(id)", accountId: account, key: id, type: type, title: id, assignee: assignee, status: status, raw: raw)
    }

    func testFilterMyWork() {
        let tickets = [mine("9"), mine("120"), mine("15", assignee: "Thanh "), mine("77", type: "Bug"), mine("50", assignee: "someone"),
                       mine("60", account: "a2"), mine("70", assignee: nil), mine("8", status: .done), mine("7", status: .review, raw: "done")]
        let f = FilterMyWork()
        XCTAssertEqual(f(tickets, accountId: "a1", userAccount: "thanh", kind: .task).map(\.externalKey), ["120", "15", "9", "8", "7"])
        XCTAssertEqual(f(tickets, accountId: "a1", userAccount: "thanh", kind: .task, openOnly: true).map(\.externalKey), ["120", "15", "9"])
        XCTAssertEqual(f(tickets, accountId: "a1", userAccount: "THANH", kind: .bug).map(\.externalKey), ["77"])
    }

    func testRankExecutions() {
        func e(_ id: String, _ status: String?, _ end: Date? = nil) -> ZenTaoDashboardExecution {
            ZenTaoDashboardExecution(id: id, name: id, status: status, end: end)
        }
        let ranked = RankDashboardExecutions()([e("waiting-soon", "wait", date(2026, 10, 18)), e("doing-late", "doing", date(2026, 12, 2)),
                                                 e("doing-undated", "doing"), e("doing-soon", "doing", date(2026, 10, 20)),
                                                 e("waiting-late", "wait", date(2026, 11, 30))])
        XCTAssertEqual(ranked.map(\.id), ["doing-soon", "doing-late", "doing-undated"])
        XCTAssertEqual(RankDashboardExecutions()([e("a", "wait"), e("b", "doing")], limit: 5).map(\.id), ["b", "a"])
    }

    // MARK: RefreshDashboard

    private func snapshot(_ at: Date) -> ZenTaoDashboard {
        ZenTaoDashboard(accountId: "a1", profile: ZenTaoDashboardProfile(account: "thanh", realname: "Thanh"), fetchedAt: at)
    }

    func testRefreshFetchesWhenNothingStored() async {
        let repo = FakeOverview()
        let r = await RefreshDashboard(repo, now: { Date(timeIntervalSince1970: 1_000_000) })("a1")
        XCTAssertNotNil(r.value); XCTAssertEqual(repo.refreshCalls, ["a1"])
    }

    func testRefreshKeepsYoungSnapshotAndFetchesOldOne() async {
        let at = Date(timeIntervalSince1970: 1_000_000)
        let repo = FakeOverview()
        repo.cached = snapshot(at.addingTimeInterval(-120))
        _ = await RefreshDashboard(repo, now: { at })("a1")
        XCTAssertTrue(repo.refreshCalls.isEmpty)
        repo.cached = snapshot(at.addingTimeInterval(-360))
        _ = await RefreshDashboard(repo, now: { at })("a1")
        XCTAssertEqual(repo.refreshCalls, ["a1"])
    }

    func testRefreshForceIgnoresStoredSnapshot() async {
        let at = Date(timeIntervalSince1970: 1_000_000)
        let repo = FakeOverview()
        repo.cached = snapshot(at)
        _ = await RefreshDashboard(repo, now: { at })("a1", force: true)
        XCTAssertEqual(repo.refreshCalls, ["a1"])
    }

    func testRefreshPassesFailureThrough() async {
        let repo = FakeOverview()
        repo.refreshResult = .failure(.auth("expired"))
        let r = await RefreshDashboard(repo)("a1")
        XCTAssertEqual(r.failure, .auth("expired"))
    }

    // MARK: SyncAssignedWork / OpenDashboardItem

    func testSyncRunsOncePerSessionAndSharesInFlight() async {
        let repo = FakeOverview()
        repo.syncDelay = .milliseconds(80)
        let sync = SyncAssignedWork(repo)
        async let a = sync("a1"); async let b = sync("a1")
        _ = await (a, b)
        XCTAssertEqual(repo.syncCalls, ["a1"])
        _ = await sync("a1")
        XCTAssertEqual(repo.syncCalls, ["a1"], "a finished session sync is not repeated")
        _ = await sync("a1", force: true)
        XCTAssertEqual(repo.syncCalls, ["a1", "a1"])
        let started = await sync.hasStarted("a1"), other = await sync.hasStarted("a2")
        XCTAssertTrue(started); XCTAssertFalse(other)
    }

    func testOpenDashboardItemResolvesTicketsButNotTodos() async {
        let repo = FakeOverview()
        let account = Account(id: "z", workspaceId: "w", providerType: .zentao, handle: "me", baseUrl: "https://zentao.example.com/zentao/")
        let open = OpenDashboardItem(repo)
        let ok = await open(account: account, kind: .bug, id: "12")
        XCTAssertEqual(ok.value, "ticket-1")
        XCTAssertEqual(repo.resolved, [["zentao.example.com", "bug", "12"]])
        let todo = await open(account: account, kind: .todo, id: "3")
        XCTAssertNotNil(todo.failure); XCTAssertEqual(repo.resolved.count, 1)
    }

    func testDashboardItemKindFromObjectType() {
        XCTAssertEqual(DashboardItemKind.fromObjectType(" Bug "), .bug)
        XCTAssertNil(DashboardItemKind.fromObjectType("project"))
        XCTAssertTrue(DashboardItemKind.story.isTicket); XCTAssertFalse(DashboardItemKind.todo.isTicket)
    }
}
