import CoreDomain
import XCTest
@testable import ToolGitLab

/// Ports of test/domain/gitlab_board_test.dart, test/unit/gitlab_usecases_test.dart,
/// test/unit/gitlab_project_tree_test.dart. (Board filtering is the shared engine's job; the builders take
/// pre-filtered tickets.)
final class GitLabDomainTests: XCTestCase {
    private func mr(_ id: String, _ providerStatus: String, priority: Priority = .medium) -> Ticket {
        Fixtures.ticket(type: "MergeRequest", key: id, status: .review, providerStatus: providerStatus, priority: priority, id: id)
    }
    private func issue(_ id: String, _ providerStatus: String, status: UnifiedStatus = .todo) -> Ticket {
        Fixtures.ticket(type: "Issue", key: id, status: status, providerStatus: providerStatus, id: id)
    }

    // MARK: boards

    func testMrBoardGroupsByRawStatus() {
        let board = BuildGitLabMrBoard()([mr("d", "draft"), mr("r", "opened"), mr("m", "merged"), mr("c", "closed")])
        XCTAssertEqual(board.column(.draft).tickets.map(\.id), ["d"])
        XCTAssertEqual(board.column(.review).tickets.map(\.id), ["r"])
        XCTAssertEqual(board.column(.merged).tickets.map(\.id), ["m"])
        XCTAssertEqual(board.column(.closed).tickets.map(\.id), ["c"])
        XCTAssertEqual(board.total, 4)
        XCTAssertEqual(board.columns.map(\.column), [.draft, .review, .merged, .closed])
    }

    func testMrBoardSortsByPriorityThenUpdated() {
        let old = Date(timeIntervalSince1970: 100), new = Date(timeIntervalSince1970: 200)
        var a = mr("lo", "opened", priority: .low); a.updatedAt = new
        var b = mr("hi", "opened", priority: .urgent); b.updatedAt = old
        var c = mr("hi2", "opened", priority: .urgent); c.updatedAt = new
        let board = BuildGitLabMrBoard()([a, b, c])
        XCTAssertEqual(board.column(.review).tickets.map(\.id), ["hi2", "hi", "lo"])
    }

    /// The board's Sort button (test/domain/compare_tickets_test.dart): every column follows the session's sort.
    func testColumnsFollowTheBoardSort() {
        var a = mr("a", "opened", priority: .urgent); a.title = "zeta"
        var b = mr("b", "opened", priority: .low); b.title = "Alpha"
        XCTAssertEqual(BuildGitLabMrBoard()([a, b]).column(.review).tickets.map(\.id), ["a", "b"])
        XCTAssertEqual(BuildGitLabMrBoard(sort: TicketSort(.title))([a, b]).column(.review).tickets.map(\.id), ["b", "a"])
        XCTAssertEqual(BuildGitLabMrBoard(sort: TicketSort(.priority, descending: true))([a, b]).column(.review).tickets.map(\.id), ["b", "a"])
        var i1 = issue("i1", "opened"); i1.title = "beta"
        var i2 = issue("i2", "opened"); i2.title = "alpha"
        XCTAssertEqual(BuildGitLabIssueBoard(sort: TicketSort(.title))([i1, i2]).column(.open).tickets.map(\.id), ["i2", "i1"])
    }

    func testMrBoardExcludesIssues() {
        XCTAssertEqual(BuildGitLabMrBoard()([issue("i", "opened")]).total, 0)
    }

    func testIssueBoardGroupsIntoOpenInProgressClosed() {
        let board = BuildGitLabIssueBoard()([issue("o", "opened"), issue("p", "opened", status: .inprogress), issue("c", "closed", status: .done)])
        XCTAssertEqual(board.column(.open).tickets.map(\.id), ["o"])
        XCTAssertEqual(board.column(.inProgress).tickets.map(\.id), ["p"])
        XCTAssertEqual(board.column(.closed).tickets.map(\.id), ["c"])
    }

