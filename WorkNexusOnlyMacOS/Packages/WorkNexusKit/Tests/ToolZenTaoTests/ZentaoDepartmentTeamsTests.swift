import CoreDomain
import CoreUI
import XCTest
@testable import ToolZenTao

/// ZenTao's departments as teams, and teams pinned to the top of the Team menu.
@MainActor
final class ZentaoDepartmentTeamsTests: XCTestCase {
    private func dept(_ id: Int, _ name: String, parent: Int = 0, order: Int = 0) -> ZenTaoDepartment {
        ZenTaoDepartment(id: id, name: name, parentId: parent, path: name, order: order)
    }
    private func user(_ login: String, _ dept: Int) -> ZenTaoDepartmentUser { ZenTaoDepartmentUser(login: login, name: login.uppercased(), dept: dept) }

    /// HK and VN at the top; under VN, Flutter VN and Go VN in ZenTao's order; Testing VN has nobody.
    private var departments: [ZenTaoDepartment] {
        [dept(2, "VN", order: 2), dept(1, "Flutter HK", order: 1), dept(5, "Go VN", parent: 2, order: 2),
         dept(4, "Flutter VN", parent: 2, order: 1), dept(6, "Testing VN", parent: 2, order: 3), dept(9, "Lost", parent: 77)]
    }
    private var users: [ZenTaoDepartmentUser] {
        [user("hk1", 1), user("an", 4), user("binh", 4), user("cuong", 5), user("lead", 2), user("x", 9), user("nobody", 0)]
    }

    func testDepartmentsBecomeTeamsInZenTaosOrderEachWithEveryoneBelowIt() {
        let teams = BuildDepartmentTeams()(accountId: "zt1", departments: departments, users: users)
        XCTAssertEqual(teams.map(\.group.name), ["Lost", "Flutter HK", "VN", "Flutter VN", "Go VN"])   // Testing VN: nobody
        let vn = teams[2]
        XCTAssertEqual(vn.group.members.map(\.login), ["lead", "an", "binh", "cuong"])
        XCTAssertTrue(vn.hasChildren)
        XCTAssertEqual(teams[3].parentId, vn.id)
        XCTAssertEqual(teams[3].depth, 1)
        XCTAssertEqual(teams[3].group.members.map(\.name), ["AN", "BINH"])
        XCTAssertFalse(teams[1].hasChildren)
        XCTAssertEqual(teams[0].depth, 0)   // its parent is unknown: a top department, not lost
        XCTAssertEqual(vn.id, "dept:zt1:2")
        XCTAssertTrue(vn.group.isDepartment)
    }

    func testAParentWithNobodyAnywhereBelowIsLeftOut() {
        let teams = BuildDepartmentTeams()(accountId: "zt1", departments: [dept(1, "Empty"), dept(2, "Child", parent: 1)], users: [])
        XCTAssertTrue(teams.isEmpty)
    }

    // MARK: The Team menu

    private struct Fixed: ZenTaoDepartmentTeamSource {
        let teams: [ZenTaoDepartmentTeam]
        func departmentTeams(accountId: String) async -> Outcome<[ZenTaoDepartmentTeam]> { .success(teams) }
    }

    private func env(scopes: ZenTaoBoardScopeStore = BoardsEnv.onTheirScope()) async -> BoardsEnv {
        let teams = BuildDepartmentTeams()(accountId: "zt1", departments: departments, users: users)
        let env = BoardsEnv(section: ZentaoSection.tasks, boardScopes: scopes, departmentTeams: Fixed(teams: teams))
        env.state.loadTeamGroups("zt1")
        env.state.loadDepartmentTeams("zt1")
        await env.wait { env.state.departmentTeams["zt1"]?.value != nil && env.state.teamGroups["zt1"] != nil }
        return env
    }

    private func items(_ env: BoardsEnv) -> [AppNativeMenu.Item] {
        ZentaoTeamMenuItems(state: env.state, account: env.store.accounts["zt1"]!, bugs: false, onNew: {}, onEdit: { _ in }, onDelete: {}).items
    }

    func testTheDepartmentsAreATreeInTheMenu() async {
        let env = await env()
        let tree = try? XCTUnwrap(items(env).first { $0.title == "ZenTao teams" })
        XCTAssertEqual(tree?.children.map(\.title), ["Lost · 1", "Flutter HK · 1", "VN · 4"])
        let vn = tree?.children[2]
        XCTAssertEqual(vn?.children.map(\.title), ["All of VN · 4", "Flutter VN · 2", "Go VN · 1"])
        vn?.children[1].action()
        XCTAssertEqual(env.state.taskTeam?.group.name, "Flutter VN")
        XCTAssertEqual(env.state.taskTeam?.logins, ["an", "binh"])
    }

    func testAPinnedTeamLeadsTheMenuAndCanBeUnpinned() async {
        let env = await env()
        let flutter = env.state.departmentTeams["zt1"]!.value!.first { $0.group.name == "Flutter VN" }!.group
        env.state.openTeam(flutter, bugs: false)
        let pin = items(env).first { $0.title.hasPrefix("Pin") }
        XCTAssertEqual(pin?.title, "Pin “Flutter VN” to the top")
        pin?.action()
        XCTAssertEqual(env.state.pinnedTeamIds("zt1"), [flutter.id])
        let titles = items(env).map(\.title)
        // Back, Only me, then the pinned team, ahead of the department tree.
        XCTAssertEqual(Array(titles.prefix(3)), ["Back to the execution", "Only me", "Flutter VN · 2"])
        XCTAssertFalse(titles.contains("Edit this group…"))   // a department is not edited here
        items(env).first { $0.title.hasPrefix("Unpin") }?.action()
        XCTAssertTrue(env.state.pinnedTeamIds("zt1").isEmpty)
    }

    func testARememberedDepartmentTeamOpensOnceTheDepartmentsAreRead() async {
        let scopes = InMemoryBoardScopes()
        scopes.setChoice(.team(id: "dept:zt1:4"), accountId: "zt1", bugs: false)
        let teams = BuildDepartmentTeams()(accountId: "zt1", departments: departments, users: users)
        let env = BoardsEnv(section: ZentaoSection.tasks, boardScopes: scopes, departmentTeams: Fixed(teams: teams))
        let account = env.store.accounts["zt1"]!
        env.state.applyDefaultScope(account: account, bugs: false)
        XCTAssertNil(env.state.taskTeam)   // still reading
        await env.wait { env.state.departmentTeams["zt1"]?.value != nil && env.state.teamGroups["zt1"] != nil }
        env.state.applyDefaultScope(account: account, bugs: false)
        XCTAssertEqual(env.state.taskTeam?.group.name, "Flutter VN")
    }
}
