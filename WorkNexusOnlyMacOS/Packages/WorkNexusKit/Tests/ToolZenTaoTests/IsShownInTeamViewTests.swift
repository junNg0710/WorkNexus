import CoreDomain
import XCTest
@testable import ToolZenTao

/// Which executions' tasks a team view shows.
@MainActor
final class IsShownInTeamViewTests: XCTestCase {
    private let shown = IsShownInTeamView()

    func testADailyReportExecutionIsLeftOutByDefault() {
        XCTAssertFalse(shown(accountId: "zt1", executionId: "7", executionName: "VN_Daily_Tasks", choices: [:]))
        XCTAssertFalse(shown(accountId: "zt1", executionId: "7", executionName: "daily report", choices: [:]))
        XCTAssertTrue(shown(accountId: "zt1", executionId: "8", executionName: "VN_IM_Chat", choices: [:]))
        XCTAssertTrue(shown(accountId: "zt1", executionId: nil, executionName: nil, choices: [:]))
    }

    func testTheUsersChoiceWinsBothWays() {
        let choices = ["zt1:7": true, "zt1:8": false]
        XCTAssertTrue(shown(accountId: "zt1", executionId: "7", executionName: "VN_Daily_Tasks", choices: choices))
        XCTAssertFalse(shown(accountId: "zt1", executionId: "8", executionName: "VN_IM_Chat", choices: choices))
        // A choice belongs to one account.
        XCTAssertFalse(shown(accountId: "zt2", executionId: "7", executionName: "VN_Daily_Tasks", choices: choices))
    }

    func testATeamViewLeavesTheDailyReportsOutButTheirExecutionStillListsThem() async {
        var daily = boardTask("5", execution: "e9", assignee: "an")
        daily.providerEntity = .zentaoTask(ZenTaoTaskEntity(execution: "e9", executionName: "VN_Daily_Tasks"))
        let work = boardTask("1", execution: "e1", assignee: "an")
        let env = BoardsEnv(section: ZentaoSection.tasks, tickets: [work, daily])
        env.pages.personWork = ["an": ZenTaoPersonWork(ids: [work.id, daily.id], total: 2, truncated: false)]
        await env.wait { env.state.taskBoard.tickets.count == 2 }

        env.state.openTeam(ZenTaoTeamGroup(id: "g1", accountId: "zt1", name: "Mobile", members: [ZenTaoTeamMember(login: "an", name: "An")]),
                           bugs: false)
        await env.wait { env.state.taskTeam?.isLoading == false }
        XCTAssertEqual(env.state.taskBoard.scoped.map(\.externalKey), ["1"])

        env.state.openExecution(env.execution("e9", "VN_Daily_Tasks"))
        await env.wait { env.state.taskBoard.scoped.map(\.externalKey) == ["5"] }
    }
}
