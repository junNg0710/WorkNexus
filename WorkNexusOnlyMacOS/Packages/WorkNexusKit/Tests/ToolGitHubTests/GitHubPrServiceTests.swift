import CoreDomain
import XCTest
@testable import ToolGitHub

/// Optimistic-action behaviour of `GitHubPrServiceImpl` (port of the `_githubAction` contract in
/// github_pr_service_impl.dart), with the local DB and detail refresh faked at the interface boundary.
final class GitHubPrServiceTests: XCTestCase {
    private let net = StubNetwork.shared
    private let t = Fixtures.ticket(type: "PullRequest")

    override func setUp() { net.reset() }

    private func service(adapter: GitHubPrAdapter?, repo: FakeTicketRepo, detail: FakeDetail = FakeDetail(),
                         status: FakeSyncStatus? = nil,
                         account: Account? = Account(id: "gh-a", workspaceId: "w", providerType: .github, handle: "me")) -> GitHubPrServiceImpl {
        GitHubPrServiceImpl(GitHubPrServiceDependencies(
            tickets: repo, ticketDetail: detail, syncStatus: status,
            adapter: { _ in adapter }, account: { _ in account }))
    }

    func testMergeWritesOptimisticRowThenRefreshesDetail() async {
        let repo = FakeTicketRepo(), detail = FakeDetail()
        let res = await service(adapter: Fixtures.adapter(), repo: repo, detail: detail).mergeGitHubPr(t)
        XCTAssertNotNil(res.value)
        XCTAssertEqual(repo.writes.count, 1)
        XCTAssertEqual(repo.writes[0].status, .done)
        XCTAssertEqual(repo.writes[0].providerStatus, "merged")
        XCTAssertEqual(detail.refreshed, [t.id])
    }

    func testFailureRollsTheTicketBack() async {
        net.reset { _ in .json("{}", status: 405) }
        let repo = FakeTicketRepo(), detail = FakeDetail()
        let res = await service(adapter: Fixtures.adapter(), repo: repo, detail: detail).mergeGitHubPr(t)
        XCTAssertNotNil(res.failure)
        XCTAssertEqual(repo.writes.last, t)
        XCTAssertEqual(repo.writes.first?.providerStatus, "merged")
        XCTAssertTrue(detail.refreshed.isEmpty)
    }

    func testReopenOptimisticStatusDependsOnKind() async {
        let repo = FakeTicketRepo()
        _ = await service(adapter: Fixtures.adapter(), repo: repo).reopenGitHubItem(t)
        XCTAssertEqual(repo.writes.first?.status, .review)
        let issueRepo = FakeTicketRepo()
        _ = await service(adapter: Fixtures.adapter(), repo: issueRepo).reopenGitHubItem(Fixtures.ticket(type: "Issue"))
        XCTAssertEqual(issueRepo.writes.first?.status, .todo)
        XCTAssertEqual(issueRepo.writes.first?.providerStatus, "open")
    }

    func testMissingCredentialsRollsBack() async {
        let repo = FakeTicketRepo()
        let res = await service(adapter: nil, repo: repo).closeGitHubItem(t)
        XCTAssertEqual(res.failure, .auth("No stored credentials for this account"))
        XCTAssertEqual(repo.writes.last, t)
    }

    func testSyncRepoItemsTagsTicketsWithRepoLabel() async {
        net.reset { _ in .json(#"[{"number":7,"state":"open"}]"#) }
        let repo = FakeTicketRepo(), status = FakeSyncStatus()
        let res = await service(adapter: Fixtures.adapter(), repo: repo, status: status)
            .syncGitHubRepoItems(accountId: "gh-a", repoId: "octo/web", pullRequests: true)
        XCTAssertEqual(res.value, ["gh-a:octo/web:pr:7"])
        XCTAssertEqual(repo.writes.first?.labels, ["github-repo:octo/web"])
        XCTAssertEqual(status.reports.first, .syncing)
    }

    func testSyncMineReportsOfflineOnNetworkFailure() async {
        net.reset { _ in .json("{}", status: 500) }
        let status = FakeSyncStatus()
        _ = await service(adapter: Fixtures.adapter(), repo: FakeTicketRepo(), status: status).syncGitHubMine(accountId: "gh-a")
        XCTAssertEqual(status.reports.last, .offline)
    }

    func testListUsersUsesRepoAssignees() async {
        net.reset { _ in .json(#"[{"login":"amy","name":"Amy"}]"#) }
        let res = await service(adapter: Fixtures.adapter(), repo: FakeTicketRepo()).listUsers(t)
        XCTAssertEqual(res.value?.map(\.account), ["amy"])
    }
}

final class FakeTicketRepo: TicketRepository, @unchecked Sendable {
    private let lock = NSLock()
    private var _writes: [Ticket] = []
    var writes: [Ticket] { lock.withLock { _writes } }
    func watchTickets() -> AsyncStream<[Ticket]> { AsyncStream { $0.finish() } }
    func ticket(id: String) async -> Outcome<Ticket?> { .success(nil) }
    func upsertTickets(_ tickets: [Ticket]) async -> Outcome<Void> { lock.withLock { _writes += tickets }; return .success(()) }
    func moveTicket(id: String, to status: UnifiedStatus) async -> Outcome<Void> { .success(()) }
}

final class FakeDetail: TicketDetailService, @unchecked Sendable {
    private let lock = NSLock()
    private var _refreshed: [String] = []
    var refreshed: [String] { lock.withLock { _refreshed } }
    func refresh(ticket: Ticket) async -> Outcome<Void> { lock.withLock { _refreshed.append(ticket.id) }; return .success(()) }
    func postComment(ticket: Ticket, body: String) async -> Outcome<Void> { .success(()) }
}

final class FakeSyncStatus: SyncStatusRepository, @unchecked Sendable {
    private let lock = NSLock()
    private var _reports: [AccountSyncStatus] = []
    var reports: [AccountSyncStatus] { lock.withLock { _reports } }
    func watch(accountId: String) -> AsyncStream<AccountSyncStatus> { AsyncStream { $0.finish() } }
    func status(accountId: String) async -> AccountSyncStatus { .idle(lastSyncedAt: nil) }
    func report(accountId: String, status: AccountSyncStatus) { lock.withLock { _reports.append(status) } }
}
