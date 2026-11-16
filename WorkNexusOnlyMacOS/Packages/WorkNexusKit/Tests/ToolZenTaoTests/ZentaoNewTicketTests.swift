import CoreDomain
import CoreTools
import SwiftUI
import XCTest
@testable import ToolZenTao

/// The "New bug" / "New task" routes open on the scope in view (header button, and the shell's "+" / Cmd-N), and the
/// Tasks pane's dead pins.
@MainActor
final class ZentaoNewTicketTests: XCTestCase {
    func testNewBugAndTaskRoutesCarryTheOpenProductAndExecution() async {
        let env = BoardsEnv(section: ZentaoSection.bugs)
        XCTAssertEqual(env.state.newBugRoute(accountId: "zt1"), .newBug(accountId: "zt1", productId: "0"), "nothing open: ZenTao's current product")
        XCTAssertEqual(env.state.newTaskRoute(accountId: "zt1"), .newTask(accountId: "zt1", executionId: "0"))
        env.state.openProduct(env.product("p7", "Chat"))
        XCTAssertEqual(env.state.newBugRoute(accountId: "zt1"), .newBug(accountId: "zt1", productId: "p7"))
        // Opening an execution is opening the Tasks board: the product is let go, the execution is the scope.
        env.state.openExecution(env.execution("e9", "Sprint 9"))
        XCTAssertEqual(env.state.newTaskRoute(accountId: "zt1"), .newTask(accountId: "zt1", executionId: "e9"))
        XCTAssertEqual(env.state.newBugRoute(accountId: "zt1"), .newBug(accountId: "zt1", productId: "0"))
        // Another account's open scope is not this one's.
        XCTAssertEqual(env.state.newBugRoute(accountId: "zt2"), .newBug(accountId: "zt2", productId: "0"))
        XCTAssertEqual(env.state.newTaskRoute(accountId: "zt2"), .newTask(accountId: "zt2", executionId: "0"))
    }

    func testThePanesDeadPinsAreThoseNoLoadedExecutionMatches() {
        func ex(_ id: String) -> ProviderExecution { ProviderExecution(id: id, name: "S\(id)", projectId: "p", accountId: "zt1") }
        let stale = ZentaoNavLogic.staleExecutionIds(open: ex("5"), pinned: ["zt1:1", "zt1:2", "zt2:3", "zt1:5", "zt1:2", "zt1:9"],
                                                     known: [ex("1")], accountId: "zt1")
        // 1 resolves; 5 is the open one; 3 is another account's; 2 repeats; 2 and 9 are gone.
        XCTAssertEqual(stale, ["2", "9"])
    }

    func testTheCelebrationHookIsANoOpUntilTheRootSetsIt() {
        var fired = 0
        var env = EnvironmentValues()
        env.zentaoCelebrate()                      // the default does nothing
        env.zentaoCelebrate = { fired += 1 }
        env.zentaoCelebrate(); env.zentaoCelebrate()
        XCTAssertEqual(fired, 2)
    }
}
