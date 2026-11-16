import CoreDomain
import XCTest
@testable import ToolZenTao

/// A team group as the scope of the Tasks board.
@MainActor
final class ZentaoTeamStateTests: XCTestCase {
    private final class MemoryGroups: ZenTaoTeamGroupRepository, @unchecked Sendable {
        private let lock = NSLock()
        private var groups: [ZenTaoTeamGroup] = []
        private var continuation: AsyncStream<[ZenTaoTeamGroup]>.Continuation?
        func watchGroups(accountId: String) -> AsyncStream<[ZenTaoTeamGroup]> {
            AsyncStream { c in lock.withLock { continuation = c; c.yield(groups) } }
        }
        func save(_ group: ZenTaoTeamGroup) async -> Outcome<Void> {
            lock.withLock {
                if let i = groups.firstIndex(where: { $0.id == group.id }) { groups[i] = group } else { groups.append(group) }
                continuation?.yield(groups)
            }
            return .success(())
        }
        func delete(id: String) async -> Outcome<Void> {
            lock.withLock { groups.removeAll { $0.id == id }; continuation?.yield(groups) }
            return .success(())
        }
    }

    private func id(_ key: String) -> String { zenTaoTicketId(accountId: "zt1", type: "task", id: key) }
    private let an = ZenTaoTeamMember(login: "an", name: "An Nguyen"), binh = ZenTaoTeamMember(login: "binh", name: "Binh Tran")

    private func env(groups: ZenTaoTeamGroupRepository = NoTeamGroups()) async -> BoardsEnv {
        let tickets = [boardTask("1", execution: "e1", providerStatus: "doing", status: .inprogress, assignee: "an"),
                       boardTask("2", execution: "e2", assignee: "binh"), boardTask("3", execution: "e2", assignee: "carol"),
                       boardTask("4", execution: "e1", assignee: "an"), boardBug("9", assignee: "an")]
        let env = BoardsEnv(section: ZentaoSection.tasks, tickets: tickets, teamGroups: groups)
        env.pages.personWork = ["an": ZenTaoPersonWork(ids: [id("1"), id("4"), "zt1:bug:9"], total: 3, truncated: false),
                                "binh": ZenTaoPersonWork(ids: [id("2")], total: 1, truncated: false)]
        await env.wait { env.state.taskBoard.tickets.count == 5 }
        return env
    }

    private func group(_ members: [ZenTaoTeamMember]) -> ZenTaoTeamGroup {
        ZenTaoTeamGroup(id: "g1", accountId: "zt1", name: "Mobile", members: members)
    }

    func testATeamShowsEachPersonsTasksFromEveryExecution() async {
        let env = await env()
        env.state.openTeam(group([an, binh]), bugs: false)
        await env.wait { env.state.taskTeam?.isLoading == false }
        // The tasks of two executions, and not the bug or the task nobody on the team holds.
        XCTAssertEqual(Set(env.state.taskBoard.scoped.map(\.externalKey)), ["1", "2", "4"])
        XCTAssertEqual(env.state.boardMembers.map(\.displayName), ["An Nguyen", "Binh Tran"])
        XCTAssertEqual(env.state.taskTeam?.loads["an"], .loaded(count: 3, total: 3, truncated: false))
        XCTAssertEqual(env.pages.personCalls.sorted(), ["an|false", "binh|false"])
        // The leader bar counts the people of the team, the idle ones too.
        XCTAssertEqual(env.state.workload(bugs: false).map(\.login), ["an", "binh"])
    }

    func testAPersonThatCannotBeReadIsReportedAndRetriedAlone() async {
        let env = await env()
        env.pages.personFailures["binh"] = .network("no right to see this")
        env.state.openTeam(group([an, binh]), bugs: false)
        await env.wait { env.state.taskTeam?.isLoading == false }
        XCTAssertEqual(env.state.taskTeam?.failed, ["binh"])
        XCTAssertFalse(env.state.taskTeam?.allFailed ?? true)
        XCTAssertEqual(Set(env.state.taskBoard.scoped.map(\.externalKey)), ["1", "4"])

        env.pages.personFailures["binh"] = nil
        env.state.loadTeam(bugs: false, only: ["binh"])
        await env.wait { env.state.taskTeam?.failed.isEmpty == true && env.state.taskTeam?.isLoading == false }
        XCTAssertEqual(Set(env.state.taskBoard.scoped.map(\.externalKey)), ["1", "2", "4"])
        XCTAssertEqual(env.pages.personCalls.filter { $0 == "an|false" }.count, 1)   // an was not read again
    }

    func testEveryoneRefusedIsAFailureOfTheWholeTeam() async {
        let env = await env()
        env.pages.personFailures = ["an": .network("x"), "binh": .network("x")]
        env.state.openTeam(group([an, binh]), bugs: false)
        await env.wait { env.state.taskTeam?.isLoading == false }
        XCTAssertTrue(env.state.taskTeam?.allFailed ?? false)
        XCTAssertTrue(env.state.taskBoard.scoped.isEmpty)
    }

