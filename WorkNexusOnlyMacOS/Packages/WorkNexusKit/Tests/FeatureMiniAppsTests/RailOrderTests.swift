import CoreDomain
import CorePersistence
import GRDB
import XCTest
@testable import FeatureMiniApps

/// A `RailOrderRepository` in memory, for the use cases.
private actor FakeRailOrder: RailOrderRepository {
    private(set) var saved: [[RailAppRef]] = []
    var next: Outcome<Int> = .success(0)
    var failing = false
    func saveOrder(_ refs: [RailAppRef]) async -> Outcome<Void> {
        if failing { return .failure(.storage("nope")) }
        saved.append(refs); return .success(())
    }
    func nextPosition() async -> Outcome<Int> { next }
    func setNext(_ value: Outcome<Int>) { next = value }
    func setFailing() { failing = true }
}

private let a = RailAppRef.miniApp("a"), b = RailAppRef.miniApp("b"), slack = RailAppRef.nativeApp("slack"), xcode = RailAppRef.nativeApp("xcode")

// MARK: The one order of the websites and the Mac apps

final class RailOrderUseCaseTests: XCTestCase {
    func testAPlaceIdNamesTheKindAndTheAppAndReadsBack() {
        XCTAssertEqual(a.id, "miniapp:a"); XCTAssertEqual(slack.id, "macapp:slack")
        XCTAssertEqual(RailAppRef(placeId: "miniapp:a"), a); XCTAssertEqual(RailAppRef(placeId: "macapp:slack"), slack)
        XCTAssertEqual(RailAppRef(placeId: "miniapp:a:b")?.appId, "a:b", "only the first colon splits")
        for junk in ["", "a", "miniapp:", "native:slack", "https://x.io", "account:1"] { XCTAssertNil(RailAppRef(placeId: junk), junk) }
        XCTAssertNotEqual(RailAppRef.miniApp("x"), RailAppRef.nativeApp("x"), "the same id in both tables is two places")
    }

    func testTheRailIsOneListByPositionWhateverTheKind() {
        let order = OrderRailApps()(miniApps: [app("a", position: 0), app("b", position: 3)],
                                    nativeApps: [native("slack", position: 1), native("xcode", position: 2)])
        XCTAssertEqual(order, [a, slack, xcode, b], "a Mac app sits between two websites")
        XCTAssertEqual(OrderRailApps()(miniApps: [], nativeApps: []), [])
    }

    func testTheSamePositionKeepsWebsitesFirstAndEachKindAsGiven() {
        // What an install had before the kinds shared an order, were the migration not to run: both count from 0.
        let order = OrderRailApps()(miniApps: [app("a", position: 0), app("b", position: 0)],
                                    nativeApps: [native("slack", position: 0), native("xcode", position: 1)])
        XCTAssertEqual(order, [a, b, slack, xcode])
    }

    func testMoveReordersAcrossKindsAndKeepsTheOrder() async throws {
        let repo = FakeRailOrder()
        let moved = try await MoveRailApp(repo)([a, b, slack, xcode], from: 2, to: 0).get()
        XCTAssertEqual(moved, [slack, a, b, xcode], "the Mac app goes above both websites")
        let back = try await MoveRailApp(repo)(moved, from: 0, to: 3).get()
        XCTAssertEqual(back, [a, b, xcode, slack])
        let saved = await repo.saved
        XCTAssertEqual(saved, [moved, back])
    }

    func testMoveGoingNowhereOrOutOfRangeTouchesNothing() async throws {
        let repo = FakeRailOrder()
        for (from, to) in [(0, 0), (-1, 1), (0, 2), (5, 0), (0, -1)] {
            let result = try await MoveRailApp(repo)([a, slack], from: from, to: to).get()
            XCTAssertEqual(result, [a, slack], "\(from)→\(to)")
        }
        let saved = await repo.saved
        XCTAssertTrue(saved.isEmpty)
    }

    func testAMoveThatCannotBeKeptFails() async {
        let repo = FakeRailOrder(); await repo.setFailing()
        let result = await MoveRailApp(repo)([a, slack], from: 0, to: 1)
        XCTAssertNil(result.value)
    }

    func testANewWebsiteGoesAfterTheMacAppsToo() async {
        let repo = FakeMiniAppRepo(), order = FakeRailOrder(); await order.setNext(.success(7))
        let added = await AddMiniApp(repo, RefreshMiniAppIcon(repo), order: order)(url: "x.io", existing: [app("a", position: 1)])
        XCTAssertEqual(added.value?.position, 7)
        // The order cannot be read: after the websites it knows of.
        await order.setNext(.failure(.storage("nope")))
        let fallback = await AddMiniApp(repo, RefreshMiniAppIcon(repo), order: order)(url: "y.io", existing: [app("a", position: 1)])
        XCTAssertEqual(fallback.value?.position, 2)
    }

