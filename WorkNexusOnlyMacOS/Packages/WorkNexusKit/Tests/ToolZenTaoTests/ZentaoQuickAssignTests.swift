import CoreDomain
import XCTest
@testable import ToolZenTao

/// Handing tickets out in one click: the people offered, what a dropped card carries, and the run itself.
@MainActor
final class ZentaoQuickAssignTests: XCTestCase {
    func testTheMostRecentLeadsAndTheListStaysShort() {
        var recent: [String] = []
        for login in ["an", "binh", "an", "cuong", "dung", "em", "giang", ""] { recent = RememberRecentAssignee()(recent, login) }
        XCTAssertEqual(recent, ["giang", "em", "dung", "cuong", "an"])
    }

    func testThePinnedComeBeforeTheRecentEachOnce() {
        XCTAssertEqual(ListQuickAssignees()(pinned: ["binh", "an"], recent: ["an", "cuong"]), ["binh", "an", "cuong"])
        let many = (1...20).map { "p\($0)" }
        XCTAssertEqual(ListQuickAssignees()(pinned: many, recent: []).count, ListQuickAssignees.limit)
    }

    func testADroppedCardBringsItsPickAlong() {
        XCTAssertEqual(DroppedTicketIds()(dropped: "1", picked: ["1", "2"]), ["1", "2"])
        XCTAssertEqual(DroppedTicketIds()(dropped: "3", picked: ["1", "2"]), ["3"])   // not picked: that card alone
    }

    private let members = [ProviderUser(account: "an", displayName: "An"), ProviderUser(account: "binh", displayName: "Binh")]

    func testQuickAssignHandsOverWhatChangesAndRemembersThePerson() async {
        let env = BoardsEnv(section: ZentaoSection.tasks, members: members)
        let tickets = [boardTask("1", assignee: "an"), boardTask("2", assignee: "binh"), boardTask("3", assignee: "an")]
        await ZentaoBulkModel().quickAssign("binh", tickets: tickets, state: env.state, bugs: false, toasts: nil)
        XCTAssertEqual(env.adapter.assigned.map(\.assignee), ["binh", "binh"])   // 2 is binh's already
        XCTAssertEqual(env.state.recentAssignees, ["binh"])
        XCTAssertEqual(env.state.quickAssignees, ["binh"])
    }

    func testQuickAssignSkipsSomeoneOffTheTeam() async {
        let env = BoardsEnv(section: ZentaoSection.tasks, members: members)
        await ZentaoBulkModel().quickAssign("zed", tickets: [boardTask("1", assignee: "an")], state: env.state, bugs: false, toasts: nil)
        XCTAssertTrue(env.adapter.assigned.isEmpty)
        XCTAssertTrue(env.state.recentAssignees.isEmpty)
    }

    func testUndoHandsTheTicketsBack() async {
        let env = BoardsEnv(section: ZentaoSection.tasks, members: members)
        let before = [boardTask("1", assignee: "an"), boardTask("2", assignee: "binh")]
        await ZentaoBulkModel().undo(before: before, succeeded: before.map(\.id), state: env.state, bugs: false, toasts: nil)
        XCTAssertEqual(env.adapter.assigned.map(\.assignee), ["an", "binh"])
    }

    func testAnOtherPickSurvivesAQuickAssignOfOneCard() async {
        let env = BoardsEnv(section: ZentaoSection.tasks, members: members)
        let one = boardTask("1", assignee: "an")
        env.state.taskBoard.select(["zt1:task:9"])
        await ZentaoBulkModel().quickAssign("binh", tickets: [one], state: env.state, bugs: false, toasts: nil)
        XCTAssertEqual(env.state.taskBoard.selectedIds, ["zt1:task:9"])
    }
}
