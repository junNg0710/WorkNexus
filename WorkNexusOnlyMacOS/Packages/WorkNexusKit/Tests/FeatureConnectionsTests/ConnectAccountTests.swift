import CoreDomain
import XCTest
@testable import FeatureConnections

// MARK: doubles

private struct StubAdapter: ProviderAdapter {
    let providerType: ProviderType
    let check: Outcome<ConnectionCheck>
    func testConnection() async -> Outcome<ConnectionCheck> { check }
    func listAssignedTickets(sinceCursor: String?) async -> Outcome<TicketPage> { .success(TicketPage(tickets: [])) }
    func getTicket(_ ticket: Ticket) async -> Outcome<Ticket> { .success(ticket) }
    func listComments(_ ticket: Ticket) async -> Outcome<[Comment]> { .success([]) }
    func postComment(_ ticket: Ticket, body: String) async -> Outcome<Comment> { .failure(.unexpected("n/a")) }
    func listActivity(_ ticket: Ticket) async -> Outcome<[ActivityEvent]> { .success([]) }
    func assignTicket(_ ticket: Ticket, assignee: String, comment: String?, left: Double?) async -> Outcome<Bool> { .success(true) }
}

private final class StubRegistry: ProviderAdapterRegistry, @unchecked Sendable {
    var check: Outcome<ConnectionCheck>
    var probed: [(Account, String)] = []
    init(_ check: Outcome<ConnectionCheck>) { self.check = check }
    func createAdapter(account: Account, secret: String) -> ProviderAdapter? {
        probed.append((account, secret))
        return StubAdapter(providerType: account.providerType, check: check)
    }
}

private final class MemoryCredentials: CredentialStore, @unchecked Sendable {
    var store: [String: String] = [:]
    func read(_ key: String) async -> String? { store[key] }
    func write(_ key: String, value: String) async -> Outcome<Void> { store[key] = value; return .success(()) }
    func delete(_ key: String) async -> Outcome<Void> { store[key] = nil; return .success(()) }
}

private final class MemoryConnections: ConnectionRepository, @unchecked Sendable {
    var accounts: [Account] = [], workspaces: [Workspace] = []
    func addAccount(_ account: Account) async -> Outcome<Void> { accounts.append(account); return .success(()) }
    func removeAccount(id: String) async -> Outcome<Void> { .success(()) }
    func addWorkspace(_ workspace: Workspace) async -> Outcome<Void> { workspaces.append(workspace); return .success(()) }
    func updateWorkspace(_ workspace: Workspace) async -> Outcome<Void> { .success(()) }
    func deleteWorkspace(id: String) async -> Outcome<[String]> { .success([]) }
}

private final class StubSync: AccountSyncService, @unchecked Sendable {
    var result: Outcome<Void> = .success(())
    var synced: [String] = []
    func sync(accountId: String) async -> Outcome<Void> { synced.append(accountId); return result }
    func adapter(for account: Account) async -> ProviderAdapter? { nil }
}

// MARK: tests (connection_controllers.dart flows)

final class ConnectAccountTests: XCTestCase {
    private var registry: StubRegistry!
    private var creds: MemoryCredentials!
    private var repo: MemoryConnections!
    private var sync: StubSync!

    private func make(_ check: Outcome<ConnectionCheck>) -> ConnectAccount {
        registry = StubRegistry(check); creds = MemoryCredentials(); repo = MemoryConnections(); sync = StubSync()
        return ConnectAccount(adapters: registry, credentials: creds, connections: repo, sync: sync)
    }

    func testZenTaoStoresResolvedRootAndKeychainSecret() async {
        let connect = make(.success(ConnectionCheck(ok: true, baseUrl: "https://zentao.example.com/zentao")))
        let r = await connect(ConnectRequest(provider: .zentao, baseUrl: " https://zentao.example.com ", username: " Jun.Ng ", secret: "pw", workspaceId: "ws1"))
        guard case .added(let account) = r else { return XCTFail("\(r)") }
        XCTAssertEqual(account.id, "zt-jun-ng-5c5ed5b1")
        XCTAssertEqual(account.handle, "Jun.Ng")
        XCTAssertEqual(account.baseUrl, "https://zentao.example.com/zentao")
        XCTAssertEqual(account.credentialsRef, "secret:zt-jun-ng-5c5ed5b1")
        XCTAssertEqual(creds.store["secret:zt-jun-ng-5c5ed5b1"], "pw")
        XCTAssertEqual(repo.accounts, [account])
        XCTAssertEqual(sync.synced, ["zt-jun-ng-5c5ed5b1"])
        XCTAssertEqual(registry.probed.first?.0.baseUrl, "https://zentao.example.com")
        XCTAssertEqual(registry.probed.first?.0.id, "zentao-probe")
    }

    func testGitLabTakesHandleFromTokenAndHashesTypedUrl() async {
        let connect = make(.success(ConnectionCheck(ok: true, account: "jun")))
        let r = await connect(ConnectRequest(provider: .gitlab, baseUrl: "https://gitlab.com", secret: "glpat-x", workspaceId: "ws1"))
        XCTAssertEqual(r, .added(Account(id: "gl-jun-5607919d", workspaceId: "ws1", providerType: .gitlab, handle: "jun",
                                         baseUrl: "https://gitlab.com", credentialsRef: "secret:gl-jun-5607919d")))
    }

