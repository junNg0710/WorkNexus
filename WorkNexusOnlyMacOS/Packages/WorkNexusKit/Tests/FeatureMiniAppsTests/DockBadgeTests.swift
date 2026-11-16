import CoreDomain
import XCTest
@testable import FeatureMiniApps

/// The Dock's badge of a Mac app shows on its rail button.
@MainActor
final class DockBadgeTests: XCTestCase {
    func testABadgeInTheDockShowsOnTheAppAndGoesWhenTheDockDropsIt() async throws {
        let h = try NativeHarness()
        await h.seed([native("discord", path: "/Applications/Discord.app", position: 0), native("trello", path: "/Applications/Trello.app", position: 1)])
        h.dock.byPath = ["/Applications/Discord.app": "274", "/Applications/Other.app": "9"]
        h.model.refreshBadges()
        XCTAssertEqual(h.model.railItems.map(\.badge), ["274", nil])
        XCTAssertEqual(h.model.railItems.map(\.badgeCount), [274, 0])
        XCTAssertTrue(h.model.badgesAllowed)
        h.dock.byPath = [:]
        h.model.refreshBadges()
        XCTAssertEqual(h.model.railItems.map(\.badgeCount), [0, 0])
    }

    func testWithoutAccessThereAreNoBadgesAndAccessCanBeAskedFor() async throws {
        let h = try NativeHarness()
        await h.seed([native("discord", path: "/Applications/Discord.app")])
        h.dock.byPath = ["/Applications/Discord.app": "3"]
        h.dock.isAllowed = false
        h.model.refreshBadges()
        XCTAssertFalse(h.model.badgesAllowed)
        XCTAssertNil(h.model.railItems.first?.badge)
        h.model.requestBadgeAccess()
        XCTAssertEqual(h.dock.asked, 1)
        h.dock.isAllowed = true
        h.model.refreshBadges()
        XCTAssertEqual(h.model.railItems.first?.badge, "3")
    }

    func testABadgeThatIsNotANumberCountsAsOne() {
        func item(_ badge: String?) -> NativeAppRailItem { NativeAppRailItem(id: "a", name: "A", path: "/A.app", running: true, missing: false, badge: badge) }
        XCTAssertEqual(item("•").badgeCount, 1)
        XCTAssertEqual(item("99+").badgeCount, 99)
        XCTAssertEqual(item("").badgeCount, 0)
        XCTAssertEqual(item(nil).badgeCount, 0)
        XCTAssertEqual(DockBadgeReader.normalized("/Applications/Discord.app/"), "/Applications/Discord.app")
    }
}
