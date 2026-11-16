import CoreDomain
import XCTest
@testable import ToolGitLab

/// Optimistic-action behaviour of `GitLabMrServiceImpl` (port of the `_gitlabAction` contract in
/// gitlab_mr_service_impl.dart), with the local DB and detail refresh faked at the interface boundary.
final class GitLabMrServiceTests: XCTestCase {
    private let net = StubNetwork.shared
    private let t = Fixtures.ticket(type: "MergeRequest")

    override func setUp() { net.reset() }

    private func service(adapter: GitLabMrAdapter?, repo: FakeTicketRepo, detail: FakeDetail = FakeDetail(),
                         status: FakeSyncStatus? = nil, account: Account? = Account(id: "gl-a", workspaceId: "w", providerType: .gitlab, handle: "me")) -> GitLabMrServiceImpl {
        GitLabMrServiceImpl(GitLabMrServiceDependencies(
            tickets: repo, ticketDetail: detail, syncStatus: status,
            adapter: { _ in adapter }, account: { _ in account }))
    }

    func testMergeWritesOptimisticRowThenRefreshesDetail() async {
        let repo = FakeTicketRepo(), detail = FakeDetail()
        let res = await service(adapter: Fixtures.adapter(), repo: repo, detail: detail).mergeGitLabMr(t, squash: nil, removeSourceBranch: nil)
        XCTAssertNotNil(res.value)
        XCTAssertEqual(repo.writes.count, 1)
        XCTAssertEqual(repo.writes[0].status, .done)
        XCTAssertEqual(repo.writes[0].providerStatus, "merged")
        XCTAssertEqual(detail.refreshed, [t.id])
    }

    func testFailureRollsTheTicketBack() async {
        net.reset { _ in .json("{}", status: 403) }
        let repo = FakeTicketRepo(), detail = FakeDetail()
        let res = await service(adapter: Fixtures.adapter(), repo: repo, detail: detail).approveGitLabMr(t)
        XCTAssertEqual(res.failure, .auth("GitLab authentication failed"))
        XCTAssertEqual(repo.writes, [t, t])    // optimistic (unchanged for approve) + rollback
        XCTAssertTrue(detail.refreshed.isEmpty)
    }

    func testCloseFailureRestoresOriginalStatus() async {
        net.reset { _ in .json("{}", status: 500) }
        let repo = FakeTicketRepo()
        _ = await service(adapter: Fixtures.adapter(), repo: repo).closeGitLabItem(t)
        XCTAssertEqual(repo.writes.first?.providerStatus, "closed")
        XCTAssertEqual(repo.writes.last, t)
    }

    func testMissingCredentialsRollsBack() async {
        let repo = FakeTicketRepo()
        let res = await service(adapter: nil, repo: repo).setGitLabMrDraft(t, draft: true)
        XCTAssertEqual(res.failure, .auth("No stored credentials for this account"))
        XCTAssertEqual(repo.writes.first?.providerStatus, "draft")
        XCTAssertEqual(repo.writes.last, t)
    }

    func testSyncProjectItemsTagsTicketsAndReportsStatus() async {
        net.reset { _ in .json(#"[{"id":9,"iid":7,"project_id":3,"state":"opened"}]"#) }
        let repo = FakeTicketRepo(), status = FakeSyncStatus()
        let res = await service(adapter: Fixtures.adapter(), repo: repo, status: status)
            .syncGitLabProjectItems(accountId: "gl-a", projectId: "12", mergeRequests: true)
        XCTAssertEqual(res.value, ["gl-a:mr:9"])
        XCTAssertEqual(repo.writes.first?.labels, ["gitlab-project:12"])
        XCTAssertEqual(status.reports.first, .syncing)
        guard case .idle? = status.reports.last else { return XCTFail("expected idle") }
    }

    func testSyncReportsAuthExpiredOnUnauthorized() async {
        net.reset { _ in .json("{}", status: 401) }
        let status = FakeSyncStatus()
        _ = await service(adapter: Fixtures.adapter(), repo: FakeTicketRepo(), status: status).syncGitLabMine(accountId: "gl-a")
        XCTAssertEqual(status.reports.last, .authExpired)
    }

    func testSyncFailsWhenAccountMissing() async {
        let res = await service(adapter: Fixtures.adapter(), repo: FakeTicketRepo(), account: nil)
            .syncGitLabMine(accountId: "gl-a")
        XCTAssertEqual(res.failure, .auth("GitLab account not found"))
    }

    func testFetchTicketImageUsesProjectFromEntity() async {
        net.reset { _ in .image([1, 2, 3]) }
        var ticket = t
        ticket.providerEntity = .gitlabItem(GitLabItemEntity(projectPath: "group/web", projectId: 42))
        let bytes = await service(adapter: Fixtures.adapter(), repo: FakeTicketRepo()).fetchTicketImage(ticket, url: "/uploads/abc/x.png")
        XCTAssertEqual(bytes, Data([1, 2, 3]))
        XCTAssertEqual(net.requests.first?.encodedPath, "/api/v4/projects/42/uploads/abc/x.png")
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
