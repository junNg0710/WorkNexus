import CoreDomain
import CorePersistence
import GRDB
import XCTest
@testable import FeatureMiniApps

// MARK: Reading an .app bundle

final class PlistAppBundleReaderTests: XCTestCase {
    private var dir: URL!
    override func setUp() { dir = nativeTempDir() }
    override func tearDown() { try? FileManager.default.removeItem(at: dir) }
    private let reader = PlistAppBundleReader()

    func testReadsTheNameAndIdentifierFromTheInfoPlist() throws {
        let path = try makeFixtureApp(in: dir, file: "Slack", bundleId: "com.tinyspeck.slackmacgap", displayName: "Slack", bundleName: "Slack Core")
        let info = try reader.read(path: path).get()
        XCTAssertEqual(info, AppBundleInfo(name: "Slack", bundleId: "com.tinyspeck.slackmacgap", path: path, isBackground: false))
    }

    func testNameFallsBackFromDisplayNameToBundleNameToTheFileName() throws {
        let a = try makeFixtureApp(in: dir, file: "A", bundleId: "com.t.a", displayName: "  ", bundleName: "Bundle A")
        XCTAssertEqual(try reader.read(path: a).get().name, "Bundle A")
        let b = try makeFixtureApp(in: dir, file: "File Name", bundleId: "com.t.b")
        XCTAssertEqual(try reader.read(path: b).get().name, "File Name")
    }

    func testAgentsAreFlaggedAsBackground() throws {
        let ui = try makeFixtureApp(in: dir, file: "Agent", bundleId: "com.t.agent", extra: ["LSUIElement": true])
        let bg = try makeFixtureApp(in: dir, file: "Daemon", bundleId: "com.t.daemon", extra: ["LSBackgroundOnly": true])
        XCTAssertTrue(try reader.read(path: ui).get().isBackground)
        XCTAssertTrue(try reader.read(path: bg).get().isBackground)
    }

    func testRefusesAnythingThatIsNotAnApplicationBundle() throws {
        let noId = try makeFixtureApp(in: dir, file: "NoId", bundleId: nil)
        let framework = try makeFixtureApp(in: dir, file: "Framework", bundleId: "com.t.fw", packageType: "FMWK")
        let bare = dir.appendingPathComponent("Bare.app", isDirectory: true)
        try FileManager.default.createDirectory(at: bare, withIntermediateDirectories: true)
        let plainFile = dir.appendingPathComponent("File.app"); try Data("x".utf8).write(to: plainFile)
        let notApp = dir.appendingPathComponent("Folder", isDirectory: true)
        try FileManager.default.createDirectory(at: notApp, withIntermediateDirectories: true)
        let wrongExtension = dir.appendingPathComponent("Tool.bundle", isDirectory: true)
        try FileManager.default.createDirectory(at: wrongExtension.appendingPathComponent("Contents"), withIntermediateDirectories: true)
        for path in [noId, framework, bare.path, plainFile.path, notApp.path, wrongExtension.path, dir.appendingPathComponent("Missing.app").path] {
            guard case .failure(.parse) = reader.read(path: path) else { return XCTFail("accepted \(path)") }
        }
    }

    func testAcceptsAPathWithATrailingSlashOrDots() throws {
        let path = try makeFixtureApp(in: dir, file: "Figma", bundleId: "com.figma.Desktop")
        XCTAssertEqual(try reader.read(path: path + "/").get().path, path)
        XCTAssertEqual(try reader.read(path: dir.path + "/../" + dir.lastPathComponent + "/Figma.app").get().path, path)
    }
}

// MARK: Use cases

private final class NativeIdCounter: @unchecked Sendable {
    private let lock = NSLock(); private var n = 0
    func next() -> String { lock.lock(); defer { lock.unlock() }; n += 1; return "id\(n)" }
}

final class NativeAppUseCaseTests: XCTestCase {
    private var dir: URL!
    override func setUp() { dir = nativeTempDir() }
    override func tearDown() { try? FileManager.default.removeItem(at: dir) }

    private func add(_ repo: FixtureNativeRepository) -> AddNativeApp {
        let counter = NativeIdCounter()
        return AddNativeApp(repo, PlistAppBundleReader(), newId: { counter.next() })
    }