    func testPickingAnExecutionLeavesTheTeam() async {
        let env = await env()
        env.state.openTeam(group([an]), bugs: false)
        await env.wait { env.state.taskTeam?.isLoading == false }
        XCTAssertNotNil(env.state.taskTeam)
        env.state.openExecution(env.execution("e1", "Sprint 1"))
        XCTAssertNil(env.state.taskTeam)
        XCTAssertTrue(env.state.boardMembers.isEmpty || env.state.membersFor != "team:g1")
    }

    /// The store's stream is what feeds the board; a ticket reassigned since it was read must not stay in the team's view.
    func testAReassignedTicketLeavesTheTeamsView() {
        var scope = ZentaoTeamScope(group: group([an]))
        scope.ids = [id("1"), id("4")]
        let held = boardTask("1", assignee: "an"), moved = boardTask("1", assignee: "carol"), other = boardTask("4", assignee: "an")
        XCTAssertEqual(scope.tickets(in: [held, other], bugs: false).map(\.externalKey), ["1", "4"])
        XCTAssertEqual(scope.tickets(in: [moved, other], bugs: false).map(\.externalKey), ["4"])
        // Bugs and tasks are kept apart.
        XCTAssertTrue(scope.tickets(in: [held], bugs: true).isEmpty)
    }

    func testSavingAGroupUpdatesTheTeamShownAndReadsOnlyTheNewPerson() async {
        let groups = MemoryGroups()
        let env = await env(groups: groups)
        env.state.loadTeamGroups("zt1")
        let mobile = group([an])
        _ = await groups.save(mobile)
        await env.wait { env.state.teamGroups["zt1"]?.count == 1 }
        env.state.openTeam(mobile, bugs: false)
        await env.wait { env.state.taskTeam?.isLoading == false }

        _ = await groups.save(group([an, binh]))
        await env.wait { env.state.taskTeam?.group.members.count == 2 && env.state.taskTeam?.isLoading == false }
        XCTAssertEqual(Set(env.state.taskBoard.scoped.map(\.externalKey)), ["1", "2", "4"])
        XCTAssertEqual(env.pages.personCalls.filter { $0 == "an|false" }.count, 1)
        XCTAssertEqual(env.state.boardMembers.count, 2)

        _ = await groups.delete(id: "g1")
        await env.wait { env.state.taskTeam == nil }
        XCTAssertNil(env.state.taskTeam)
    }

    // MARK: Derived values are worked out once per change

    func testTheBoardIsBuiltOnceHoweverManyViewsAskAndAgainWhenAnInputChanges() async {
        let env = await env()
        env.state.openExecution(env.execution("e1", "Sprint 1"))
        env.pages.script = ["wait": [boardTask("4", execution: "e1", assignee: "an")], "doing": [boardTask("1", execution: "e1", providerStatus: "doing", status: .inprogress, assignee: "an")]]
        env.state.reopenTaskStreams()
        await env.wait { env.state.taskBoard.scoped.count == 2 }
        let cache = env.state.taskCache
        let before = cache.builds
        // The columns, the header's count, the bulk bar, the people strip and the chips all ask on one redraw.
        for _ in 0..<20 {
            _ = ZentaoBoards.taskBoard(env.state); _ = env.state.shownTickets(bugs: false)
            _ = env.state.workload(bugs: false); _ = env.state.quickCounts(bugs: false); _ = env.state.leaderPool(bugs: false)
        }
        XCTAssertEqual(cache.builds - before, 4, "board, pool, workload and counts: once each")
        // A chip is an input: everything is worked out again, once.
        env.state.updateLeader(bugs: false) { $0.quick = [.unassigned] }
        let afterChip = cache.builds
        for _ in 0..<5 { _ = ZentaoBoards.taskBoard(env.state); _ = env.state.quickCounts(bugs: false) }
        XCTAssertEqual(cache.builds - afterChip, 3, "board, counts and the pool they narrow")
        XCTAssertEqual(ZentaoBoards.taskBoard(env.state).total, 0)
        // And so is the order of the cards.
        env.state.updateLeader(bugs: false) { $0.quick = [] }
        env.state.columnSort = .deadline
        let afterSort = cache.builds
        _ = ZentaoBoards.taskBoard(env.state); _ = ZentaoBoards.taskBoard(env.state)
        XCTAssertEqual(cache.builds - afterSort, 1)
        XCTAssertEqual(ZentaoBoards.taskBoard(env.state).total, 2)
    }

    /// 5 000 tickets through every chip count and the workload: one pass each, well inside a frame or two.
    func testCountingManyTicketsIsQuick() {
        let today = AppDateFormatBridge.iso(Date())
        let many = (0..<5_000).map { i in
            boardTask("\(i)", providerStatus: i % 3 == 0 ? "doing" : "wait", status: i % 3 == 0 ? .inprogress : .todo, deadline: i % 4 == 0 ? today : nil,
                      assignee: ["an", "binh", "chi", nil][i % 4])
        }
        let started = Date()
        let counts = CountQuickFilters()(many)
        let load = SummarizeWorkload()(many)
        let took = Date().timeIntervalSince(started)
        XCTAssertEqual(counts[.unassigned], 1_250)
        XCTAssertEqual(load.reduce(0) { $0 + $1.open }, 5_000)
        XCTAssertLessThan(took, 0.5, "took \(took)s")
    }
}