    func testANewMacAppGoesAfterTheWebsitesToo() async throws {
        let dir = nativeTempDir(); defer { try? FileManager.default.removeItem(at: dir) }
        let path = try makeFixtureApp(in: dir, file: "Slack", bundleId: "com.slack")
        let order = FakeRailOrder(); await order.setNext(.success(4))
        let added = try await AddNativeApp(FixtureNativeRepository(), PlistAppBundleReader(), order: order)(path: path, existing: []).get()
        XCTAssertEqual(added.position, 4)
    }
}

// MARK: Database: the migration and the repository

final class RailOrderDatabaseTests: XCTestCase {
    private func database() throws -> AppDatabase { try AppDatabase.inMemory(registrars: [MiniAppsMigrations.registrar]) }

    private func railOrder(_ db: AppDatabase) async -> [RailAppRef] {
        var sites = GRDBMiniAppRepository(database: db, icons: MiniAppIconStorage(folder: nativeTempDir())).watchAll().makeAsyncIterator()
        var macApps = GRDBNativeAppRepository(database: db).watchAll().makeAsyncIterator()
        return OrderRailApps()(miniApps: await sites.next() ?? [], nativeApps: await macApps.next() ?? [])
    }

    /// A database as a build before the shared order left it (`miniapps_v4`), with `sites` and `macApps` at these positions.
    private func legacy(sites: [(String, Int)], macApps: [(String, Int)]) throws -> DatabaseQueue {
        let queue = try DatabaseQueue()
        var migrator = DatabaseMigrator()
        MiniAppsMigrations.registrar(&migrator)
        try migrator.migrate(queue, upTo: MiniAppsMigrations.nativeAppLooksMigrationId)
        try queue.write { db in
            for (id, position) in sites {
                try db.execute(sql: "INSERT INTO miniApps (id, name, url, position) VALUES (?, ?, 'https://x.io', ?)", arguments: [id, id, position])
            }
            for (id, position) in macApps {
                try db.execute(sql: "INSERT INTO nativeApps (id, name, bundleId, path, position) VALUES (?, ?, ?, '/x.app', ?)",
                               arguments: [id, id, "com.test.\(id)", position])
            }
        }
        return queue
    }

    func testAnExistingInstallKeepsWebsitesThenMacApps() async throws {
        // Each kind counted from 0, and the websites have a gap where one was removed.
        let queue = try legacy(sites: [("a", 0), ("b", 1), ("c", 4)], macApps: [("xcode", 1), ("slack", 0)])
        let db = try AppDatabase(writer: queue, registrars: [MiniAppsMigrations.registrar])
        let order = await railOrder(db)
        XCTAssertEqual(order, [a, b, .miniApp("c"), slack, xcode], "what the rail showed: the websites, then the Mac apps, each in its order")
        let positions = try await queue.read { try Int.fetchAll($0, sql: "SELECT position FROM nativeApps ORDER BY position") }
        XCTAssertEqual(positions, [5, 6], "past the last website")
        let sites = try await queue.read { try Int.fetchAll($0, sql: "SELECT position FROM miniApps ORDER BY position") }
        XCTAssertEqual(sites, [0, 1, 4], "the websites are left as they were")
    }

    func testTheMigrationRunsOnceAndLeavesALaterOrderAlone() async throws {
        let queue = try legacy(sites: [("a", 0), ("b", 1)], macApps: [("slack", 0)])
        var db = try AppDatabase(writer: queue, registrars: [MiniAppsMigrations.registrar])
        _ = await GRDBRailOrderRepository(database: db).saveOrder([a, slack, b])
        // The next launch.
        db = try AppDatabase(writer: queue, registrars: [MiniAppsMigrations.registrar])
        let order = await railOrder(db)
        XCTAssertEqual(order, [a, slack, b])
    }

    func testMacAppsAloneOrWebsitesAloneAreLeftInTheirOrder() async throws {
        let onlyApps = try AppDatabase(writer: try legacy(sites: [], macApps: [("slack", 0), ("xcode", 1)]), registrars: [MiniAppsMigrations.registrar])
        let apps = await railOrder(onlyApps)
        XCTAssertEqual(apps, [slack, xcode])
        let onlySites = try AppDatabase(writer: try legacy(sites: [("b", 0), ("a", 1)], macApps: []), registrars: [MiniAppsMigrations.registrar])
        let sites = await railOrder(onlySites)
        XCTAssertEqual(sites, [b, a])
    }