    func testAddsAtTheEndOfTheRailFromTheInfoPlist() async throws {
        let repo = FixtureNativeRepository()
        let notion = try makeFixtureApp(in: dir, file: "Notion", bundleId: "notion.id")
        let adding = add(repo)
        let first = try await adding(path: notion, existing: []).get()
        XCTAssertEqual(first, NativeApp(id: "id1", name: "Notion", bundleId: "notion.id", path: notion, position: 0))
        let figma = try makeFixtureApp(in: dir, file: "Figma", bundleId: "com.figma", displayName: "Figma")
        let second = try await adding(path: figma, existing: [first]).get()
        XCTAssertEqual(second.position, 1)
        XCTAssertEqual(repo.items.count, 2)
    }

    func testTheSameBundleIdentifierIsNotAddedTwice() async throws {
        let repo = FixtureNativeRepository()
        let path = try makeFixtureApp(in: dir, file: "Slack", bundleId: "com.slack")
        let kept = try await add(repo)(path: path, existing: []).get()
        let again = try await add(repo)(path: path, existing: [kept]).get()
        XCTAssertEqual(again, kept)
        XCTAssertEqual(repo.items, [kept], "nothing added or rewritten")
    }

    func testTheSameAppAtANewPlaceIsRelinkedNotDuplicated() async throws {
        let repo = FixtureNativeRepository()
        var old = native("slack", bundle: "com.slack", path: "/gone/Slack.app", position: 3)
        old.name = "Old name"
        repo.items = [old]
        let moved = try makeFixtureApp(in: dir, file: "Slack", bundleId: "com.slack", displayName: "Slack")
        let relinked = try await add(repo)(path: moved, existing: [old]).get()
        XCTAssertEqual(relinked, NativeApp(id: "slack", name: "Slack", bundleId: "com.slack", path: moved, position: 3))
        XCTAssertEqual(repo.items, [relinked])
    }

    func testRefusesANonAppPathAndKeepsNothing() async throws {
        let repo = FixtureNativeRepository()
        let folder = dir.appendingPathComponent("Docs", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let result = await add(repo)(path: folder.path, existing: [])
        guard case .failure(.parse) = result else { return XCTFail("\(result)") }
        XCTAssertTrue(repo.items.isEmpty)
    }

    func testAStorageFailureComesBack() async throws {
        let repo = FixtureNativeRepository(); repo.failing = true
        let path = try makeFixtureApp(in: dir, file: "Xcode", bundleId: "com.apple.dt.Xcode")
        guard case .failure(.storage) = await add(repo)(path: path, existing: []) else { return XCTFail("expected a storage failure") }
    }

    /// An empty name or the app's own goes back to the app's own; dropping the icon forgets its file.
    func testEditNamesTheAppAndSetsOrDropsItsIcon() async {
        let repo = FixtureNativeRepository()
        let app = native("jenkins")
        repo.items = [app]
        guard case .success(let named) = await EditNativeApp(repo)(app, name: "  CI build  ", iconPath: "/icons/jenkins.png") else { return XCTFail() }
        XCTAssertEqual(named.label, "CI build")
        XCTAssertEqual(named.name, "Jenkins", "the app's own name is kept")
        XCTAssertEqual(repo.items.first?.iconPath, "/icons/jenkins.png")
        guard case .success(let plain) = await EditNativeApp(repo)(named, name: "", iconPath: nil) else { return XCTFail() }
        XCTAssertNil(plain.customName)
        XCTAssertEqual(plain.label, "Jenkins")
        XCTAssertEqual(repo.deletedIcons, ["jenkins"])
        guard case .success(let same) = await EditNativeApp(repo)(plain, name: "Jenkins", iconPath: nil) else { return XCTFail() }
        XCTAssertNil(same.customName, "the app's own name is no custom name")
    }

    func testRemoveDeletes() async {
        let repo = FixtureNativeRepository(); repo.items = [native("a"), native("b", position: 1)]
        _ = await RemoveNativeApp(repo)(id: "a")
        XCTAssertEqual(repo.items.map(\.id), ["b"])
    }
}

// MARK: Repository (in-memory GRDB), scanner

final class GRDBNativeAppRepositoryTests: XCTestCase {
    private func repo() throws -> (GRDBNativeAppRepository, AppDatabase) {
        let db = try AppDatabase.inMemory(registrars: [MiniAppsMigrations.registrar])
        return (GRDBNativeAppRepository(database: db), db)
    }

