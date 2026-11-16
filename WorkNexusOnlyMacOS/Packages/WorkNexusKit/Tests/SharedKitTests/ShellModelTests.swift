import CoreDomain
import CoreTools
import Foundation
import XCTest
@testable import SharedKit

/// A workspace repository whose lists can change after the first emission (the shell follows the database).
final class LiveWorkspaces: WorkspaceRepository, @unchecked Sendable {
    private let lock = NSLock()
    private var ws: [Workspace], accts: [Account]
    private var wsC: [AsyncStream<[Workspace]>.Continuation] = [], acC: [AsyncStream<[Account]>.Continuation] = []
    init(_ ws: [Workspace], _ accts: [Account]) { self.ws = ws; self.accts = accts }

    func setAccounts(_ list: [Account]) { let cs = lock.withLock { accts = list; return acC }; cs.forEach { $0.yield(Account.sort(list)) } }
    func watchWorkspaces() -> AsyncStream<[Workspace]> {
        AsyncStream { c in lock.withLock { wsC.append(c) }; c.yield(ws) }
    }
    func watchAccounts() -> AsyncStream<[Account]> {
        AsyncStream { c in lock.withLock { acC.append(c) }; c.yield(Account.sort(accts)) }
    }
    func watchProjects() -> AsyncStream<[Project]> { AsyncStream { $0.yield([]) } }
    func createWorkspace(_ workspace: Workspace) async -> Outcome<Void> { .success(()) }
    func updateWorkspace(_ workspace: Workspace) async -> Outcome<Void> { .success(()) }
    func upsertAccount(_ account: Account) async -> Outcome<Void> { .success(()) }
    func deleteAccount(id: String) async -> Outcome<Void> { .success(()) }
    func upsertProjects(_ projects: [Project]) async -> Outcome<Void> { .success(()) }
}

final class FixedStatus: SyncStatusRepository, @unchecked Sendable {
    let value: AccountSyncStatus
    init(_ v: AccountSyncStatus) { value = v }
    func watch(accountId: String) -> AsyncStream<AccountSyncStatus> { AsyncStream { $0.yield(value) } }
    func status(accountId: String) async -> AccountSyncStatus { value }
    func report(accountId: String, status: AccountSyncStatus) {}
}

final class MemoryWorkspaceStore: ActiveWorkspaceStoring, @unchecked Sendable {
    var id: String?
    init(_ id: String? = nil) { self.id = id }
    func load() -> String? { id }
    func save(_ workspaceId: String?) { id = workspaceId }
}

@MainActor
final class ShellModelTests: XCTestCase {
    private let wsA = Workspace(id: "a", name: "Alpha", shortCode: "A", colorValue: 1)
    private let wsB = Workspace(id: "b", name: "Beta", shortCode: "B", colorValue: 2)
    private func acct(_ id: String, _ ws: String, _ p: ProviderType = .gitlab) -> Account {
        Account(id: id, workspaceId: ws, providerType: p, handle: id)
    }

    private func make(accounts: [Account], store: MemoryWorkspaceStore = MemoryWorkspaceStore(), chatAtLaunch: Bool = true,
                      status: SyncStatusRepository = SyncTests.RecordingStatus())
        -> (ShellModel, LiveWorkspaces, MemoryWorkspaceStore) {
        let live = LiveWorkspaces([wsA, wsB], accounts)
        let fake = FakeStore()
        let services = AppServices(tickets: fake, workspaces: live, comments: fake, activity: fake, syncStatus: status,
                                   settings: BoardControllerTests.FakeSettings(), credentials: fake, sync: BoardControllerTests.NoopSync(),
                                   ticketDetail: BoardControllerTests.NoopSync(), adapters: FakeRegistry())
        let shell = ShellModel(services: services, registry: ToolRegistry(), workspaceStore: store)
        shell.opensChatAtLaunch = chatAtLaunch
        shell.start()
        return (shell, live, store)
    }

    private func settle(_ shell: ShellModel, until cond: () -> Bool = { true }) async {
        for _ in 0..<100 where !(shell.loadedAccounts && shell.loadedWorkspaces && cond()) { try? await Task.sleep(for: .milliseconds(10)) }
        try? await Task.sleep(for: .milliseconds(20))
    }

