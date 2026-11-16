import CoreDomain
import CoreTools
import XCTest
@testable import SharedKit

/// A second click on the rail button of the place on screen folds that place's side panel away; the next brings it back.
@MainActor
final class RailPaneToggleTests: XCTestCase {
    private func shell() -> ShellModel {
        let fake = FakeStore()
        let services = AppServices(tickets: fake, workspaces: fake, comments: fake, activity: fake, syncStatus: SyncTests.RecordingStatus(),
                                   settings: BoardControllerTests.FakeSettings(), credentials: fake, sync: BoardControllerTests.NoopSync(),
                                   ticketDetail: BoardControllerTests.NoopSync(), adapters: FakeRegistry())
        return ShellModel(services: services, registry: ToolRegistry())
    }

    func testTheSecondClickFoldsThePaneAndTheThirdBringsItBack() {
        let s = shell()
        var went = 0
        s.nav.select(.settings)
        // A click on another place goes there and folds nothing.
        s.railTap(isCurrent: false) { went += 1; s.nav.select(.workspace) }
        XCTAssertEqual(went, 1)
        XCTAssertFalse(s.currentPaneFolded)
        XCTAssertTrue(ToolPaneHost.isVisible(s))
        // A click on the place on screen folds its pane, and does not navigate.
        s.railTap(isCurrent: true) { went += 1 }
        XCTAssertEqual(went, 1)
        XCTAssertTrue(s.currentPaneFolded)
        XCTAssertFalse(ToolPaneHost.isVisible(s), "a folded pane takes no room")
        s.railTap(isCurrent: true) { went += 1 }
        XCTAssertFalse(s.currentPaneFolded)
        XCTAssertTrue(ToolPaneHost.isVisible(s))
    }

    func testEachPlaceFoldsOnItsOwnAndASectionHasItsOwnPane() {
        let s = shell()
        s.nav.select(.workspace)
        s.toggleCurrentPane()
        s.nav.select(.settings)
        XCTAssertFalse(s.currentPaneFolded, "settings is not folded because the dashboard is")
        s.nav.select(.workspace)
        XCTAssertTrue(s.currentPaneFolded, "and the dashboard is still folded on coming back")
        s.nav.select(.account("zt"))
        s.nav.setSection("tasks", accountId: "zt")
        XCTAssertEqual(s.currentPaneKey, AppNavController.paneKey("zt", "tasks"))
        s.toggleCurrentPane()
        s.nav.setSection("bugs", accountId: "zt")
        XCTAssertFalse(s.currentPaneFolded)
    }

    func testWithAMiniAppOnScreenAClickGoesToThePlace() {
        let s = shell()
        s.nav.select(.workspace)
        s.nav.openMiniApp("jenkins")
        var went = 0
        // The rail still says "workspace", but the mini app is what is on screen: the click leaves it for the dashboard.
        s.railTap(isCurrent: true) { went += 1 }
        XCTAssertEqual(went, 1)
        XCTAssertFalse(s.currentPaneFolded)
    }

    func testTheTooltipSaysWhatTheSecondClickDoes() {
        XCTAssertEqual(RailTips.place("Tasks", current: false, folded: false), "Tasks")
        XCTAssertTrue(RailTips.place("Tasks", current: true, folded: false).contains("hide"))
        XCTAssertTrue(RailTips.place("Tasks", current: true, folded: true).contains("show"))
    }
}
