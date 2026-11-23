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

    /// The read that comes round every few seconds asks the Dock without keeping the main thread, and shows the same.
    func testTheRegularReadDoesNotKeepTheMainThread() async throws {
        let h = try NativeHarness()
        await h.seed([native("discord", path: "/Applications/Discord.app", position: 0)])
        let before = h.dock.offMainReads
        h.dock.byPath = ["/Applications/Discord.app": "3"]
        await h.model.refreshBadgesOffMain()
        XCTAssertEqual(h.model.railItems.map(\.badge), ["3"])
        XCTAssertEqual(h.dock.offMainReads, before + 1)
        h.dock.isAllowed = false
        await h.model.refreshBadgesOffMain()
        XCTAssertEqual(h.model.railItems.map(\.badge), [nil], "not allowed: nothing is asked, nothing shows")
        XCTAssertEqual(h.dock.offMainReads, before + 1)
    }

    /// The pet hears about a badge going up - not about the badges already there when WorkNexus started, nor one going down.
    func testABadgeGoingUpIsToldNotTheOnesAlreadyThere() async throws {
        let h = try NativeHarness()
        await h.seed([native("slack", path: "/Applications/Slack.app", position: 0), native("mail", path: "/Applications/Mail.app", position: 1)])
        var told: [String] = []
        h.model.onBadgeRose = { app, badge in told.append("\(app.label) \(badge)") }
        h.dock.byPath = ["/Applications/Slack.app": "2"]
        h.model.refreshBadges()
        XCTAssertEqual(told, [], "there before: no news")
        h.dock.byPath = ["/Applications/Slack.app": "5", "/Applications/Mail.app": "•"]
        h.model.refreshBadges()
        XCTAssertEqual(told, ["Mail •", "Slack 5"])
        h.dock.byPath = ["/Applications/Slack.app": "1", "/Applications/Mail.app": "•"]
        h.model.refreshBadges()
        XCTAssertEqual(told.count, 2, "going down is no news")
    }

    func testRisenBadges() {
        XCTAssertEqual(RisenBadges.ids(old: ["a": "2", "b": "1"], new: ["a": "3", "b": "1", "c": "•"]), ["a", "c"])
        XCTAssertEqual(RisenBadges.ids(old: ["a": "9"], new: ["a": "10"]), ["a"])
        XCTAssertEqual(RisenBadges.ids(old: ["a": "•"], new: ["a": "•"]), [])
        XCTAssertEqual(RisenBadges.ids(old: [:], new: ["a": ""]), [])
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
