import CoreDomain
import XCTest
@testable import ToolZenTao

/// A board opens on the user's own work, then on whatever they last chose.
@MainActor
final class ZentaoDefaultScopeTests: XCTestCase {
    private final class StaticGroups: ZenTaoTeamGroupRepository, @unchecked Sendable {
        let groups: [ZenTaoTeamGroup]
        init(_ groups: [ZenTaoTeamGroup]) { self.groups = groups }
        func watchGroups(accountId: String) -> AsyncStream<[ZenTaoTeamGroup]> { AsyncStream { $0.yield(groups) } }
        func save(_ group: ZenTaoTeamGroup) async -> Outcome<Void> { .success(()) }
        func delete(id: String) async -> Outcome<Void> { .success(()) }
    }

    private func account(_ env: BoardsEnv) -> Account { env.store.accounts["zt1"]! }

    func testTheFirstVisitShowsTheUsersOwnWork() async {
        let env = BoardsEnv(section: ZentaoSection.tasks, boardScopes: InMemoryBoardScopes())
        env.state.applyDefaultScope(account: account(env), bugs: false)
        XCTAssertEqual(env.state.taskTeam?.group.isOnlyMe, true)
        XCTAssertEqual(env.state.taskTeam?.logins, ["thanh"])
        XCTAssertNil(env.state.bugTeam)   // each board on its own
    }

    func testLeavingOnlyMeIsRememberedForTheNextLaunch() async {
        let scopes = InMemoryBoardScopes()
        let env = BoardsEnv(section: ZentaoSection.tasks, boardScopes: scopes)
        env.state.applyDefaultScope(account: account(env), bugs: false)
        env.state.openExecution(env.execution("e1", "Sprint 1"))
        XCTAssertEqual(scopes.choice(accountId: "zt1", bugs: false), .scope)

        let next = BoardsEnv(section: ZentaoSection.tasks, boardScopes: scopes)
        next.state.applyDefaultScope(account: account(next), bugs: false)
        XCTAssertNil(next.state.taskTeam)
    }

    func testOpeningIsNotTakenForAChoice() async {
        let scopes = InMemoryBoardScopes()
        let env = BoardsEnv(section: ZentaoSection.tasks, boardScopes: scopes)
        env.state.applyDefaultScope(account: account(env), bugs: false)
        XCTAssertNil(scopes.choice(accountId: "zt1", bugs: false))
        env.state.openTeam(.onlyMe(accountId: "zt1", login: "thanh"), bugs: false)
        XCTAssertEqual(scopes.choice(accountId: "zt1", bugs: false), .onlyMe)
    }

    func testARememberedGroupOpensOnceTheGroupsAreRead() async {
        let mobile = ZenTaoTeamGroup(id: "g1", accountId: "zt1", name: "Mobile", members: [ZenTaoTeamMember(login: "an", name: "An")])
        let scopes = InMemoryBoardScopes()
        scopes.setChoice(.team(id: "g1"), accountId: "zt1", bugs: true)
        let env = BoardsEnv(section: ZentaoSection.bugs, teamGroups: StaticGroups([mobile]), boardScopes: scopes)
        env.state.applyDefaultScope(account: account(env), bugs: true)
        XCTAssertNil(env.state.bugTeam)   // the groups are not read yet
        await env.wait { env.state.teamGroups["zt1"] != nil }
        env.state.applyDefaultScope(account: account(env), bugs: true)
        XCTAssertEqual(env.state.bugTeam?.group.id, "g1")
    }

    func testOnlyMeGoesByTheLoginAsZenTaoWritesIt() async {
        let env = BoardsEnv(section: ZentaoSection.tasks, boardScopes: InMemoryBoardScopes())
        env.pages.personWork = ["thanh": ZenTaoPersonWork(ids: [], total: 0, truncated: false, login: "Thanh")]
        env.state.applyDefaultScope(account: account(env), bugs: false)
        await env.wait { env.state.taskTeam?.isLoading == false }
        XCTAssertEqual(env.state.taskTeam?.logins, ["Thanh"])
        XCTAssertEqual(env.state.boardMembers.map(\.account), ["Thanh"])
        XCTAssertNotNil(env.state.taskTeam?.loads["Thanh"])
    }

    func testTheDefaultIsAppliedOncePerSession() async {
        let env = BoardsEnv(section: ZentaoSection.tasks, boardScopes: InMemoryBoardScopes())
        env.state.applyDefaultScope(account: account(env), bugs: false)
        env.state.closeTeam(bugs: false)
        env.state.applyDefaultScope(account: account(env), bugs: false)
        XCTAssertNil(env.state.taskTeam)
    }
}