    func testIssueBoardExcludesMergeRequests() {
        XCTAssertEqual(BuildGitLabIssueBoard()([mr("m", "opened")]).total, 0)
    }

    // MARK: metrics

    func testMetricsCountProjectsAndOnlyOpenMrsForAccount() {
        let tickets = [
            Fixtures.ticket(type: "MergeRequest", status: .inprogress, id: "1"),
            Fixtures.ticket(type: "Issue", status: .todo, id: "2"),
            Fixtures.ticket(type: "MergeRequest", status: .done, id: "3"),
            Fixtures.ticket(type: "MergeRequest", status: .inprogress, id: "4", accountId: "other-acc"),
        ]
        let m = ComputeGitLabMetrics()(tickets: tickets, projectCount: 5, accountId: "gl-a")
        XCTAssertEqual(m, GitLabMetrics(primaryCount: 5, secondaryCount: 1))
    }

    // MARK: project tree

    func testProjectTreeBuildsMultiLevelHierarchy() {
        func p(_ id: String, _ name: String) -> ProviderProject { ProviderProject(id: id, name: name, accountId: "acc1") }
        let tree = GitLabProjectTree.build([
            p("1", "icom / Server / storage"), p("2", "icom / Server / Subscription"), p("3", "icom / Server / payment"),
            p("4", "icom / Server / socialfi / post"), p("5", "icom / Server / socialfi / feed"),
            p("6", "other-group / tool"), p("7", "standalone-project"),
        ])
        XCTAssertEqual(tree.rootGroups.count, 2)
        XCTAssertEqual(tree.rootGroups[0].name, "icom")
        XCTAssertEqual(tree.rootGroups[0].fullPath, "icom")
        XCTAssertEqual(tree.rootGroups[1].name, "other-group")
        XCTAssertEqual(tree.rootProjects.map(\.name), ["standalone-project"])

        let icom = tree.rootGroups[0]
        XCTAssertEqual(icom.subgroups.count, 1)
        let server = icom.subgroups[0]
        XCTAssertEqual(server.name, "Server")
        XCTAssertEqual(server.fullPath, "icom/Server")
        XCTAssertEqual(server.projects.map(gitlabShortProjectName), ["payment", "storage", "Subscription"])
        XCTAssertEqual(server.subgroups.count, 1)
        let socialfi = server.subgroups[0]
        XCTAssertEqual(socialfi.fullPath, "icom/Server/socialfi")
        XCTAssertEqual(socialfi.projects.map(gitlabShortProjectName), ["feed", "post"])
        XCTAssertEqual(icom.totalProjectCount, 5)
        XCTAssertEqual(server.totalProjectCount, 5)
        XCTAssertEqual(socialfi.totalProjectCount, 2)
    }

    func testProjectTreeEmpty() {
        let tree = GitLabProjectTree.build([])
        XCTAssertTrue(tree.rootGroups.isEmpty)
        XCTAssertTrue(tree.rootProjects.isEmpty)
    }

    // MARK: use cases (ports of test/domain/gitlab_mr_usecases_test.dart)

    func testUseCasesDelegateOneCommandEach() async {
        let svc = RecordingMrService()
        let t = Fixtures.ticket(type: "MergeRequest")
        _ = await PostGitLabMrComment(svc)(t, body: "Looks good")
        _ = await CloseGitLabMr(svc)(t)
        _ = await ReopenGitLabMr(svc)(t)
        _ = await ApproveGitLabMr(svc)(t)
        _ = await UnapproveGitLabMr(svc)(t)
        _ = await RebaseGitLabMr(svc)(t)
        _ = await MergeGitLabMr(svc)(t)
        _ = await MergeGitLabMr(svc)(t, squash: true, removeSourceBranch: true)
        _ = await SetGitLabMrDraft(svc)(t, draft: false)
        XCTAssertEqual(svc.calls, ["comment:Looks good", "close", "reopen", "approve", "unapprove", "rebase", "merge:nil,nil",
                                   "merge:true,true", "draft:false"])
    }