    func testMigrationAddsTheTableAndKeepsV1() throws {
        let (_, db) = try repo()
        let tables = try db.writer.read { try String.fetchAll($0, sql: "SELECT name FROM sqlite_master WHERE type = 'table'") }
        XCTAssertTrue(tables.contains("nativeApps")); XCTAssertTrue(tables.contains("miniApps")); XCTAssertTrue(tables.contains("miniAppPermissions"))
        let applied = try db.writer.read { try String.fetchAll($0, sql: "SELECT identifier FROM grdb_migrations") }
        XCTAssertEqual(applied.filter { $0.hasPrefix("miniapps_") }, ["miniapps_v1", "miniapps_v2", "miniapps_v3", "miniapps_v4", "miniapps_v5"], "v1 is untouched, the rest follow it")
        XCTAssertEqual(MiniAppsMigrations.migrationId, "miniapps_v1")
    }

    func testSavesWatchesInOrderAndReplacesById() async throws {
        let (r, _) = try repo()
        _ = await r.save(native("b", position: 1)); _ = await r.save(native("a", position: 0))
        var it = r.watchAll().makeAsyncIterator()
        let first = await it.next()
        XCTAssertEqual(first?.map(\.id), ["a", "b"])
        var renamed = native("a", position: 5); renamed.name = "Renamed"; renamed.path = "/x/Renamed.app"
        _ = await r.save(renamed)
        var it2 = r.watchAll().makeAsyncIterator()
        let second = await it2.next()
        XCTAssertEqual(second, [native("b", position: 1), renamed])
    }

    func testSaveOrderAndDelete() async throws {
        let (r, db) = try repo()
        for (i, id) in ["a", "b", "c"].enumerated() { _ = await r.save(native(id, position: i)) }
        _ = await GRDBRailOrderRepository(database: db).saveOrder([.nativeApp("c"), .nativeApp("a"), .nativeApp("b")])
        _ = await r.delete(id: "a")
        var it = r.watchAll().makeAsyncIterator()
        let list = await it.next()
        XCTAssertEqual(list?.map(\.id), ["c", "b"])
        XCTAssertEqual(list?.map(\.position), [0, 2])
    }

    /// The name and icon the user gave a Mac app are kept with it; an icon picked is copied in, and forgotten with the app.
    func testKeepsTheNameAndIconGivenAndTheIconCopy() async throws {
        let db = try AppDatabase.inMemory(registrars: [MiniAppsMigrations.registrar])
        let dir = nativeTempDir(); defer { try? FileManager.default.removeItem(at: dir) }
        let r = GRDBNativeAppRepository(database: db, icons: MiniAppIconStorage(folder: dir.appendingPathComponent("icons")))
        let source = dir.appendingPathComponent("logo.png"); try Data([1, 2, 3]).write(to: source)
        guard case .success(let kept) = await r.importIcon(id: "a", sourcePath: source.path) else { return XCTFail("not copied") }
        XCTAssertTrue(FileManager.default.fileExists(atPath: kept))
        var app = native("a"); app.customName = "Build"; app.iconPath = kept
        _ = await r.save(app)
        var it = r.watchAll().makeAsyncIterator()
        let list = await it.next()
        XCTAssertEqual(list?.first?.label, "Build")
        XCTAssertEqual(list?.first?.iconPath, kept)
        await r.deleteIcon(id: "a")
        XCTAssertFalse(FileManager.default.fileExists(atPath: kept))
    }

