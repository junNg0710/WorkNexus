import CoreDomain
import CoreTools
import CoreUI
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

    /// The title bar's search shows only where it has something to search.
    func testTheGlobalSearchShowsOnlyWhereThereIsSomethingToSearch() {
        let s = shell()
        s.nav.select(.workspace); XCTAssertTrue(s.showsGlobalSearch)
        s.nav.select(.chat); XCTAssertTrue(s.showsGlobalSearch)
        s.nav.openMiniApp("gitlab"); XCTAssertFalse(s.showsGlobalSearch, "a mini app is a web page with its own search")
        s.nav.openMiniApp(nil); XCTAssertTrue(s.showsGlobalSearch)
        s.nav.openEditor(.newBug(accountId: "zt1")); XCTAssertFalse(s.showsGlobalSearch)
        s.nav.select(.settings); XCTAssertFalse(s.showsGlobalSearch)
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

    /// Clicked through faster than the places can be shown: only where the user ended up is built.
    func testAPlaceIsNotBuiltWhileAnotherRailClickWaits() async throws {
        let s = shell()
        var behind = true
        s.railGate = CatchUpGate(recheck: 0.01) { behind }
        s.nav.select(.settings)
        var went: [String] = []
        s.railTap(isCurrent: false) { went.append("workspace") }
        s.railTap(isCurrent: false) { went.append("chat") }
        XCTAssertEqual(went, [])
        behind = false
        try await Task.sleep(for: .milliseconds(120))
        XCTAssertEqual(went, ["chat"])
    }

    func testComingBackToThePlaceOnScreenDropsThePlaceAskedForAndFoldsNothing() async throws {
        let s = shell()
        var behind = true
        s.railGate = CatchUpGate(recheck: 0.01) { behind }
        s.nav.select(.settings)
        var went = 0
        s.railTap(isCurrent: false) { went += 1 }
        s.railTap(isCurrent: true) { went += 1 }
        behind = false
        try await Task.sleep(for: .milliseconds(120))
        XCTAssertEqual(went, 0)
        XCTAssertFalse(s.currentPaneFolded)
    }

    /// The chat's accounts are switched at the top of its own list: no column beside it, however many accounts there are.
    func testTheChatHasNoPaneOfItsOwn() {
        let s = shell()
        s.nav.select(.chat)
        XCTAssertFalse(ToolPaneHost.isVisible(s))
        s.nav.select(.workspace)
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

    /// Clicking Chat in the rail from another app brings WorkNexus back and shows Chat; it does not fold the chat list.
    func testTheClickThatBringsTheAppBackDoesNotFoldThePane() {
        let s = shell()
        s.nav.select(.chat)
        let folded = s.currentPaneFolded
        s.activatedAt = Date()
        var went = 0
        s.railTap(isCurrent: true) { went += 1 }
        XCTAssertEqual(went, 1, "it only shows the place")
        XCTAssertEqual(s.currentPaneFolded, folded)
        // A second click a moment later folds it as usual.
        s.railTap(isCurrent: true, now: Date().addingTimeInterval(ShellModel.activationGrace + 0.1)) { went += 1 }
        XCTAssertEqual(went, 1)
        XCTAssertNotEqual(s.currentPaneFolded, folded)
    }
}