    func testActiveWorkspaceDefaultsToFirstAndScopesAccounts() async {
        let (shell, _, _) = make(accounts: [acct("a1", "a"), acct("b1", "b")])
        await settle(shell)
        XCTAssertEqual(shell.workspace?.id, "a")
        XCTAssertEqual(shell.workspaceAccounts.map(\.id), ["a1"])
        XCTAssertEqual(shell.railAccounts.map(\.id), ["a1"])
    }

    func testSwitchWorkspaceFollowsEverywhereAndIsRemembered() async {
        let (shell, _, store) = make(accounts: [acct("a1", "a"), acct("b1", "b")])
        await settle(shell)
        shell.nav.openTicket("t1")
        shell.switchWorkspace("b")
        XCTAssertEqual(shell.workspace?.id, "b")
        XCTAssertEqual(shell.railAccounts.map(\.id), ["b1"])
        XCTAssertEqual(shell.nav.state.rail, .account("b1"), "the new workspace's first app opens")
        XCTAssertTrue(shell.nav.state.ticketHistories.isEmpty, "every open ticket closes")
        XCTAssertEqual(store.id, "b")
        // A new shell over the same store opens in the remembered workspace.
        let (again, _, _) = make(accounts: [acct("a1", "a"), acct("b1", "b")], store: store)
        await settle(again)
        XCTAssertEqual(again.workspace?.id, "b")
    }

    func testSwitchToEmptyWorkspaceShowsItsOverview() async {
        let (shell, _, _) = make(accounts: [acct("a1", "a")])
        await settle(shell)
        shell.switchWorkspace("b")
        XCTAssertEqual(shell.nav.state.rail, .workspace)
        XCTAssertTrue(shell.nav.state.userSelectedWorkspace)
        XCTAssertTrue(shell.railAccounts.isEmpty)
    }

    func testStaleActiveIdFallsBackToFirst() async {
        let (shell, _, _) = make(accounts: [], store: MemoryWorkspaceStore("gone"))
        await settle(shell)
        XCTAssertEqual(shell.workspace?.id, "a")
    }

    func testLaunchOpensFirstAccountUnlessUserChoseTheDashboard() async {
        let (shell, _, _) = make(accounts: [acct("a1", "a")])
        await settle(shell)
        XCTAssertEqual(shell.nav.state.rail, .account("a1"))

        let live = LiveWorkspaces([wsA], [acct("a1", "a")])
        let fake = FakeStore()
        let services = AppServices(tickets: fake, workspaces: live, comments: fake, activity: fake, syncStatus: SyncTests.RecordingStatus(),
                                   settings: BoardControllerTests.FakeSettings(), credentials: fake, sync: BoardControllerTests.NoopSync(),
                                   ticketDetail: BoardControllerTests.NoopSync(), adapters: FakeRegistry())
        let chosen = ShellModel(services: services, registry: ToolRegistry())
        chosen.nav.select(.workspace)
        chosen.start()
        await settle(chosen)
        XCTAssertEqual(chosen.nav.state.rail, .workspace)
    }

    func testChatOpensAtLaunchOnlyWhenTheAppPickedThePlace() async {
        let (shell, _, _) = make(accounts: [acct("zt", "a", .zentao)])
        await settle(shell)
        XCTAssertEqual(shell.nav.state.rail, .chat)
        let (off, _, _) = make(accounts: [acct("zt", "a", .zentao)], chatAtLaunch: false)
        await settle(off)
        XCTAssertEqual(off.nav.state.rail, .account("zt"))
    }

    func testOpeningAnAccountOfAnotherWorkspaceJoinsIt() async {
        let (shell, _, store) = make(accounts: [acct("a1", "a"), acct("b1", "b")])
        await settle(shell)
        shell.nav.select(.account("b1"))
        shell.noteRail(.account("b1"))
        XCTAssertEqual(shell.workspace?.id, "b")
        XCTAssertEqual(store.id, "b")
        XCTAssertEqual(shell.nav.state.rail, .account("b1"), "joining must not move the rail")
    }

    func testRemovedAccountFallsBackToDashboardThenDefault() async {
        let (shell, live, _) = make(accounts: [acct("a1", "a"), acct("a2", "a")])
        await settle(shell)
        shell.nav.select(.account("a2"))
        live.setAccounts([acct("a1", "a")])
        await settle(shell, until: { shell.nav.state.rail == .account("a1") })
        XCTAssertEqual(shell.nav.state.rail, .account("a1"))
        XCTAssertNil(shell.nav.state.locations["a2"])
    }