    func testTwoRowsCannotShareABundleIdentifier() async throws {
        let (r, _) = try repo()
        _ = await r.save(native("a", bundle: "com.same"))
        guard case .failure(.storage) = await r.save(native("b", bundle: "com.same", position: 1)) else { return XCTFail("the duplicate was kept") }
    }
}

final class InstalledAppsScannerTests: XCTestCase {
    func testListsWindowedAppsByNameOneLevelDownWithoutDuplicates() throws {
        let dir = nativeTempDir(); defer { try? FileManager.default.removeItem(at: dir) }
        let apps = dir.appendingPathComponent("Applications"), home = dir.appendingPathComponent("Home")
        let utilities = apps.appendingPathComponent("Utilities"), deep = utilities.appendingPathComponent("Deep")
        for d in [apps, home, utilities, deep] { try FileManager.default.createDirectory(at: d, withIntermediateDirectories: true) }
        try makeFixtureApp(in: apps, file: "zed", bundleId: "com.zed")
        try makeFixtureApp(in: apps, file: "Alpha", bundleId: "com.alpha", displayName: "Alpha")
        try makeFixtureApp(in: utilities, file: "Terminal", bundleId: "com.terminal")
        try makeFixtureApp(in: deep, file: "TooDeep", bundleId: "com.deep")
        try makeFixtureApp(in: apps, file: "Menu Helper", bundleId: "com.helper", extra: ["LSUIElement": true])
        try makeFixtureApp(in: home, file: "Alpha Copy", bundleId: "com.alpha")
        try makeFixtureApp(in: home, file: "Broken", bundleId: nil)
        let found = InstalledAppsScanner.scan([apps, home, dir.appendingPathComponent("Nope")], PlistAppBundleReader())
        XCTAssertEqual(found.map(\.name), ["Alpha", "Terminal", "zed"])
    }
}

// MARK: Model

@MainActor
final class NativeAppsModelTests: XCTestCase {
    func testListsTheSavedAppsAndWhichOnesRun() async throws {
        let h = try NativeHarness()
        h.launcher.running = ["com.test.b"]
        await h.seed([native("a", position: 0), native("b", position: 1)])
        XCTAssertEqual(h.model.railItems.map(\.id), ["a", "b"])
        XCTAssertEqual(h.model.railItems.map(\.running), [false, true])
        XCTAssertEqual(h.model.railItems.map(\.missing), [false, false])
    }

    func testRunningFollowsLaunchAndQuitEvents() async throws {
        let h = try NativeHarness()
        await h.seed([native("a")])
        XCTAssertFalse(h.model.railItems[0].running)
        h.launcher.send(.launched("com.test.a"))
        await h.settle { h.model.railItems[0].running }
        XCTAssertTrue(h.model.railItems[0].running)
        h.launcher.send(.launched("com.other"))
        h.launcher.send(.terminated("com.test.a"))
        await h.settle { !h.model.railItems[0].running }
        XCTAssertFalse(h.model.railItems[0].running)
        XCTAssertEqual(h.model.runningBundleIds, ["com.other"])
    }

    func testLaunchAsksTheLauncherNotTheSystem() async throws {
        let h = try NativeHarness()
        await h.seed([native("a")])
        let result = await h.model.launch(h.model.apps[0])
        guard case .success = result else { return XCTFail("\(result)") }
        XCTAssertEqual(h.launcher.launched, ["com.test.a"])
    }

    func testALaunchFailureComesBack() async throws {
        let h = try NativeHarness()
        await h.seed([native("a")])
        h.launcher.launchResult = .failure(.unexpected("boom"))
        guard case .failure(.unexpected) = await h.model.launch(h.model.apps[0]) else { return XCTFail("expected the failure") }
    }

    func testAMissingAppIsMarkedAndNeverLaunched() async throws {
        let h = try NativeHarness()
        h.launcher.present = ["/Applications/A.app"]
        await h.seed([native("a", position: 0), native("b", position: 1)])
        XCTAssertEqual(h.model.railItems.map(\.missing), [false, true])
        guard case .failure(.notFound) = await h.model.launch(h.model.apps[1]) else { return XCTFail("expected notFound") }
        XCTAssertTrue(h.launcher.launched.isEmpty)
        // It comes back (or the user located it): the next check clears the mark.
        h.launcher.present = nil
        h.model.refreshMissing()
        XCTAssertEqual(h.model.railItems.map(\.missing), [false, false])
    }

