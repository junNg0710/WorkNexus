import CoreDomain
import CorePersistence
import GRDB
import XCTest
@testable import FeatureMiniApps

private func tempDir() -> URL {
    let d = FileManager.default.temporaryDirectory.appendingPathComponent("miniapps_test_\(UUID().uuidString)")
    try? FileManager.default.createDirectory(at: d, withIntermediateDirectories: true)
    return d
}

private func database() throws -> AppDatabase { try AppDatabase.inMemory(registrars: [MiniAppsMigrations.registrar]) }

// MARK: local_mini_app_repository_test.dart, mini_app_permissions_test.dart (database half)

final class MiniAppRepositoryTests: XCTestCase {
    private var dir: URL!
    override func setUp() { dir = tempDir() }
    override func tearDown() { try? FileManager.default.removeItem(at: dir) }

    private struct StubIcons: SiteIconSource {
        var icon: SiteIcon?
        func fetch(_ page: URL) async -> SiteIcon? { icon }
    }

    private func repo(_ db: AppDatabase, icon: SiteIcon? = nil) -> GRDBMiniAppRepository {
        GRDBMiniAppRepository(database: db, icons: MiniAppIconStorage(folder: dir.appendingPathComponent("icons")), siteIcons: StubIcons(icon: icon))
    }

    func testMigrationRegistersBothTables() throws {
        let db = try database()
        let tables = try db.writer.read { try String.fetchAll($0, sql: "SELECT name FROM sqlite_master WHERE type = 'table'") }
        XCTAssertTrue(tables.contains("miniApps")); XCTAssertTrue(tables.contains("miniAppPermissions"))
        let applied = try db.writer.read { try String.fetchAll($0, sql: "SELECT identifier FROM grdb_migrations") }
        XCTAssertTrue(applied.contains("miniapps_v1"))
    }

    func testSavesWatchesAndOrdersByPosition() async throws {
        let r = repo(try database())
        _ = await r.save(app("b", position: 1)); _ = await r.save(app("a", position: 0))
        var it = r.watchAll().makeAsyncIterator()
        let first = await it.next()
        XCTAssertEqual(first?.map(\.id), ["a", "b"])
        // Saving again replaces by id.
        var changed = app("a", position: 5); changed.name = "Renamed"; changed.iconPath = "/i.png"; changed.lastUrl = "https://x.io/p"
        _ = await r.save(changed)
        var it2 = r.watchAll().makeAsyncIterator()
        let second = await it2.next()
        XCTAssertEqual(second?.map(\.id), ["b", "a"])
        XCTAssertEqual(second?.last, changed)
    }

    func testLastUrlAndOrderTouchOnlyTheirColumns() async throws {
        let r = repo(try database())
        _ = await r.save(app("a", position: 0)); _ = await r.save(app("b", position: 1))
        _ = await r.saveLastUrl(id: "a", url: "https://x.io/deep")
        _ = await r.saveOrder(["b", "a"])
        var it = r.watchAll().makeAsyncIterator()
        let list = await it.next()
        XCTAssertEqual(list?.map(\.id), ["b", "a"])
        XCTAssertEqual(list?.last?.lastUrl, "https://x.io/deep"); XCTAssertEqual(list?.last?.name, "A")
    }

    func testDeleteRemovesTheAppItsPermissionsAndItsIcon() async throws {
        let db = try database()
        let r = repo(db, icon: SiteIcon(data: Data(repeating: 1, count: 100), fileExtension: "png"))
        _ = await r.save(app("a"))
        let path = try await r.fetchSiteIcon(id: "a", pageUrl: "https://x.io").value ?? nil
        let kept = try XCTUnwrap(path)
        XCTAssertTrue(FileManager.default.fileExists(atPath: kept))
        let permissions = GRDBMiniAppPermissionRepository(database: db)
        _ = await permissions.save(MiniAppPermissionGrant(miniAppId: "a", kind: .camera, decision: .allow))
        _ = await r.delete(id: "a")
        XCTAssertFalse(FileManager.default.fileExists(atPath: kept))
        let left = try await db.writer.read { try Int.fetchOne($0, sql: "SELECT (SELECT COUNT(*) FROM miniApps) + (SELECT COUNT(*) FROM miniAppPermissions)") }
        XCTAssertEqual(left, 0)
    }

    func testSiteIconIsKeptUnderTheAppIdAndReplacedByANewPath() async throws {
        let r = repo(try database(), icon: SiteIcon(data: Data(repeating: 2, count: 100), fileExtension: "ico"))
        let one = try await r.fetchSiteIcon(id: "a", pageUrl: "https://x.io").value ?? nil
        try await Task.sleep(for: .milliseconds(5))
        let two = try await r.fetchSiteIcon(id: "a", pageUrl: "https://x.io").value ?? nil
        XCTAssertNotEqual(one, two, "a replaced icon is a new path")
        XCTAssertFalse(FileManager.default.fileExists(atPath: try XCTUnwrap(one)))
        XCTAssertEqual((try XCTUnwrap(two) as NSString).pathExtension, "ico")
        let none = try await repo(try database()).fetchSiteIcon(id: "a", pageUrl: "https://x.io").value
        XCTAssertNil(none ?? nil)
    }

