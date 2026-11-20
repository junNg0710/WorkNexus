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

    /// A task with hours left on record (one without cannot be assigned in one click).
    private func task(_ key: String, assignee: String, left: Double? = 4) -> Ticket {
        var t = boardTask(key, assignee: assignee)
        t.providerEntity = .zentaoTask(ZenTaoTaskEntity(execution: "e1", left: left))
        return t
    }

    func testATaskWithNoHoursLeftSendsTheLeaderToTheDialog() async {
        let env = BoardsEnv(section: ZentaoSection.tasks, members: members)
        let outcome = await ZentaoBulkModel().quickAssign("binh", tickets: [task("1", assignee: "an", left: 0)], state: env.state, bugs: false, toasts: nil)
        XCTAssertEqual(outcome, .needsHours)
        XCTAssertTrue(env.adapter.assigned.isEmpty)
    }

    func testUndoGivesBackTheHoursTheAssignNeeded() async {
        let env = BoardsEnv(section: ZentaoSection.tasks, members: members)
        let before = [task("1", assignee: "an", left: 0)]
        await ZentaoBulkModel().undo(before: before, succeeded: ["zt1:task:1"], left: 3, state: env.state, bugs: false, toasts: nil)
        XCTAssertEqual(env.adapter.assigned.map(\.left), [3])
    }

    /// Undo sends each task the hours its own row gave it, ahead of the shared ones.
    func testUndoGivesEachTaskItsOwnHoursBack() async {
        let env = BoardsEnv(section: ZentaoSection.tasks, members: members)
        let before = [task("1", assignee: "an", left: 0), task("2", assignee: "an", left: 0)]
        await ZentaoBulkModel().undo(before: before, succeeded: ["zt1:task:1", "zt1:task:2"], left: 3, hours: ["zt1:task:1": 7],
                                     state: env.state, bugs: false, toasts: nil)
        XCTAssertEqual(env.adapter.assigned.map(\.left), [7, 3])
    }

    func testQuickAssignHandsOverWhatChangesAndRemembersThePerson() async {
        let env = BoardsEnv(section: ZentaoSection.tasks, members: members)
        let tickets = [task("1", assignee: "an"), task("2", assignee: "binh"), task("3", assignee: "an")]
        await ZentaoBulkModel().quickAssign("binh", tickets: tickets, state: env.state, bugs: false, toasts: nil)
        XCTAssertEqual(env.adapter.assigned.map(\.assignee), ["binh", "binh"])   // 2 is binh's already
        XCTAssertEqual(env.state.recentAssignees, ["binh"])
        XCTAssertEqual(env.state.quickAssignees, ["binh"])
    }

    func testQuickAssignSkipsSomeoneOffTheTeam() async {
        let env = BoardsEnv(section: ZentaoSection.tasks, members: members)
        await ZentaoBulkModel().quickAssign("zed", tickets: [task("1", assignee: "an")], state: env.state, bugs: false, toasts: nil)
        XCTAssertTrue(env.adapter.assigned.isEmpty)
        XCTAssertTrue(env.state.recentAssignees.isEmpty)
    }

    func testUndoHandsTheTicketsBack() async {
        let env = BoardsEnv(section: ZentaoSection.tasks, members: members)
        let before = [task("1", assignee: "an"), task("2", assignee: "binh")]
        await ZentaoBulkModel().undo(before: before, succeeded: before.map(\.id), state: env.state, bugs: false, toasts: nil)
        XCTAssertEqual(env.adapter.assigned.map(\.assignee), ["an", "binh"])
    }

    func testAnOtherPickSurvivesAQuickAssignOfOneCard() async {
        let env = BoardsEnv(section: ZentaoSection.tasks, members: members)
        let one = task("1", assignee: "an")
        env.state.taskBoard.select(["zt1:task:9"])
        await ZentaoBulkModel().quickAssign("binh", tickets: [one], state: env.state, bugs: false, toasts: nil)
        XCTAssertEqual(env.state.taskBoard.selectedIds, ["zt1:task:9"])
    }
}
