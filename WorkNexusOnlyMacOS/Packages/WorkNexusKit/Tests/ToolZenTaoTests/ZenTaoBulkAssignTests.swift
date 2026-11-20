import CoreDomain
import XCTest
@testable import ToolZenTao

/// Who a bulk assign can go to, and handing the tickets back.
final class ZenTaoBulkAssignTests: XCTestCase {
    private func task(_ id: String, execution: String?, assignee: String? = "an") -> Ticket {
        Ticket(id: id, accountId: "a", projectId: "p", providerType: .zentao, externalKey: id, title: "T\(id)", body: "", priority: .medium,
               status: .inprogress, providerStatus: "doing", sourceHash: id, externalType: "Task", assignee: assignee,
               providerEntity: .zentaoTask(ZenTaoTaskEntity(execution: execution)))
    }

    private func bug(_ id: String, product: String?) -> Ticket {
        Ticket(id: id, accountId: "a", projectId: "p", providerType: .zentao, externalKey: id, title: "B\(id)", body: "", priority: .medium,
               status: .todo, providerStatus: "active", sourceHash: id, externalType: "Bug", assignee: "an",
               providerEntity: .zentaoBug(ZenTaoBugEntity(product: product)))
    }

    private func user(_ login: String, _ name: String) -> ProviderUser { ProviderUser(account: login, displayName: name) }

    // MARK: Teams

    func testATaskIsAssignedWithinItsExecutionAndABugWithinItsProduct() {
        XCTAssertEqual(ZenTaoAssignTeams.key(task("1", execution: "12")), "e:a:12")
        XCTAssertEqual(ZenTaoAssignTeams.key(bug("2", product: "3")), "p:a:3")
        XCTAssertNil(ZenTaoAssignTeams.key(task("3", execution: "0")))
        XCTAssertNil(ZenTaoAssignTeams.key(bug("4", product: nil)))
    }

    func testAnUnknownTeamTakesAnyone() {
        let teams = ZenTaoAssignTeams(members: ["e:a:1": ["an"]])
        XCTAssertTrue(teams.canTake(task("1", execution: "1"), "an"))
        XCTAssertFalse(teams.canTake(task("1", execution: "1"), "binh"))
        XCTAssertTrue(teams.canTake(task("2", execution: "9"), "binh"))   // its team was not read
        XCTAssertTrue(teams.canTake(task("3", execution: nil), "binh"))
    }

    // MARK: The people

    func testThoseWhoCanTakeEveryTicketComeFirstThenThePinnedThenByName() {
        let tickets = [task("1", execution: "1"), task("2", execution: "2")]
        let teams = ["e:a:1": [user("an", "An"), user("cuong", "Cuong"), user("binh", "Binh")],
                     "e:a:2": [user("an", "An"), user("binh", "Binh"), user("dung", "Dung")]]
        var an = ZenTaoWorkload(login: "an"); an.open = 4; an.overdue = 1
        let rows = ListBulkAssignees()(tickets: tickets, teams: teams, fallback: [], workload: [an], pinned: ["binh"])
        XCTAssertEqual(rows.map(\.login), ["binh", "an", "cuong", "dung"])
        XCTAssertEqual(rows.map(\.cannotTake), [0, 0, 1, 1])
        XCTAssertEqual(rows.first { $0.login == "an" }?.open, 4)
        XCTAssertEqual(rows.first { $0.login == "an" }?.overdue, 1)
        XCTAssertTrue(rows[0].pinned)
    }

    func testWithoutTeamsEveryUserOfTheAccountIsOffered() {
        let rows = ListBulkAssignees()(tickets: [task("1", execution: "1")], teams: [:], fallback: [user("an", ""), user("an", "dup")],
                                       workload: [], pinned: [])
        XCTAssertEqual(rows.map(\.login), ["an"])
        XCTAssertEqual(rows[0].name, "an")   // no display name: the login
        XCTAssertEqual(rows[0].cannotTake, 0)
    }

    // MARK: Undo

    func testUndoGivesEachTicketBackToItsHolder() {
        let before = [task("1", execution: "1", assignee: "an"), task("2", execution: "1", assignee: "binh"),
                      task("3", execution: "1", assignee: "an"), task("4", execution: "1", assignee: nil),
                      task("5", execution: "1", assignee: "an")]
        let undo = PlanBulkUndo()(before: before, succeeded: ["1", "2", "3", "4"])
        XCTAssertEqual(undo.steps.map(\.login), ["an", "binh"])
        XCTAssertEqual(undo.steps[0].tickets.map(\.id), ["1", "3"])   // 5 failed: nothing to undo there
        XCTAssertEqual(undo.cannotUndo.map(\.id), ["4"])               // nobody held it before
    }

    func testNothingToUndoWhenNobodyHeldThem() {
        let undo = PlanBulkUndo()(before: [task("1", execution: "1", assignee: "closed")], succeeded: ["1"])
        XCTAssertTrue(undo.isEmpty)
        XCTAssertEqual(undo.cannotUndo.count, 1)
    }

    // MARK: The default scope

    private let group = ZenTaoTeamGroup(id: "g1", accountId: "a", name: "Mobile", members: [])

    func testABoardOpensOnTheUsersOwnWorkUntilTheyChooseOtherwise() {
        let resolve = ResolveDefaultBoardScope()
        XCTAssertEqual(resolve(nil, groups: nil, login: "thanh"), .onlyMe)
        XCTAssertEqual(resolve(.onlyMe, groups: [], login: "thanh"), .onlyMe)
        XCTAssertEqual(resolve(.scope, groups: nil, login: "thanh"), .scope)
        XCTAssertEqual(resolve(nil, groups: nil, login: " "), .scope)   // no login: no own work to show
    }

    func testARememberedGroupWaitsForTheGroupsAndFallsBackWhenDeleted() {
        let resolve = ResolveDefaultBoardScope()
        XCTAssertEqual(resolve(.team(id: "g1"), groups: nil, login: "thanh"), .waitForGroups)
        XCTAssertEqual(resolve(.team(id: "g1"), groups: [group], login: "thanh"), .team(group))
        XCTAssertEqual(resolve(.team(id: "gone"), groups: [group], login: "thanh"), .onlyMe)
    }

    func testTheChoiceIsStoredAsText() {
        for choice in [ZenTaoBoardScopeChoice.onlyMe, .scope, .team(id: "a:b")] {
            XCTAssertEqual(ZenTaoBoardScopeChoice(stored: choice.stored), choice)
        }
        XCTAssertNil(ZenTaoBoardScopeChoice(stored: "team:"))
        XCTAssertNil(ZenTaoBoardScopeChoice(stored: "?"))
    }

    func testOnlyMeIsTheAccountsOwnGroup() {
        let me = ZenTaoTeamGroup.onlyMe(accountId: "a", login: "thanh")
        XCTAssertTrue(me.isOnlyMe)
        XCTAssertEqual(me.members.map(\.login), ["thanh"])
        XCTAssertFalse(group.isOnlyMe)
    }
}
