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

    func testAnAppTheDockKnowsUnderAnotherPathIsFoundByItsBundleId() async throws {
        let h = try NativeHarness()
        let app = native("discord", path: "/Volumes/Data/Applications/Discord.app")
        await h.seed([app])
        h.dock.byPath = ["/Applications/Discord.app": "274", DockBadgeKey.bundle(app.bundleId): "274"]
        h.model.refreshBadges()
        XCTAssertEqual(h.model.railItems.first?.badge, "274")
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

    func testTheBadgesAreOfferedOnceAndAgainWhenAccessThatWorkedIsLost() async throws {
        let h = try NativeHarness()
        h.dock.isAllowed = false
        h.model.refreshBadges()
        XCTAssertNil(h.model.badgeOffer, "nothing to show a badge on yet")
        await h.seed([native("discord", path: "/Applications/Discord.app")])
        h.model.refreshBadges()
        XCTAssertEqual(h.model.badgeOffer, .first)
        h.model.declineBadgeOffer()
        h.model.refreshBadges()
        XCTAssertNil(h.model.badgeOffer, "turned down: not asked again")
        XCTAssertTrue(h.offers.declined)

        // Allowed later from the settings card: System Settings opens, and once macOS trusts the app the badges show.
        h.model.requestBadgeAccess()
        XCTAssertEqual(h.dock.asked, 1); XCTAssertEqual(h.dock.opened, 1)
        h.dock.isAllowed = true
        h.model.refreshBadges()
        XCTAssertNil(h.model.badgeOffer)
        XCTAssertTrue(h.offers.wasAllowed)

        // An update of an unsigned build loses the access: said again, as lost, even though the offer was answered.
        h.dock.isAllowed = false
        h.model.refreshBadges()
        XCTAssertEqual(h.model.badgeOffer, .lost)
        h.model.declineBadgeOffer()
        h.model.refreshBadges()
        XCTAssertNil(h.model.badgeOffer)
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