    func testAddReadsTheBundleAndIsOnceOnly() async throws {
        let h = try NativeHarness(); defer { try? FileManager.default.removeItem(at: h.dir) }
        await h.seed([])
        let path = try makeFixtureApp(in: h.dir, file: "Figma", bundleId: "com.figma", displayName: "Figma")
        guard case .success(let app) = await h.model.add(path: path) else { return XCTFail("not added") }
        await h.settle { h.model.apps.count == 1 }
        XCTAssertEqual(h.model.apps.map(\.name), ["Figma"])
        XCTAssertTrue(h.model.isAdded("com.figma"))
        _ = await h.model.add(path: path)
        try await Task.sleep(for: .milliseconds(80))
        XCTAssertEqual(h.model.apps.map(\.id), [app.id])
        guard case .failure(.parse) = await h.model.add(path: h.dir.path) else { return XCTFail("a folder was added") }
    }

    func testLocatingAMissingAppPointsItAtTheNewPlace() async throws {
        let h = try NativeHarness(); defer { try? FileManager.default.removeItem(at: h.dir) }
        await h.seed([native("slack", bundle: "com.slack", path: "/gone/Slack.app")])
        let moved = try makeFixtureApp(in: h.dir, file: "Slack", bundleId: "com.slack")
        _ = await h.model.add(path: moved)
        await h.settle { h.model.apps.first?.path == moved }
        XCTAssertEqual(h.model.apps.map(\.path), [moved])
        XCTAssertEqual(h.model.apps.map(\.id), ["slack"])
    }

    func testRemoveTakesTheAppOffTheRail() async throws {
        let h = try NativeHarness()
        await h.seed([native("c", position: 0), native("b", position: 1), native("a", position: 2)])
        await h.model.remove("b")
        XCTAssertEqual(h.model.apps.map(\.id), ["c", "a"])
        await h.settle { h.model.apps.map(\.id) == ["c", "a"] }
    }

    func testRevealGoesThroughTheLauncher() async throws {
        let h = try NativeHarness()
        await h.seed([native("a")])
        h.model.reveal(h.model.apps[0])
        XCTAssertEqual(h.launcher.revealed, ["/Applications/A.app"])
    }

    func testLoadInstalledFillsTheListAndSearchFilters() async throws {
        let list = [AppBundleInfo(name: "Notion", bundleId: "n", path: "/Applications/Notion.app"),
                    AppBundleInfo(name: "Émile", bundleId: "e", path: "/Applications/Emile.app"),
                    AppBundleInfo(name: "Slack", bundleId: "s", path: "/Applications/Slack.app")]
        let h = try NativeHarness(installed: list)
        XCTAssertTrue(h.model.installed.isEmpty)
        await h.model.loadInstalled()
        XCTAssertEqual(h.model.installed, list)
        XCTAssertFalse(h.model.loadingInstalled)
        XCTAssertEqual(NativeAppPickerDialog.filter(list, "").count, 3)
        XCTAssertEqual(NativeAppPickerDialog.filter(list, " slA ").map(\.name), ["Slack"])
        XCTAssertEqual(NativeAppPickerDialog.filter(list, "emile").map(\.name), ["Émile"])
        XCTAssertTrue(NativeAppPickerDialog.filter(list, "zzz").isEmpty)
    }

    func testIconsAreKeptPerPath() throws {
        let h = try NativeHarness()
        let first = h.model.icon(forPath: "/Applications")
        XCTAssertTrue(first === h.model.icon(forPath: "/Applications"))
    }

    func testTheFeatureOwnsANativeModelOverTheSharedDatabase() async throws {
        let h = try await Harness()
        XCTAssertTrue(h.feature.nativeApps.apps.isEmpty)
        h.feature.nativeApps.start()
        let path = FileManager.default.temporaryDirectory.appendingPathComponent("feature_native_\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: path) }
        try FileManager.default.createDirectory(at: path, withIntermediateDirectories: true)
        let app = try makeFixtureApp(in: path, file: "Notion", bundleId: "notion.id")
        _ = await h.feature.nativeApps.add(path: app)
        await h.settle { h.feature.nativeApps.apps.count == 1 }
        XCTAssertEqual(h.feature.nativeApps.apps.map(\.bundleId), ["notion.id"])
        h.feature.nativeApps.stop()
    }
}
