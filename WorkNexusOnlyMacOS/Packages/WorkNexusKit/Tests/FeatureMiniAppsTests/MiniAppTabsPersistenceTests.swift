import CoreDomain
import CorePersistence
import GRDB
import XCTest
@testable import FeatureMiniApps

/// The tabs a mini app has open are kept and come back, with the one in front.
@MainActor
final class MiniAppTabsPersistenceTests: XCTestCase {
    private func database() throws -> AppDatabase { try AppDatabase.inMemory(registrars: [MiniAppsMigrations.registrar]) }

    private func repo(_ db: AppDatabase) -> GRDBMiniAppRepository {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("tabs_test_\(UUID().uuidString)")
        return GRDBMiniAppRepository(database: db, icons: MiniAppIconStorage(folder: dir), siteIcons: NoIcons())
    }
    private struct NoIcons: SiteIconSource { func fetch(_ page: URL) async -> SiteIcon? { nil } }

    func testTheTabListIsKeptWithTheAppAndEditingTheAppLeavesItAlone() async throws {
        let db = try database()
        let r = repo(db)
        _ = await r.save(app("a"))
        _ = await r.saveTabs(id: "a", urls: ["https://x.io/one", "https://x.io/two", "https://x.io/three"], selected: 2)
        var edited = app("a"); edited.name = "Renamed"      // an edit made from a copy that knows nothing of the tabs
        _ = await r.save(edited)
        var it = r.watchAll().makeAsyncIterator()
        let list = await it.next()
        XCTAssertEqual(list?.first?.name, "Renamed")
        XCTAssertEqual(list?.first?.openTabs, ["https://x.io/one", "https://x.io/two", "https://x.io/three"])
        XCTAssertEqual(list?.first?.selectedTab, 2)
        // Saving again replaces the list; deleting the app takes it along.
        _ = await r.saveTabs(id: "a", urls: ["https://x.io/only"], selected: 0)
        var again = r.watchAll().makeAsyncIterator()
        let replaced = await again.next()
        XCTAssertEqual(replaced?.first?.openTabs, ["https://x.io/only"])
        _ = await r.delete(id: "a")
        let left = try await db.writer.read { try Int.fetchOne($0, sql: "SELECT COUNT(*) FROM miniAppTabs") }
        XCTAssertEqual(left, 0)
    }

    func testRestoredTabsKeepTheirOrderAndOnlyTheOneInFrontHasAPage() {
        let tabs = MiniAppTabsModel(appId: "a", restoring: ["https://x.io/1", "https://x.io/2", "https://x.io/3"], selected: 1, apps: FakeMiniAppRepo())
        XCTAssertEqual(tabs.tabs.map(\.address), ["https://x.io/1", "https://x.io/2", "https://x.io/3"])
        XCTAssertEqual(tabs.selected.address, "https://x.io/2")
        XCTAssertEqual(tabs.tabs.map(\.activated), [false, true, false])
        // Showing a tab gives it its page.
        tabs.select(tabs.tabs[2].id)
        XCTAssertTrue(tabs.tabs[2].activated)
        XCTAssertEqual(tabs.snapshot.selected, 2)
        XCTAssertEqual(tabs.snapshot.urls.count, 3)
    }

    func testOpeningAndClosingTabsAreSaved() async throws {
        let repo = FakeMiniAppRepo()
        let tabs = MiniAppTabsModel(appId: "a", initialUrl: "https://x.io/1", apps: repo)
        tabs.newTab(url: "https://x.io/2")
        tabs.flush()                       // the app is closing: what is pending is written now
        try await Task.sleep(for: .milliseconds(100))
        var saves = await repo.tabSaves
        XCTAssertEqual(saves.last?.urls, ["https://x.io/1", "https://x.io/2"])
        XCTAssertEqual(saves.last?.selected, 1)
        tabs.close(tabs.tabs[1].id)
        tabs.flush()
        try await Task.sleep(for: .milliseconds(100))
        saves = await repo.tabSaves
        XCTAssertEqual(saves.last?.urls, ["https://x.io/1"])
    }

    func testAnAddressThatIsNotAWebPageIsNotKept() {
        let tabs = MiniAppTabsModel(appId: "a", initialUrl: "https://x.io/1", apps: FakeMiniAppRepo())
        tabs.newTab(url: "about:blank")
        XCTAssertEqual(tabs.snapshot.urls, ["https://x.io/1"])
    }
}
