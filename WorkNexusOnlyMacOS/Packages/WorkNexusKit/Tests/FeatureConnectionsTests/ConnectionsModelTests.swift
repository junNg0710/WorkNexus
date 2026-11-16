import CoreDomain
import XCTest
@testable import FeatureConnections

@MainActor
final class ConnectionsModelTests: XCTestCase {
    private let ws = Workspace(id: "w1", name: "One", shortCode: "O", colorValue: 0xFF3B82F6)
    private let live = Account(id: "a1", workspaceId: "w1", providerType: .zentao, handle: "jun", baseUrl: "https://z/", credentialsRef: "secret:a1")

    private func make(sync: FakeSync = FakeSync(), tickets: FakeTickets = FakeTickets(), creds: FakeCredentials = FakeCredentials(),
                      connections: RecordingConnections = RecordingConnections(), cache: RecordingCache = RecordingCache()) -> ConnectionsModel {
        ConnectionsModel(workspaces: FakeWorkspaces(workspaces: [ws], accounts: [live]), tickets: tickets, credentials: creds, sync: sync,
                         adapters: NoAdapters(), connections: connections, cache: cache)
    }

    private func ticket(_ id: String, _ account: String) -> Ticket {
        Ticket(id: id, accountId: account, projectId: "p", providerType: .zentao, externalKey: id, title: "t", body: "", priority: .medium,
               status: .todo, providerStatus: "s", sourceHash: "h")
    }

    func testStartFollowsWorkspacesAndAccounts() async throws {
        let m = make()
        m.start()
        try await Task.sleep(for: .milliseconds(50))
        XCTAssertEqual(m.workspaces, [ws])
        XCTAssertEqual(m.accounts(in: "w1"), [live])
        XCTAssertEqual(m.accounts(in: "other"), [])
        XCTAssertEqual(m.workspace(id: "w1"), ws)
    }

    func testSyncReportsStoredTicketCountOfThatAccount() async {
        let t = FakeTickets(); t.tickets = [ticket("1", "a1"), ticket("2", "a1"), ticket("3", "zz")]
        let m = make(tickets: t)
        let report = await m.sync(live)
        XCTAssertEqual(report, .synced(count: 2))
        let s = FakeSync(); s.result = .failure(.network("offline"))
        let failed = await make(sync: s).sync(live)
        XCTAssertEqual(failed, .failed("offline"))
    }

    func testRemoveDeletesAccountAndItsSecret() async {
        let creds = FakeCredentials(); creds.store["secret:a1"] = "pw"
        let c = RecordingConnections()
        await make(creds: creds, connections: c).remove(live)
        XCTAssertEqual(c.removed, ["a1"])
        XCTAssertNil(creds.store["secret:a1"])
    }

    func testDeleteWorkspaceWipesEveryAccountSecret() async {
        let creds = FakeCredentials(); creds.store = ["secret:a1": "x", "secret:a2": "y", "secret:keep": "z"]
        let c = RecordingConnections(); c.refsOnDelete = ["secret:a1", "secret:a2"]
        await make(creds: creds, connections: c).deleteWorkspace(id: "w1")
        XCTAssertEqual(c.deleted, ["w1"])
        XCTAssertEqual(creds.store, ["secret:keep": "z"])
    }

    func testClearGoesThroughUseCase() async {
        let cache = RecordingCache()
        let m = make(cache: cache)
        _ = await m.clear([])
        XCTAssertTrue(cache.cleared.isEmpty)
        _ = await m.clear([.tickets])
        XCTAssertEqual(cache.cleared, [[.tickets]])
        cache.failure = .storage("disk")
        let failed = await m.clear([.chat])
        XCTAssertEqual(failed.failure, .storage("disk"))
    }

    func testAddConnectionModelStates() async {
        let ok = AddConnectionModel { _ in .added(Account(id: "x", workspaceId: "w", providerType: .github, handle: "h")) }
        let added = await ok.submit(ConnectRequest(provider: .github, baseUrl: "u", secret: "t", workspaceId: "w"))
        XCTAssertTrue(added); XCTAssertTrue(ok.done); XCTAssertNil(ok.error)
        let warn = AddConnectionModel { _ in .addedButSyncFailed(Account(id: "x", workspaceId: "w", providerType: .github, handle: "h"), "offline") }
        _ = await warn.submit(ConnectRequest(provider: .github, baseUrl: "u", secret: "t", workspaceId: "w"))
        XCTAssertTrue(warn.done)
        XCTAssertEqual(warn.syncWarning, "Connected, but sync failed: offline")
        let bad = AddConnectionModel { _ in .failed(.rejected("Wrong password")) }
        let r = await bad.submit(ConnectRequest(provider: .zentao, baseUrl: "u", username: "u", secret: "p", workspaceId: "w"))
        XCTAssertFalse(r); XCTAssertFalse(bad.done); XCTAssertEqual(bad.error, "Wrong password"); XCTAssertFalse(bad.busy)
        bad.reset(); XCTAssertNil(bad.error)
        XCTAssertEqual(AddConnectionModel.text(.allFieldsRequired), "All fields are required")
        XCTAssertEqual(AddConnectionModel.text(.noWorkspace), "Choose or create a workspace")
        XCTAssertEqual(AddConnectionModel.text(.connectionFailed), "Connection failed")
    }

    func testServerUrlTrimsTrailingSlash() {
        XCTAssertEqual(AccountRowView.serverUrl(" https://z/zentao/ "), "https://z/zentao")
        XCTAssertNil(AccountRowView.serverUrl("  "))
        XCTAssertNil(AccountRowView.serverUrl(nil))
    }

    func testWorkspaceEditorRefusalsAreWorded() {
        let tooLong = Failure.validation("x", fields: ["shortCode": "tooLong"])
        XCTAssertEqual(WorkspaceEditorDialog.refusal(tooLong), "Use at most 4 badge letters")
        XCTAssertEqual(WorkspaceEditorDialog.refusal(.validation("x", fields: ["name": "tooLong"])), "Use at most 40 characters")
        XCTAssertEqual(WorkspaceEditorDialog.refusal(.validation("x", fields: ["name": "missing"])), "Enter a name")
        XCTAssertEqual(WorkspaceEditorDialog.mimeType("a.JPG"), "image/jpeg")
        XCTAssertEqual(WorkspaceEditorDialog.mimeType("a.bmp"), "image/png")
    }
}