    func testSyncStatusFollowsAccounts() async {
        let (shell, _, _) = make(accounts: [acct("a1", "a")], status: FixedStatus(.authExpired))
        await settle(shell, until: { shell.syncStatuses["a1"] != nil })
        XCTAssertEqual(shell.syncStatus(of: "a1"), .authExpired)
    }

    func testNewTicketTargetsDefaultsHideTheButton() {
        XCTAssertNil(ShellHost().newTicketTargets)
        XCTAssertEqual(NewTicketTarget(accountId: "x", accountHandle: "h", isBug: true, route: .newBug(accountId: "x")).id, "x|bug")
    }

    func testCelebrateTicks() async {
        let (shell, _, _) = make(accounts: [])
        shell.celebrate(); shell.celebrate()
        XCTAssertEqual(shell.celebration.tick, 2)
    }
}

final class KeepAliveLRUTests: XCTestCase {
    func testKeepsTheLastFiveAndEvictsTheLeastRecentlyUsed() {
        var lru = KeepAliveLRU(limit: 5)
        for k in ["a", "b", "c", "d", "e"] { XCTAssertNil(lru.touch(k)) }
        XCTAssertNil(lru.touch("a"), "touching a kept key evicts nothing and makes it the newest")
        XCTAssertEqual(lru.touch("f"), "b")
        XCTAssertEqual(lru.keys, ["c", "d", "e", "a", "f"])
        XCTAssertEqual(lru.touch("g"), "c")
        XCTAssertTrue(lru.contains("a"))
    }

    func testRetainAndRemove() {
        var lru = KeepAliveLRU(limit: 3)
        ["a:1", "b:1", "a:2"].forEach { lru.touch($0) }
        lru.retain { !$0.hasPrefix("a") }
        XCTAssertEqual(lru.keys, ["b:1"])
        lru.remove("b:1"); XCTAssertTrue(lru.keys.isEmpty)
    }

    func testLimitIsAtLeastOne() { var l = KeepAliveLRU(limit: 0); XCTAssertNil(l.touch("a")); XCTAssertEqual(l.touch("b"), "a") }
}

final class SectionHealthTests: XCTestCase {
    func testStatusMapping() {
        XCTAssertEqual(SectionHealth(status: .authExpired, hasCachedData: true), .authExpired)
        XCTAssertEqual(SectionHealth(status: .syncing, hasCachedData: false), .healthy)
        XCTAssertEqual(SectionHealth(status: .idle(lastSyncedAt: nil), hasCachedData: false), .healthy)
        XCTAssertEqual(SectionHealth(status: .offline, hasCachedData: true), .offline(blocked: false))
        XCTAssertEqual(SectionHealth(status: .error("x"), hasCachedData: false), .failed("x", blocked: true))
    }

    func testOnlyAnEmptyFailedAccountBlocksTheSection() {
        XCTAssertTrue(SectionHealth(status: .error("x"), hasCachedData: false).blocksSection)
        XCTAssertFalse(SectionHealth(status: .error("x"), hasCachedData: true).blocksSection)
        XCTAssertFalse(SectionHealth.authExpired.blocksSection)
        XCTAssertNotEqual(SectionHealth.failed("a", blocked: false).newsKey, SectionHealth.failed("b", blocked: false).newsKey)
    }
}

final class ActiveWorkspaceStoreTests: XCTestCase {
    func testFileStoreRoundTrip() {
        let file = FileManager.default.temporaryDirectory.appendingPathComponent("wn-aw-\(UUID().uuidString)/active.txt")
        let store = FileActiveWorkspaceStore(file: file)
        XCTAssertNil(store.load())
        store.save("ws_1"); XCTAssertEqual(store.load(), "ws_1")
        store.save(nil); XCTAssertNil(store.load())
        try? FileManager.default.removeItem(at: file.deletingLastPathComponent())
    }
}

final class SavedFilterStorageTests: XCTestCase {
    func testInstalledRepositoryIsWhatBoardsGet() async {
        let mine = InMemorySavedFilterRepository([SavedFilter(id: "1", name: "n", filter: FilterState(), createdAt: Date())])
        SavedFilterStorage.install(mine)
        var it = SavedFilterStorage.shared.watchSavedFilters().makeAsyncIterator()
        let first = await it.next()
        XCTAssertEqual(first?.map(\.id), ["1"])
    }
}