    func testSaveOrderNumbersBothTablesInOneSequence() async throws {
        let db = try database()
        let sites = GRDBMiniAppRepository(database: db, icons: MiniAppIconStorage(folder: nativeTempDir())), macApps = GRDBNativeAppRepository(database: db)
        _ = await sites.save(app("a", position: 0)); _ = await sites.save(app("b", position: 1))
        _ = await macApps.save(native("slack", position: 2)); _ = await macApps.save(native("xcode", position: 3))
        let repo = GRDBRailOrderRepository(database: db)
        let saved = await repo.saveOrder([slack, a, xcode, b])
        XCTAssertNotNil(saved.value)
        let order = await railOrder(db)
        XCTAssertEqual(order, [slack, a, xcode, b])
        let sitePositions = try await db.writer.read { try Row.fetchAll($0, sql: "SELECT id, position FROM miniApps ORDER BY id").map { "\($0["id"] as String)=\($0["position"] as Int)" } }
        let appPositions = try await db.writer.read { try Row.fetchAll($0, sql: "SELECT id, position FROM nativeApps ORDER BY id").map { "\($0["id"] as String)=\($0["position"] as Int)" } }
        XCTAssertEqual(sitePositions, ["a=1", "b=3"]); XCTAssertEqual(appPositions, ["slack=0", "xcode=2"])
        // Nothing but the positions.
        var it = sites.watchAll().makeAsyncIterator()
        let kept = await it.next()
        XCTAssertEqual(kept?.map(\.name), ["A", "B"])
    }

    func testTheNextPositionIsPastTheLastOfEitherKind() async throws {
        let db = try database(), repo = GRDBRailOrderRepository(database: db)
        let empty = await repo.nextPosition().value
        XCTAssertEqual(empty, 0)
        _ = await GRDBMiniAppRepository(database: db, icons: MiniAppIconStorage(folder: nativeTempDir())).save(app("a", position: 2))
        let afterSite = await repo.nextPosition().value
        XCTAssertEqual(afterSite, 3)
        _ = await GRDBNativeAppRepository(database: db).save(native("slack", position: 6))
        let afterApp = await repo.nextPosition().value
        XCTAssertEqual(afterApp, 7)
    }
}

// MARK: The rail's model

/// The feature's own rail model over an in-memory database, with Mac apps that launch nothing.
@MainActor
struct RailHarness {
    let sites: Harness
    let macApps: NativeAppsModel
    let model: RailAppsModel
    let macAppRepository: GRDBNativeAppRepository
    let launcher = FakeLauncher()

    init() async throws {
        sites = try await Harness()
        macAppRepository = GRDBNativeAppRepository(database: sites.db)
        let order = GRDBRailOrderRepository(database: sites.db)
        macApps = NativeAppsModel(repository: macAppRepository, add: AddNativeApp(macAppRepository, PlistAppBundleReader(), order: order),
                                  remove: RemoveNativeApp(macAppRepository), installed: FixtureInstalled(apps: []), launcher: launcher,
                                  dock: FakeDock(), offerMemory: InMemoryBadgeOfferMemory())
        model = RailAppsModel(miniApps: sites.model, nativeApps: macApps, move: MoveRailApp(order))
    }

    func seed(sites apps: [MiniApp], macApps list: [NativeApp]) async {
        for app in list { _ = await macAppRepository.save(app) }
        await sites.seed(apps)
        macApps.start()
        await sites.settle { macApps.apps.count == list.count }
    }

    /// The order as the database has it: what the next launch shows.
    func kept() async -> [RailAppRef] {
        var s = sites.feature.apps.watchAll().makeAsyncIterator(), m = macAppRepository.watchAll().makeAsyncIterator()
        return OrderRailApps()(miniApps: await s.next() ?? [], nativeApps: await m.next() ?? [])
    }
}

@MainActor
final class RailAppsModelTests: XCTestCase {
    private func seeded() async throws -> RailHarness {
        let rail = try await RailHarness()
        await rail.seed(sites: [app("a", "https://a.io", position: 0), app("b", "https://b.io", position: 1)],
                        macApps: [native("slack", position: 2), native("xcode", position: 3)])
        return rail
    }

    func testTheItemsAreTheButtonsOfBothKindsInRailOrder() async throws {
        let rail = try await seeded()
        XCTAssertEqual(rail.model.order, [a, b, slack, xcode])
        XCTAssertEqual(rail.model.items.map(\.id), ["miniapp:a", "miniapp:b", "macapp:slack", "macapp:xcode"])
        XCTAssertEqual(rail.model.items.map(\.name), ["A", "B", "Slack", "Xcode"])
        rail.sites.model.show("b")
        guard case .miniApp(let shown) = rail.model.items[1] else { return XCTFail("a website") }
        XCTAssertTrue(shown.selected && shown.running, "each button is its own model's")
    }