    func testPriorityLabelDetector() {
        XCTAssertEqual(gitLabPriorityFromLabels(["x", "priority::critical"]), .urgent)
        XCTAssertEqual(gitLabPriorityFromLabels(["Priority::4"]), .low)
        XCTAssertNil(gitLabPriorityFromLabels(["priority::weird"]))
    }

    func testSyntheticLabelsFormat() {
        XCTAssertEqual(GitLabSyntheticLabels.project("12"), "gitlab-project:12")
        XCTAssertEqual(GitLabSyntheticLabels.mine("acc"), "gitlab-mine:acc")
    }

    func testCountDiffLinesIgnoresFileHeaders() {
        XCTAssertEqual(countDiffLines("--- a\n+++ b\n+x\n-y\n z").additions, 1)
        XCTAssertEqual(countDiffLines("--- a\n+++ b\n+x\n-y\n z").deletions, 1)
        XCTAssertEqual(countDiffLines(nil).additions, 0)
    }
}

/// Records which service command each use case issues.
final class RecordingMrService: GitLabMrService, @unchecked Sendable {
    private(set) var calls: [String] = []
    private func rec(_ s: String) -> Outcome<Void> { calls.append(s); return .success(()) }
    func postComment(_ t: Ticket, body: String) async -> Outcome<Void> { rec("comment:\(body)") }
    func closeGitLabItem(_ t: Ticket) async -> Outcome<Void> { rec("close") }
    func reopenGitLabItem(_ t: Ticket) async -> Outcome<Void> { rec("reopen") }
    func approveGitLabMr(_ t: Ticket) async -> Outcome<Void> { rec("approve") }
    func unapproveGitLabMr(_ t: Ticket) async -> Outcome<Void> { rec("unapprove") }
    func mergeGitLabMr(_ t: Ticket, squash: Bool?, removeSourceBranch: Bool?) async -> Outcome<Void> {
        rec("merge:\(squash.map(String.init) ?? "nil"),\(removeSourceBranch.map(String.init) ?? "nil")")
    }
    func setGitLabMrDraft(_ t: Ticket, draft: Bool) async -> Outcome<Void> { rec("draft:\(draft)") }
    func rebaseGitLabMr(_ t: Ticket) async -> Outcome<Void> { rec("rebase") }
    func listUsers(_ t: Ticket) async -> Outcome<[ProviderUser]> { .success([]) }
    func assignTicket(_ t: Ticket, assignee: String, comment: String?) async -> Outcome<Void> { rec("assign") }
    func setReviewers(_ t: Ticket, logins: [String]) async -> Outcome<Void> { rec("reviewers") }
    func listGitLabLabels(_ t: Ticket) async -> Outcome<[ProviderLabelOption]> { .success([]) }
    func setGitLabLabels(_ t: Ticket, labels: [String]) async -> Outcome<Void> { rec("labels") }
    func listGitLabMilestones(_ t: Ticket) async -> Outcome<[ProviderMilestoneOption]> { .success([]) }
    func setGitLabMilestone(_ t: Ticket, milestoneId: Int?) async -> Outcome<Void> { rec("milestone") }
    func updateGitLabTimeTracking(_ t: Ticket, estimate: String?, spent: String?, resetEstimate: Bool, resetSpent: Bool) async -> Outcome<Void> { rec("time") }
    func fetchTicketImage(_ t: Ticket, url: String) async -> Data? { nil }
    func listMergeRequestCommits(_ t: Ticket) async -> Outcome<[RepoCommit]> { .success([]) }
    func listMergeRequestChanges(_ t: Ticket) async -> Outcome<[RepoFileChange]> { .success([]) }
    func syncGitLabProjectItems(accountId: String, projectId: String, mergeRequests: Bool) async -> Outcome<[String]> { .success([]) }
    func syncGitLabMine(accountId: String) async -> Outcome<[String]> { .success([]) }
    func gitlabServerVersion(accountId: String) async -> String? { nil }
    func listProjects(accountId: String) async -> Outcome<[ProviderProject]> { .success([]) }
}
