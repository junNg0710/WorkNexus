import CoreDomain
import CoreTools
import XCTest
@testable import FeatureWorkspaceOverview

@MainActor
final class OverviewModelTests: XCTestCase {
    private let ws1 = Workspace(id: "w1", name: "Company A", shortCode: "CA", colorValue: 0xFF3B82F6)
    private let ws2 = Workspace(id: "w2", name: "Company B", shortCode: "CB", colorValue: 0xFF16A99C)
    private let zt = Account(id: "zt", workspaceId: "w1", providerType: .zentao, handle: "thanh", baseUrl: "https://zentao.example.com/")
    private let other = Account(id: "gh", workspaceId: "w2", providerType: .github, handle: "octocat")

    private func started(_ repo: FakeOverview, active: String? = nil) async -> OverviewModel {
        let m = makeModel(repo, activeWorkspaceId: active)
        m.start()
        try? await Task.sleep(for: .milliseconds(120))
        return m
    }

    private func repo() -> FakeOverview {
        let r = FakeOverview()
        r.workspaces = [ws1, ws2]; r.accounts = [zt, other]
        r.tickets = [makeTicket("zt:1", accountId: "zt", key: "1", type: "Task", status: .inprogress),
                     makeTicket("zt:2", accountId: "zt", key: "2", type: "Bug", status: .todo),
                     makeTicket("zt:3", accountId: "zt", key: "3", type: "Task", status: .done, raw: "done"),
                     makeTicket("gh:1", accountId: "gh", provider: .github, key: "1", type: "Issue", assignee: "octocat")]
        return r
    }

    func testShowsTheFirstWorkspaceAndItsAccounts() async {
        let m = await started(repo())
        XCTAssertEqual(m.workspace?.id, "w1"); XCTAssertEqual(m.accounts.map(\.id), ["zt"])
        XCTAssertEqual(Set(m.assignedWork.map(\.ticketId)), ["zt:1", "zt:2"], "finished and other-workspace work is left out")
        m.stop()
    }

    func testActiveWorkspaceIsChosenById() async {
        let m = await started(repo(), active: "w2")
        XCTAssertEqual(m.workspace?.name, "Company B"); XCTAssertEqual(m.accounts.map(\.id), ["gh"])
        XCTAssertEqual(m.assignedWork.map(\.ticketId), ["gh:1"])
        m.stop()
    }

    func testQueueAndMyWorkLists() async {
        let m = await started(repo())
        XCTAssertEqual(m.queue(zt, .task).inProgress.map(\.id), ["zt:1"])
        XCTAssertEqual(m.queue(zt, .bug).notStarted.map(\.id), ["zt:2"])
        XCTAssertEqual(m.myWork(zt, .task, openOnly: false).count, 2)
        XCTAssertEqual(m.myWork(zt, .task, openOnly: true).count, 1)
        m.stop()
    }

    func testPreparedAccountSyncsOncePerSession() async {
        let r = repo(); let m = await started(r)
        await m.prepare(zt); await m.prepare(zt)
        XCTAssertEqual(r.syncCalls, ["zt"])
        XCTAssertEqual(r.refreshCalls, ["zt"], "a snapshot younger than maxAge is not fetched again")
        await m.refresh(zt)
        XCTAssertEqual(r.syncCalls, ["zt", "zt"]); XCTAssertEqual(r.refreshCalls, ["zt", "zt"])
        XCTAssertEqual(m.workSyncState["zt"], .idle)
        m.stop()
    }

    func testFailuresAreStatesNotCrashes() async {
        let r = repo(); r.refreshResult = .failure(.network("offline")); r.syncResult = .failure(.network("offline"))
        let m = await started(r)
        await m.loadDashboard("zt", force: true); await m.syncMyWork("zt", force: true)
        XCTAssertTrue(m.dashboardState["zt"]?.hasFailed == true); XCTAssertTrue(m.workSyncState["zt"]?.hasFailed == true)
        m.stop()
    }

    func testOpeningAnItemOpensItsTicketInTheDetailPanel() async {
        let r = repo(); let m = await started(r)
        let ok = await m.open(zt, kind: .bug, id: "2")
        XCTAssertTrue(ok); XCTAssertEqual(m.nav.openTicketId, "ticket-1")
        r.resolveResult = .failure(.notFound("gone"))
        let failed = await m.open(zt, kind: .task, id: "9")
        XCTAssertFalse(failed)
        m.stop()
    }

    func testMyWorkTargetClearsWhenItsAccountLeaves() async {
        let m = await started(repo())
        m.myWorkTarget = MyWorkTarget(account: zt, kind: .task)
        m.setAccounts([other])
        XCTAssertNil(m.myWorkTarget)
        m.stop()
    }

    func testNavigation() async {
        let m = await started(repo())
        m.select(zt, section: "zentao.sprints")
        XCTAssertEqual(m.nav.state.rail, .account("zt")); XCTAssertEqual(m.nav.location(for: "zt").section, "zentao.sprints")
        m.openIntegrations()
        XCTAssertEqual(m.nav.state.workspaceSection, "integrations"); XCTAssertEqual(m.nav.state.rail, .workspace)
        m.stop()
    }
}