    func testImportIconCopiesTheFileKeepingItsExtension() async throws {
        let src = dir.appendingPathComponent("pic.JPG"); try Data([1, 2, 3]).write(to: src)
        let kept = try await repo(try database()).importIcon(id: "a", sourcePath: src.path).value
        XCTAssertEqual((try XCTUnwrap(kept) as NSString).pathExtension, "jpg")
        XCTAssertEqual(try Data(contentsOf: URL(fileURLWithPath: kept!)), Data([1, 2, 3]))
    }

    func testPermissionsRememberChangeForgetAndStayPerApp() async throws {
        let p = GRDBMiniAppPermissionRepository(database: try database())
        let none = try await p.decision(miniAppId: "a", kind: .camera).value ?? nil
        XCTAssertNil(none)
        _ = await p.save(MiniAppPermissionGrant(miniAppId: "a", kind: .camera, decision: .allow))
        _ = await p.save(MiniAppPermissionGrant(miniAppId: "b", kind: .camera, decision: .block))
        let a1 = try await p.decision(miniAppId: "a", kind: .camera).value ?? nil
        let b1 = try await p.decision(miniAppId: "b", kind: .camera).value ?? nil
        XCTAssertEqual(a1, .allow); XCTAssertEqual(b1, .block)
        _ = await p.save(MiniAppPermissionGrant(miniAppId: "a", kind: .camera, decision: .block))
        let a2 = try await p.decision(miniAppId: "a", kind: .camera).value ?? nil
        XCTAssertEqual(a2, .block)
        var it = p.watch(miniAppId: "a").makeAsyncIterator()
        let watched = await it.next()
        XCTAssertEqual(watched, [MiniAppPermissionGrant(miniAppId: "a", kind: .camera, decision: .block)])
        _ = await p.clear(miniAppId: "a", kind: .camera)
        let a3 = try await p.decision(miniAppId: "a", kind: .camera).value ?? nil
        XCTAssertNil(a3)
    }

    func testAnUnknownKindWrittenByANewerBuildIsSkipped() async throws {
        let db = try database()
        try await db.writer.write { try $0.execute(sql: "INSERT INTO miniAppPermissions VALUES ('a', 'teleport', 1)") }
        var it = GRDBMiniAppPermissionRepository(database: db).watch(miniAppId: "a").makeAsyncIterator()
        let list = await it.next()
        XCTAssertEqual(list, [])
    }
}

// MARK: trusted_certificates_test.dart, cookie import store, favicon

final class MiniAppFileStoreTests: XCTestCase {
    private var dir: URL!
    override func setUp() { dir = tempDir() }
    override func tearDown() { try? FileManager.default.removeItem(at: dir) }

    func testTrustedCertificates() async {
        let file = dir.appendingPathComponent("sub/trusted.json")
        let repo = FileTrustedCertificateRepository(file: file)
        let none = await repo.all().value
        XCTAssertEqual(none, [])
        let one = await repo.trust(origin: "https://a.io:443", error: "net::ERR_CERT_DATE_INVALID").value
        XCTAssertEqual(one, [TrustedCertificate(origin: "https://a.io:443", error: "net::ERR_CERT_DATE_INVALID")])
        // Trusting twice keeps one entry, with the latest error.
        let twice = await repo.trust(origin: "https://a.io:443", error: "net::ERR_CERT_AUTHORITY_INVALID").value
        XCTAssertEqual(twice?.map(\.error), ["net::ERR_CERT_AUTHORITY_INVALID"])
        _ = await repo.trust(origin: "https://b.io:443", error: trustedByChoice)
        let after = await repo.forget(TrustedCertificate(origin: "https://a.io:443", error: "net::ERR_CERT_AUTHORITY_INVALID")).value
        XCTAssertEqual(after?.map(\.origin), ["https://b.io:443"])
        let cleared = await repo.forgetAll().value
        XCTAssertEqual(cleared, [])
        XCTAssertFalse(FileManager.default.fileExists(atPath: file.path), "no entries: no file")
    }

    func testWritesAtOnceLoseNone() async {
        let repo = FileTrustedCertificateRepository(file: dir.appendingPathComponent("t.json"))
        await withTaskGroup(of: Void.self) { group in
            for i in 0..<20 { group.addTask { _ = await repo.trust(origin: "https://h\(i).io:443", error: "e") } }
        }
        let all = await repo.all().value
        XCTAssertEqual(all?.count, 20)
    }

