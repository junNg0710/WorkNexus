import CoreDomain
import CoreTools
import CoreUI
import XCTest
@testable import SharedKit

/// A second click on the rail button of the place on screen folds that place's side panel away; the next brings it back.
@MainActor
final class RailPaneToggleTests: XCTestCase {
    /// The clicks here are deliberate ones, however close together the test makes them: no repeat is dropped, except
    /// where a test is about that.
    override func setUp() { super.setUp(); ShellModel.railRepeat = 0 }
    override func tearDown() { ShellModel.railRepeat = TapGuard.defaultCooldown; super.tearDown() }

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

    /// Folding a mini app's bars takes the title bar along, on a mini app only: every other place keeps it.
    func testTheTitleBarFoldsAwayOnlyOverAMiniAppWithItsBarsCollapsed() {
        let s = shell()
        s.nav.openMiniApp("gitlab"); XCTAssertFalse(s.titleBarHidden, "the bars come open")
        s.updateSettings { $0.miniAppBarsCollapsed = true }
        XCTAssertTrue(s.titleBarHidden)
        s.nav.openMiniApp(nil); XCTAssertFalse(s.titleBarHidden, "Chat, the boards and Settings keep their title bar")
        s.nav.select(.settings); XCTAssertFalse(s.titleBarHidden)
        s.nav.openMiniApp("jenkins"); XCTAssertTrue(s.titleBarHidden, "the choice is one for every mini app")
        s.updateSettings { $0.miniAppBarsCollapsed = false }
        XCTAssertFalse(s.titleBarHidden)
    }

    func testTheSecondClickFoldsThePaneAndTheThirdBringsItBack() {
        let s = shell()
        var went = 0
        s.nav.select(.settings)
        // A click on another place goes there and folds nothing.
        s.railTap("place", isCurrent: false) { went += 1; s.nav.select(.workspace) }
        XCTAssertEqual(went, 1)
        XCTAssertFalse(s.currentPaneFolded)
        XCTAssertTrue(ToolPaneHost.isVisible(s))
        // A click on the place on screen folds its pane, and does not navigate.
        s.railTap("place", isCurrent: true) { went += 1 }
        XCTAssertEqual(went, 1)
        XCTAssertTrue(s.currentPaneFolded)
        XCTAssertFalse(ToolPaneHost.isVisible(s), "a folded pane takes no room")
        s.railTap("place", isCurrent: true) { went += 1 }
        XCTAssertFalse(s.currentPaneFolded)
        XCTAssertTrue(ToolPaneHost.isVisible(s))
    }

    /// The notifications panel lies over the place: a rail click puts it away.
    func testARailClickPutsTheNotificationsPanelAway() {
        let s = shell()
        var panelOpen = true, went = 0
        s.host.dismissOverlay = { if panelOpen { panelOpen = false; return true } else { return false } }
        s.nav.select(.settings)
        s.railTap("place", isCurrent: false) { went += 1; s.nav.select(.workspace) }
        XCTAssertFalse(panelOpen, "going to another place closes the panel")
        XCTAssertEqual(went, 1)

        // On the place the panel lies over, the click closes the panel and folds nothing; the next one folds the pane.
        panelOpen = true
        s.railTap("place", isCurrent: true) { went += 1 }
        XCTAssertFalse(panelOpen)
        XCTAssertFalse(s.currentPaneFolded, "the pane is not folded behind the panel")
        XCTAssertEqual(went, 1)
        s.railTap("place", isCurrent: true) { went += 1 }
        XCTAssertTrue(s.currentPaneFolded)
    }

    /// A rail click is answered at once, however fast the clicks come: none waits for the one behind it.
    func testEveryRailClickIsAnsweredAtOnce() {
        let s = shell()
        s.nav.select(.settings)
        var went: [String] = []
        s.railTap("workspace", isCurrent: false) { went.append("workspace") }
        s.railTap("chat", isCurrent: false) { went.append("chat") }
        XCTAssertEqual(went, ["workspace", "chat"])
    }

    /// A double click goes to the place once: the second click is not taken for "fold the pane of the place on screen".
    func testARepeatedClickOnTheSameRailButtonIsDropped() async throws {
        ShellModel.railRepeat = 0.08
        defer { ShellModel.railRepeat = TapGuard.defaultCooldown }
        let s = shell()
        s.nav.select(.settings)
        var went = 0
        s.railTap("workspace", isCurrent: false) { went += 1; s.nav.select(.workspace) }
        s.railTap("workspace", isCurrent: true) { went += 1 }
        XCTAssertEqual(went, 1)
        XCTAssertFalse(s.currentPaneFolded, "the second click of a double click folds nothing")
        // A deliberate second click, a moment later, does fold it.
        try await Task.sleep(for: .milliseconds(200))
        s.railTap("workspace", isCurrent: true) { went += 1 }
        XCTAssertEqual(went, 1)
        XCTAssertTrue(s.currentPaneFolded)
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
        s.railTap("place", isCurrent: true) { went += 1 }
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
        s.railTap("place", isCurrent: true) { went += 1 }
        XCTAssertEqual(went, 1, "it only shows the place")
        XCTAssertEqual(s.currentPaneFolded, folded)
        // A second click a moment later folds it as usual.
        s.railTap("place", isCurrent: true, now: Date().addingTimeInterval(ShellModel.activationGrace + 0.1)) { went += 1 }
        XCTAssertEqual(went, 1)
        XCTAssertNotEqual(s.currentPaneFolded, folded)
    }
}