    func testGitHubWithoutAccountFallsBackToProviderName() async {
        let connect = make(.success(ConnectionCheck(ok: true, account: "")))
        let r = await connect(ConnectRequest(provider: .github, baseUrl: "https://github.com", secret: "ghp_x", workspaceId: "ws1"))
        guard case .added(let a) = r else { return XCTFail("\(r)") }
        XCTAssertEqual(a.handle, "github")
        XCTAssertTrue(a.id.hasPrefix("gh-github-"))
    }

    func testNewWorkspaceIsCreatedFirstWithDerivedIdBadgeAndColor() async {
        let connect = make(.success(ConnectionCheck(ok: true, account: "jun")))
        let r = await connect(ConnectRequest(provider: .github, baseUrl: "https://github.com", secret: "t", newWorkspaceName: " Company C "))
        XCTAssertEqual(repo.workspaces, [Workspace(id: "ws-company-c-233c3540", name: "Company C", shortCode: "CC",
                                                   colorValue: ConnectionIdentity.palette[2])])
        XCTAssertEqual(r.accountAdded, true)
        XCTAssertEqual(repo.accounts.first?.workspaceId, "ws-company-c-233c3540")
    }

    func testValidation() async {
        let connect = make(.success(ConnectionCheck(ok: true)))
        let zt = await connect(ConnectRequest(provider: .zentao, baseUrl: "https://x", username: "", secret: "pw", workspaceId: "w"))
        XCTAssertEqual(zt, .failed(.allFieldsRequired))
        let gh = await connect(ConnectRequest(provider: .github, baseUrl: "https://github.com", secret: "  ", workspaceId: "w"))
        XCTAssertEqual(gh, .failed(.allFieldsRequired))
        let noWs = await connect(ConnectRequest(provider: .github, baseUrl: "https://github.com", secret: "t"))
        XCTAssertEqual(noWs, .failed(.noWorkspace))
        XCTAssertTrue(registry.probed.isEmpty)
        XCTAssertTrue(repo.accounts.isEmpty)
    }

    func testRejectedConnectionStoresNothing() async {
        var connect = make(.failure(.auth("bad password")))
        var r = await connect(ConnectRequest(provider: .zentao, baseUrl: "https://x", username: "u", secret: "pw", workspaceId: "w"))
        XCTAssertEqual(r, .failed(.rejected("bad password")))
        XCTAssertTrue(creds.store.isEmpty); XCTAssertTrue(repo.accounts.isEmpty); XCTAssertTrue(sync.synced.isEmpty)

        connect = make(.success(ConnectionCheck(ok: false, error: "Wrong token")))
        r = await connect(ConnectRequest(provider: .gitlab, baseUrl: "https://gitlab.com", secret: "t", workspaceId: "w"))
        XCTAssertEqual(r, .failed(.rejected("Wrong token")))
        connect = make(.success(ConnectionCheck(ok: false)))
        r = await connect(ConnectRequest(provider: .gitlab, baseUrl: "https://gitlab.com", secret: "t", workspaceId: "w"))
        XCTAssertEqual(r, .failed(.connectionFailed))
    }

    func testFailedFirstSyncKeepsTheAccount() async {
        let connect = make(.success(ConnectionCheck(ok: true, account: "jun")))
        sync.result = .failure(.network("offline"))
        let r = await connect(ConnectRequest(provider: .gitlab, baseUrl: "https://gitlab.com", secret: "t", workspaceId: "w"))
        guard case .addedButSyncFailed(let account, let message) = r else { return XCTFail("\(r)") }
        XCTAssertEqual(message, "offline")
        XCTAssertEqual(repo.accounts, [account])
        XCTAssertTrue(r.accountAdded)
    }

    func testJiraIsDisabled() async {
        let connect = make(.success(ConnectionCheck(ok: true)))
        let r = await connect(ConnectRequest(provider: .jira, baseUrl: "https://x", secret: "t", workspaceId: "w"))
        XCTAssertEqual(r, .failed(.connectionFailed))
    }

    func testAfterAddHookRunsBeforeSync() async {
        let hooked = HookBox()
        registry = StubRegistry(.success(ConnectionCheck(ok: true, baseUrl: "https://z/zentao")))
        creds = MemoryCredentials(); repo = MemoryConnections(); sync = StubSync()
        let connect = ConnectAccount(adapters: registry, credentials: creds, connections: repo, sync: sync,
                                     afterAdd: { await hooked.add($0.id) })
        _ = await connect(ConnectRequest(provider: .zentao, baseUrl: "https://z", username: "u", secret: "p", workspaceId: "w"))
        let ids = await hooked.ids
        XCTAssertEqual(ids.count, 1)
    }
}

private actor HookBox {
    var ids: [String] = []
    func add(_ id: String) { ids.append(id) }
}