    func testAStepUpOrDownGoesPastTheOtherKind() async throws {
        let rail = try await seeded()
        await rail.model.move(slack, by: -1)
        XCTAssertEqual(rail.model.order, [a, slack, b, xcode], "a Mac app between two websites")
        await rail.model.move(a, by: 1)
        XCTAssertEqual(rail.model.order, [slack, a, b, xcode])
        await rail.model.move(b, by: 1)
        XCTAssertEqual(rail.model.order, [slack, a, xcode, b], "a website below a Mac app")
        let kept = await rail.kept()
        XCTAssertEqual(kept, [slack, a, xcode, b], "kept for the next launch")
        await rail.sites.settle { rail.model.order == [slack, a, xcode, b] }
        XCTAssertEqual(rail.model.order, [slack, a, xcode, b], "and still so once the database has answered")
    }

    func testTheEndsOfTheRailAreTheLimits() async throws {
        let rail = try await seeded()
        XCTAssertFalse(rail.model.canMove(a, by: -1)); XCTAssertTrue(rail.model.canMove(a, by: 1))
        XCTAssertTrue(rail.model.canMove(b, by: 1), "the last website is not the last of the rail")
        XCTAssertTrue(rail.model.canMove(slack, by: -1), "nor the first Mac app the first")
        XCTAssertFalse(rail.model.canMove(xcode, by: 1)); XCTAssertFalse(rail.model.canMove(.miniApp("zzz"), by: 1))
        await rail.model.move(a, by: -1); await rail.model.move(xcode, by: 1); await rail.model.move(.nativeApp("zzz"), by: 1)
        XCTAssertEqual(rail.model.order, [a, b, slack, xcode], "out of range changes nothing")
    }

    func testDroppedOnAnotherItTakesThatPlaceWhateverTheKind() async throws {
        let rail = try await seeded()
        await rail.model.move(xcode, onto: a)
        XCTAssertEqual(rail.model.order, [xcode, a, b, slack], "dragged up: it lands where the other was")
        await rail.model.move(xcode, onto: slack)
        XCTAssertEqual(rail.model.order, [a, b, slack, xcode], "dragged down to the last: it is the last")
        await rail.model.move(a, onto: slack)
        XCTAssertEqual(rail.model.order, [b, slack, a, xcode], "a website among the Mac apps")
        await rail.model.move(a, onto: a); await rail.model.move(.miniApp("zzz"), onto: a)
        XCTAssertEqual(rail.model.order, [b, slack, a, xcode])
    }

    func testADropTakesOnlyARailButtonsDrag() async throws {
        let rail = try await seeded()
        for payload in [nil, "", "https://x.io", "a", "native:slack", "miniapp:zzz", "miniapp:a"] {
            XCTAssertFalse(rail.model.drop(payload, onto: a), payload ?? "nil")
        }
        XCTAssertTrue(rail.model.drop("macapp:xcode", onto: a))
        await rail.sites.settle { rail.model.order.first == xcode }
        XCTAssertEqual(rail.model.order, [xcode, a, b, slack])
    }

    func testANewWebsiteOrMacAppGoesToTheEndOfTheRail() async throws {
        let rail = try await seeded()
        await rail.model.move(a, onto: xcode)                                   // b, slack, xcode, a
        let site = try await rail.sites.feature.addMiniApp(url: "new.io", existing: rail.sites.model.apps).get()
        await rail.sites.settle { rail.model.order.count == 5 }
        XCTAssertEqual(rail.model.order, [b, slack, xcode, a, .miniApp(site.id)])
        let dir = nativeTempDir(); defer { try? FileManager.default.removeItem(at: dir) }
        let added = try await rail.macApps.add(path: try makeFixtureApp(in: dir, file: "Notes", bundleId: "com.notes")).get()
        await rail.sites.settle { rail.model.order.count == 6 }
        XCTAssertEqual(rail.model.order.last, .nativeApp(added.id))
    }

    func testRemovingOneLeavesTheOthersWhereTheyAre() async throws {
        let rail = try await seeded()
        await rail.model.move(slack, by: -1)                                    // a, slack, b, xcode
        await rail.sites.model.remove("a")
        await rail.sites.settle { rail.model.order.count == 3 }
        XCTAssertEqual(rail.model.order, [slack, b, xcode])
        XCTAssertFalse(rail.model.canMove(slack, by: -1))
    }
}
