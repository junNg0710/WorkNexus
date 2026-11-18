import CoreDomain
import XCTest
@testable import ToolGitHub

/// Ports of test/domain/github_board_test.dart, test/domain/github_pr_usecases_test.dart,
/// test/unit/github_usecases_test.dart.
final class GitHubDomainTests: XCTestCase {
    private func pr(_ id: String, _ providerStatus: String, priority: Priority = .medium) -> Ticket {
        Fixtures.ticket(type: "PullRequest", key: id, status: .review, providerStatus: providerStatus, priority: priority, id: id)
    }
    private func issue(_ id: String, _ providerStatus: String, status: UnifiedStatus = .todo) -> Ticket {
        Fixtures.ticket(type: "Issue", key: id, status: status, providerStatus: providerStatus, id: id)
    }

    func testPrBoardGroupsByRawStatus() {
        let board = BuildGitHubPrBoard()([pr("d", "draft"), pr("r", "open"), pr("m", "merged"), pr("c", "closed")])
        XCTAssertEqual(board.column(.draft).tickets.map(\.id), ["d"])
        XCTAssertEqual(board.column(.review).tickets.map(\.id), ["r"])
        XCTAssertEqual(board.column(.merged).tickets.map(\.id), ["m"])
        XCTAssertEqual(board.column(.closed).tickets.map(\.id), ["c"])
        XCTAssertEqual(board.total, 4)
        XCTAssertEqual(board.columns.map(\.column), [.draft, .review, .merged, .closed])
    }

    func testPrBoardSortsByPriorityThenUpdated() {
        var a = pr("lo", "open", priority: .low); a.updatedAt = Date(timeIntervalSince1970: 300)
        var b = pr("hi-old", "open", priority: .urgent); b.updatedAt = Date(timeIntervalSince1970: 100)
        var c = pr("hi-new", "open", priority: .urgent); c.updatedAt = Date(timeIntervalSince1970: 200)
        XCTAssertEqual(BuildGitHubPrBoard()([a, b, c]).column(.review).tickets.map(\.id), ["hi-new", "hi-old", "lo"])
    }

    /// The board's Sort button (test/domain/compare_tickets_test.dart): every column follows the session's sort.
    func testColumnsFollowTheBoardSort() {
        var a = pr("a", "open", priority: .urgent); a.title = "zeta"
        var b = pr("b", "open", priority: .low); b.title = "Alpha"
        XCTAssertEqual(BuildGitHubPrBoard()([a, b]).column(.review).tickets.map(\.id), ["a", "b"])
        XCTAssertEqual(BuildGitHubPrBoard(sort: TicketSort(.title))([a, b]).column(.review).tickets.map(\.id), ["b", "a"])
        XCTAssertEqual(BuildGitHubPrBoard(sort: TicketSort(.priority, descending: true))([a, b]).column(.review).tickets.map(\.id), ["b", "a"])
        var i1 = issue("i1", "open"); i1.title = "beta"
        var i2 = issue("i2", "open"); i2.title = "alpha"
        XCTAssertEqual(BuildGitHubIssueBoard(sort: TicketSort(.title))([i1, i2]).column(.open).tickets.map(\.id), ["i2", "i1"])
    }

    func testPrBoardExcludesIssuesAndOtherProviders() {
        XCTAssertEqual(BuildGitHubPrBoard()([issue("i", "open")]).total, 0)
        var gl = pr("x", "open"); gl.providerType = .gitlab
        XCTAssertEqual(BuildGitHubPrBoard()([gl]).total, 0)
    }

    func testIssueBoardGroupsIntoOpenInProgressClosed() {
        let board = BuildGitHubIssueBoard()([issue("o", "open"), issue("p", "open", status: .inprogress), issue("c", "closed", status: .done)])
        XCTAssertEqual(board.column(.open).tickets.map(\.id), ["o"])
        XCTAssertEqual(board.column(.inProgress).tickets.map(\.id), ["p"])
        XCTAssertEqual(board.column(.closed).tickets.map(\.id), ["c"])
        XCTAssertEqual(BuildGitHubIssueBoard()([pr("m", "open")]).total, 0)
    }

    func testMetricsCountOpenPullsAndIssuesForAccount() {
        let tickets = [
            Fixtures.ticket(type: "PullRequest", status: .review, id: "1"),
            Fixtures.ticket(type: "PullRequest", status: .done, id: "2"),
            Fixtures.ticket(type: "Issue", status: .todo, id: "3"),
            Fixtures.ticket(type: "Issue", status: .todo, id: "4"),
            Fixtures.ticket(type: "Issue", status: .todo, id: "5", accountId: "other"),
        ]
        XCTAssertEqual(ComputeGitHubMetrics()(tickets: tickets, accountId: "gh-a"), GitHubMetrics(primaryCount: 1, secondaryCount: 2))
    }

    func testUseCasesDelegateOneCommandEach() async {
        let svc = RecordingPrService()
        let t = Fixtures.ticket(type: "PullRequest")
        _ = await PostGitHubComment(svc)(t, body: "Looks good")
        _ = await CloseGitHubItem(svc)(t)
        _ = await ReopenGitHubItem(svc)(t)
        _ = await MergeGitHubPr(svc)(t)
        _ = await UpdateGitHubPrBranch(svc)(t)
        XCTAssertEqual(svc.calls, ["comment:Looks good", "close", "reopen", "merge", "update-branch"])
    }

    func testSyntheticLabelsFormat() {
        XCTAssertEqual(GitHubSyntheticLabels.repo("octo/web"), "github-repo:octo/web")
        XCTAssertEqual(GitHubSyntheticLabels.mine("acc"), "github-mine:acc")
    }

    func testCountDiffLinesIgnoresFileHeaders() {
        let c = countDiffLines("--- a\n+++ b\n+x\n-y\n z")
        XCTAssertEqual(c.additions, 1)
        XCTAssertEqual(c.deletions, 1)
    }
}

/// Records which service command each use case issues.
final class RecordingPrService: GitHubPrService, @unchecked Sendable {
    private(set) var calls: [String] = []
    private func rec(_ s: String) -> Outcome<Void> { calls.append(s); return .success(()) }
    func postComment(_ t: Ticket, body: String) async -> Outcome<Void> { rec("comment:\(body)") }
    func closeGitHubItem(_ t: Ticket) async -> Outcome<Void> { rec("close") }
    func reopenGitHubItem(_ t: Ticket) async -> Outcome<Void> { rec("reopen") }
    func mergeGitHubPr(_ t: Ticket) async -> Outcome<Void> { rec("merge") }
    func updateGitHubPrBranch(_ t: Ticket) async -> Outcome<Void> { rec("update-branch") }
    func setReviewers(_ t: Ticket, logins: [String]) async -> Outcome<Void> { rec("reviewers") }
    func assignTicket(_ t: Ticket, assignee: String, comment: String?) async -> Outcome<Void> { rec("assign") }
    func listUsers(_ t: Ticket) async -> Outcome<[ProviderUser]> { .success([]) }
    func fetchTicketImage(_ t: Ticket, url: String) async -> Data? { nil }
    func listPullCommits(_ t: Ticket) async -> Outcome<[RepoCommit]> { .success([]) }
    func listPullFiles(_ t: Ticket) async -> Outcome<[RepoFileChange]> { .success([]) }
    func syncGitHubRepoItems(accountId: String, repoId: String, pullRequests: Bool) async -> Outcome<[String]> { .success([]) }
    func syncGitHubMine(accountId: String) async -> Outcome<[String]> { .success([]) }
    func listProjects(accountId: String) async -> Outcome<[ProviderProject]> { .success([]) }
}