    func testADamagedFileTrustsNothingAndAnUnwritableOneIsAFailure() async throws {
        let file = dir.appendingPathComponent("t.json")
        try "{broken".write(to: file, atomically: true, encoding: .utf8)
        let damaged = await FileTrustedCertificateRepository(file: file).all().value
        XCTAssertEqual(damaged, [])
        // A path under a regular file cannot be created.
        let blocker = dir.appendingPathComponent("blocker"); try "x".write(to: blocker, atomically: true, encoding: .utf8)
        let result = await FileTrustedCertificateRepository(file: blocker.appendingPathComponent("t.json")).trust(origin: "https://a.io:443", error: "e")
        guard case .failure(.storage) = result else { return XCTFail("expected storage failure") }
    }

    func testCookieImportsKeepOneEntryPerSiteAndNeverTheValues() async throws {
        let file = dir.appendingPathComponent("imports.json")
        let repo = FileCookieImportRepository(file: file)
        let src = CookieSource(browser: .firefox, profileId: "/p", profileName: "main")
        let at = Date(timeIntervalSince1970: 1_794_000_000.5)
        let first = CookieImport(site: "work.io", source: src, importedAt: at, keys: [CookieKey(host: "work.io", path: "/", name: "sid")])
        _ = await repo.save([first, CookieImport(site: "other.io", source: src, importedAt: at, keys: [])])
        let replaced = await repo.save([CookieImport(site: "work.io", source: src, importedAt: at, keys: [])]).value
        XCTAssertEqual(replaced?.map(\.site).sorted(), ["other.io", "work.io"])
        XCTAssertEqual(replaced?.first { $0.site == "work.io" }?.keys, [])
        // Same JSON shape as the Flutter build (browser by name, ISO-8601 date), and reads back across sessions.
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: file)) as? [[String: Any]])
        XCTAssertEqual(json.first { $0["site"] as? String == "work.io" }?["browser"] as? String, "firefox")
        let reloaded = await FileCookieImportRepository(file: file).all().value
        XCTAssertEqual(reloaded?.first { $0.site == "work.io" }?.importedAt.timeIntervalSince1970 ?? 0, at.timeIntervalSince1970, accuracy: 0.01)
        let forgotten = await repo.forget(site: "work.io").value
        XCTAssertEqual(forgotten?.map(\.site), ["other.io"])
    }

    func testReadsAnImportFileTheFlutterBuildWrote() async throws {
        let file = dir.appendingPathComponent("imports.json")
        try """
        [{"site":"work.io","browser":"chrome","profileId":"/c/Default","profileName":"Me","importedAt":"2026-11-06T10:00:00.000Z",
          "keys":[{"host":"work.io","path":"/","name":"sid"}]},
         {"site":"bad.io","browser":"netscape","profileId":"x","profileName":"x","importedAt":"2026-11-06T10:00:00Z","keys":[]}]
        """.write(to: file, atomically: true, encoding: .utf8)
        let all = await FileCookieImportRepository(file: file).all().value
        XCTAssertEqual(all?.map(\.site), ["work.io"], "an unknown browser is skipped")
        XCTAssertEqual(all?.first?.source, CookieSource(browser: .chrome, profileId: "/c/Default", profileName: "Me"))
    }

    func testFaviconDeclaredIconsBestFirst() {
        let html = """
        <html><head>
        <link rel="stylesheet" href="/s.css">
        <link rel="icon" href="/small.png" sizes="16x16">
        <link rel="icon" type="image/svg+xml" href="/vector.svg">
        <link rel="shortcut icon" href='/big.ico' sizes="64x64">
        <LINK REL="apple-touch-icon" HREF="touch.png" sizes="180x180">
        </head></html>
        """
        let icons = FaviconFetcher.declaredIcons(in: html, base: URL(string: "https://x.io/app/page")!)
        XCTAssertEqual(icons.map(\.absoluteString), ["https://x.io/app/touch.png", "https://x.io/big.ico", "https://x.io/small.png"])
        XCTAssertEqual(FaviconFetcher.fileExtension(URL(string: "https://x.io/a")!, contentType: "image/jpeg"), "jpg")
        XCTAssertEqual(FaviconFetcher.fileExtension(URL(string: "https://x.io/a.PNG")!, contentType: ""), "png")
        XCTAssertEqual(FaviconFetcher.fileExtension(URL(string: "https://x.io/a")!, contentType: ""), "ico")
    }

    func testBrowsingDataHostsOnlyWebAddresses() {
        XCTAssertEqual(WKMiniAppBrowsingDataRepository.hosts(of: ["https://A.io/x", "http://b.io", "ftp://c.io", "nonsense", "file:///x"]), ["a.io", "b.io"])
    }
}
