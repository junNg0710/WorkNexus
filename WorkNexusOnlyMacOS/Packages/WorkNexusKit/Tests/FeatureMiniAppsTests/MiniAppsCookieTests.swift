import CommonCrypto
import CoreDomain
import CryptoKit
import GRDB
import XCTest
@testable import FeatureMiniApps

private let now = Date(timeIntervalSince1970: 1_794_000_000)   // 2026-11-06
private let source = CookieSource(browser: .chrome, profileId: "/chrome/Default", profileName: "Me")

private func cookie(_ name: String, _ domain: String, httpOnly: Bool = false, expires: Date? = nil, value: String = "v") -> BrowserCookie {
    BrowserCookie(name: name, value: value, domain: domain, expires: expires, httpOnly: httpOnly)
}

private func tempDir() -> URL {
    let d = FileManager.default.temporaryDirectory.appendingPathComponent("cookies_test_\(UUID().uuidString)")
    try? FileManager.default.createDirectory(at: d, withIntermediateDirectories: true)
    return d
}

private final class FakeBrowsers: BrowserCookieRepository, @unchecked Sendable {
    var result: Outcome<[BrowserCookie]> = .success([])
    func sources() async -> Outcome<[CookieSource]> { .success([source]) }
    func read(_ source: CookieSource) async -> Outcome<[BrowserCookie]> { result }
}

private final class FakeWebView: WebViewCookieRepository, @unchecked Sendable {
    var written: [[BrowserCookie]] = []
    var presentKeys: Set<CookieKey> = []
    let canWrite = true
    func write(_ cookies: [BrowserCookie]) async -> Outcome<Void> { written.append(cookies); return .success(()) }
    func present(_ keys: [CookieKey]) async -> Outcome<Set<CookieKey>> { .success(presentKeys) }
}

private final class FakeImports: CookieImportRepository, @unchecked Sendable {
    var items: [CookieImport] = []
    func all() async -> Outcome<[CookieImport]> { .success(items) }
    func save(_ imports: [CookieImport]) async -> Outcome<[CookieImport]> { items = imports; return .success(imports) }
    func forget(site: String) async -> Outcome<[CookieImport]> { items.removeAll { $0.site == site }; return .success(items) }
}

// MARK: cookie_domain_test.dart

final class CookieDomainTests: XCTestCase {
    func testSiteOfKeepsTheRegistrablePart() {
        XCTAssertEqual(cookieSite(of: ".mail.google.com"), "google.com")
        XCTAssertEqual(cookieSite(of: "github.com"), "github.com")
        XCTAssertEqual(cookieSite(of: "shop.example.com.vn"), "example.com.vn")
        XCTAssertEqual(cookieSite(of: "a.b.co.uk"), "b.co.uk")
    }

    func testAnAddressOrSingleLabelIsItsOwnSite() {
        XCTAssertEqual(cookieSite(of: "192.168.1.20"), "192.168.1.20")
        XCTAssertEqual(cookieSite(of: "localhost"), "localhost")
    }

    func testGroupsBySiteMiniAppsFirstDropsExpiredAndEmpty() {
        let sites = GroupCookiesBySite()([cookie("a", ".zeta.com"), cookie("b", "app.zeta.com"), cookie("c", "alpha.com"), cookie("d", "work.io"),
                                          cookie("old", "beta.com", expires: Date(timeIntervalSince1970: 1_577_836_800)),
                                          cookie("blank", "gamma.com", value: "")], miniAppUrls: ["https://work.io/board"], now: now)
        XCTAssertEqual(sites.map(\.site), ["work.io", "alpha.com", "zeta.com"])
        XCTAssertTrue(sites.first!.usedByMiniApp)
        XCTAssertEqual(sites.last?.cookies.count, 2)
    }

    func testBrowserCookieDerivedFields() {
        let c = cookie("n", ".work.io")
        XCTAssertEqual(c.host, "work.io"); XCTAssertTrue(c.includesSubdomains)
        XCTAssertEqual(c.key, CookieKey(host: "work.io", path: "/", name: "n"))
        XCTAssertFalse(cookie("n", "work.io").includesSubdomains)
        XCTAssertTrue(cookie("n", "x", expires: now.addingTimeInterval(-1)).isExpired(at: now))
        XCTAssertFalse(cookie("n", "x").isExpired(at: now))
    }

    func testImportWritesOnlyPickedSitesAndRemembersSignInKeys() async throws {
        let browsers = FakeBrowsers(), web = FakeWebView(), imports = FakeImports()
        browsers.result = .success([cookie("session", ".work.io", httpOnly: true), cookie("_ga", ".work.io"), cookie("other", "elsewhere.com", httpOnly: true),
                                    cookie("gone", "work.io", expires: Date(timeIntervalSince1970: 1_609_459_200))])
        let result = await ImportBrowserCookies(browsers, web, imports, now: { now })(source, sites: ["work.io"])
        XCTAssertEqual(result.value, 2)
        XCTAssertEqual(web.written.single?.map(\.name), ["session", "_ga"])
        let saved = try XCTUnwrap(imports.items.single)
        XCTAssertEqual(saved.site, "work.io"); XCTAssertEqual(saved.source, source); XCTAssertEqual(saved.importedAt, now)
        // Only the HttpOnly cookie is watched: analytics come and go.
        XCTAssertEqual(saved.keys, [CookieKey(host: "work.io", path: "/", name: "session")])
    }

    func testImportWithoutHttpOnlyWatchesWholeSite() async {
        let browsers = FakeBrowsers(), web = FakeWebView(), imports = FakeImports()
        browsers.result = .success([cookie("a", "work.io"), cookie("b", "work.io"), cookie("a", "work.io")])
        _ = await ImportBrowserCookies(browsers, web, imports, now: { now })(source, sites: ["work.io"])
        XCTAssertEqual(imports.items.first?.keys.map(\.name), ["a", "b"])
    }

    func testImportFailsWithoutTouchingWebViewWhenNothingMatches() async {
        let browsers = FakeBrowsers(), web = FakeWebView(), imports = FakeImports()
        browsers.result = .success([cookie("x", "other.com")])
        let result = await ImportBrowserCookies(browsers, web, imports)(source, sites: ["work.io"])
        guard case .failure(.notFound) = result else { return XCTFail("expected not found") }
        XCTAssertTrue(web.written.isEmpty)
    }

    func testImportPassesOnARefusedRead() async {
        let browsers = FakeBrowsers(); browsers.result = .failure(.auth("denied"))
        let result = await ImportBrowserCookies(browsers, FakeWebView(), FakeImports())(source, sites: ["work.io"])
        guard case .failure(.auth) = result else { return XCTFail("expected auth failure") }
    }

    func testCheckCountsSignInCookiesTheWebViewNoLongerHas() async {
        let imports = FakeImports(), web = FakeWebView()
        let kept = CookieKey(host: "work.io", path: "/", name: "session"), lost = CookieKey(host: "work.io", path: "/", name: "refresh")
        imports.items = [CookieImport(site: "work.io", source: source, importedAt: now, keys: [kept, lost])]
        web.presentKeys = [kept]
        let states = await CheckCookieImports(imports, web)().value
        XCTAssertEqual(states?.single?.missing, 1)
        XCTAssertEqual(states?.single?.expired, true)
    }

    func testWebViewCookieConversionKeepsHttpOnlyExpiryAndHostOnly() throws {
        let c = BrowserCookie(name: "sid", value: "abc", domain: ".work.io", path: "/a", expires: now.addingTimeInterval(3600), secure: true, httpOnly: true, sameSite: .lax)
        let http = try XCTUnwrap(WebViewCookieDataSource.httpCookie(c))
        XCTAssertTrue(http.isHTTPOnly); XCTAssertTrue(http.isSecure)
        XCTAssertEqual(http.domain, ".work.io"); XCTAssertEqual(http.path, "/a")
        XCTAssertEqual(http.expiresDate?.timeIntervalSince1970 ?? 0, now.addingTimeInterval(3600).timeIntervalSince1970, accuracy: 1)
        XCTAssertEqual(http.sameSitePolicy, .sameSiteLax)
        let hostOnly = try XCTUnwrap(WebViewCookieDataSource.httpCookie(BrowserCookie(name: "x", value: "y", domain: "work.io")))
        XCTAssertEqual(hostOnly.domain, "work.io"); XCTAssertNil(hostOnly.expiresDate)
        XCTAssertTrue(WebViewCookieDataSource.matches(http, CookieKey(host: "app.work.io", path: "/a/b", name: "sid")))
        XCTAssertFalse(WebViewCookieDataSource.matches(hostOnly, CookieKey(host: "app.work.io", path: "/", name: "x")))
    }
}

private extension Array { var single: Element? { count == 1 ? first : nil } }

// MARK: browser_cookie_readers_test.dart

final class BrowserCookieReaderTests: XCTestCase {
    private var tmp: URL!
    override func setUp() { tmp = tempDir() }
    override func tearDown() { try? FileManager.default.removeItem(at: tmp) }

    /// Derived here on its own (CommonCrypto, as Chromium documents it), to check the reader's.
    private func encrypt(_ password: String, _ plain: [UInt8]) -> Data {
        var key = [UInt8](repeating: 0, count: 16)
        let salt = Array("saltysalt".utf8), pw = Array(password.utf8)
        CCKeyDerivationPBKDF(CCPBKDFAlgorithm(kCCPBKDF2), pw.map { Int8(bitPattern: $0) }, pw.count, salt, salt.count, CCPseudoRandomAlgorithm(kCCPRFHmacAlgSHA1), 1003, &key, 16)
        return ChromiumCookieCrypto(key: Data(key)).encryptForTesting(plain)
    }

    func testPBKDF2KeyMatchesKnownVector() {
        // Chromium's macOS key for the password "peanuts" (PBKDF2-HMAC-SHA1, "saltysalt", 1003 rounds, 16 bytes).
        let key = ChromiumCookieCrypto(password: "peanuts").keyBytes.map { String(format: "%02x", $0) }.joined()
        XCTAssertEqual(key.count, 32)
        var expected = [UInt8](repeating: 0, count: 16)
        let salt = Array("saltysalt".utf8), pw = Array("peanuts".utf8)
        CCKeyDerivationPBKDF(CCPBKDFAlgorithm(kCCPBKDF2), pw.map { Int8(bitPattern: $0) }, pw.count, salt, salt.count, CCPseudoRandomAlgorithm(kCCPRFHmacAlgSHA1), 1003, &expected, 16)
        XCTAssertEqual(key, expected.map { String(format: "%02x", $0) }.joined())
    }

    func testDecryptsAV10ValueDroppingTheDomainHashFromV24() {
        let crypto = ChromiumCookieCrypto(password: "secret")
        let hash = [UInt8](SHA256.hash(data: Data(".work.io".utf8)))
        XCTAssertEqual(crypto.decrypt(encrypt("secret", hash + Array("token".utf8)), hasDomainHash: true), "token")
        XCTAssertEqual(crypto.decrypt(encrypt("secret", Array("token".utf8)), hasDomainHash: false), "token")
    }

    func testGivesUpOnAnotherSchemeOrAWrongKey() {
        XCTAssertNil(ChromiumCookieCrypto(password: "secret").decrypt(Data("v20xxxxxxxxxxxxxxxx".utf8), hasDomainHash: false))
        XCTAssertNil(ChromiumCookieCrypto(password: "secret").decrypt(Data("v10short".utf8), hasDomainHash: false))
        XCTAssertNotEqual(ChromiumCookieCrypto(password: "other").decrypt(encrypt("secret", Array("token".utf8)), hasDomainHash: false), "token")
    }

    func testChromiumExpiryCountsFrom1601() {
        XCTAssertNil(chromiumExpiry(0)); XCTAssertNil(chromiumExpiry(nil))
        let year = Calendar(identifier: .gregorian).dateComponents(in: TimeZone(identifier: "UTC")!, from: chromiumExpiry(13_400_000_000_000_000)!).year
        XCTAssertEqual(year, 2025)
    }

    private func makeChromeProfile(version: String = "23") throws -> (profile: URL, run: CommandRunner, asked: Locked<Int>) {
        let profile = tmp.appendingPathComponent("Library/Application Support/Google/Chrome/Default")
        try FileManager.default.createDirectory(at: profile, withIntermediateDirectories: true)
        try JSONSerialization.data(withJSONObject: ["profile": ["info_cache": ["Default": ["name": "Work"]]]])
            .write(to: profile.deletingLastPathComponent().appendingPathComponent("Local State"))
        let db = try DatabaseQueue(path: profile.appendingPathComponent("Cookies").path)
        try db.write { db in
            try db.execute(sql: "CREATE TABLE meta (key TEXT, value TEXT)")
            try db.execute(sql: "INSERT INTO meta VALUES ('version', ?)", arguments: [version])
            try db.execute(sql: "CREATE TABLE cookies (host_key TEXT, name TEXT, value TEXT, encrypted_value BLOB, path TEXT, expires_utc INTEGER, is_secure INTEGER, is_httponly INTEGER, samesite INTEGER)")
            try db.execute(sql: "INSERT INTO cookies VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)",
                           arguments: [".work.io", "sid", "", encrypt("pw", Array("abc".utf8)), "/", 13_400_000_000_000_000, 1, 1, 1])
            try db.execute(sql: "INSERT INTO cookies VALUES ('plain.io', 'p', 'plain-value', X'', '/x', 0, 0, 0, -1)")
        }
        try db.close()
        let asked = Locked(0)
        return (profile, { _, _ in asked.withLock { $0 += 1 }; return CommandResult(status: 0, stdout: "pw\n") }, asked)
    }

    func testReadsAndDecryptsAProfileAskingTheKeychainOnce() async throws {
        let (profile, run, asked) = try makeChromeProfile()
        let reader = ChromiumCookieReader(home: tmp.path, run: run)
        let profiles = reader.profiles(.chrome)
        XCTAssertEqual(profiles, [ChromiumProfile(path: profile.path, name: "Work")])
        let cookies = try await reader.read(.chrome, profilePath: profiles[0].path)
        _ = try await reader.read(.chrome, profilePath: profiles[0].path)
        let sid = try XCTUnwrap(cookies.first { $0.name == "sid" })
        XCTAssertEqual(sid.value, "abc"); XCTAssertTrue(sid.httpOnly); XCTAssertTrue(sid.secure); XCTAssertEqual(sid.sameSite, .lax)
        XCTAssertEqual(Calendar(identifier: .gregorian).component(.year, from: try XCTUnwrap(sid.expires)), 2025)
        let plain = try XCTUnwrap(cookies.first { $0.name == "p" })
        XCTAssertEqual(plain.value, "plain-value"); XCTAssertEqual(plain.path, "/x"); XCTAssertNil(plain.expires); XCTAssertEqual(plain.sameSite, .unspecified)
        XCTAssertEqual(asked.withLock { $0 }, 1)
    }

    func testReadsAV24ProfileWhoseValuesCarryTheDomainHash() async throws {
        let profile = tmp.appendingPathComponent("Library/Application Support/Google/Chrome/Default/Network")
        try FileManager.default.createDirectory(at: profile, withIntermediateDirectories: true)
        let db = try DatabaseQueue(path: profile.appendingPathComponent("Cookies").path)
        let hash = [UInt8](SHA256.hash(data: Data(".work.io".utf8)))
        try await db.write { db in
            try db.execute(sql: "CREATE TABLE meta (key TEXT, value TEXT)")
            try db.execute(sql: "INSERT INTO meta VALUES ('version', '24')")
            try db.execute(sql: "CREATE TABLE cookies (host_key TEXT, name TEXT, value TEXT, encrypted_value BLOB, path TEXT, expires_utc INTEGER, is_secure INTEGER, is_httponly INTEGER, samesite INTEGER)")
            try db.execute(sql: "INSERT INTO cookies VALUES ('.work.io', 'sid', '', ?, '/', 0, 0, 0, 0)", arguments: [encrypt("pw", hash + Array("tok".utf8))])
        }
        try db.close()
        let reader = ChromiumCookieReader(home: tmp.path, run: { _, _ in CommandResult(status: 0, stdout: "pw") })
        let cookies = try await reader.read(.chrome, profilePath: profile.deletingLastPathComponent().path)
        XCTAssertEqual(cookies.first?.value, "tok")
        XCTAssertEqual(cookies.first?.sameSite, CookieSameSite.none)
    }

    func testARefusedKeychainIsAKeychainDeniedError() async throws {
        let (profile, _, _) = try makeChromeProfile()
        let reader = ChromiumCookieReader(home: tmp.path, run: { _, _ in CommandResult(status: 51, stdout: "") })
        do { _ = try await reader.read(.chrome, profilePath: profile.path); XCTFail("expected a throw") }
        catch let e as KeychainDeniedError { XCTAssertEqual(e.service, "Chrome Safe Storage") }
        // And the repository maps it to an auth failure.
        let repo = LocalBrowserCookieRepository(chromium: reader, firefox: FirefoxCookieReader(root: tmp.path), safari: SafariCookieReader(home: tmp.path))
        let result = await repo.read(CookieSource(browser: .chrome, profileId: profile.path, profileName: "Work"))
        guard case .failure(.auth) = result else { return XCTFail("expected auth failure, got \(result)") }
    }

    func testParsesProfilesIni() {
        let profiles = FirefoxCookieReader.parseProfilesIni("""
        [General]
        StartWithLastProfile=1

        [Profile0]
        Name=default-release
        IsRelative=1
        Path=Profiles/abc.default-release

        [Profile1]
        Name=work
        IsRelative=0
        Path=/abs/work
        """)
        XCTAssertEqual(profiles, [FirefoxIniProfile(name: "default-release", path: "Profiles/abc.default-release", relative: true),
                                  FirefoxIniProfile(name: "work", path: "/abs/work", relative: false)])
    }

    func testFirefoxExpiryInSecondsOrMilliseconds() {
        let year: (Date?) -> Int? = { $0.map { Calendar(identifier: .gregorian).component(.year, from: $0) } }
        XCTAssertNil(firefoxExpiry(0))
        XCTAssertEqual(year(firefoxExpiry(1_800_000_000)), 2027)
        XCTAssertEqual(year(firefoxExpiry(1_800_000_000_000)), 2027)
    }

    func testReadsAFirefoxProfile() async throws {
        try "[Profile0]\nName=main\nIsRelative=1\nPath=p\n".write(to: tmp.appendingPathComponent("profiles.ini"), atomically: true, encoding: .utf8)
        try FileManager.default.createDirectory(at: tmp.appendingPathComponent("p"), withIntermediateDirectories: true)
        let db = try DatabaseQueue(path: tmp.appendingPathComponent("p/cookies.sqlite").path)
        try await db.write { db in
            try db.execute(sql: "CREATE TABLE moz_cookies (name TEXT, value TEXT, host TEXT, path TEXT, expiry INTEGER, isSecure INTEGER, isHttpOnly INTEGER, sameSite INTEGER)")
            try db.execute(sql: "INSERT INTO moz_cookies VALUES ('sid', 'abc', '.work.io', '/', 1800000000, 1, 1, 2)")
        }
        try db.close()
        let reader = FirefoxCookieReader(root: tmp.path)
        let profile = try XCTUnwrap(reader.profiles().single)
        let read = try await reader.read(profilePath: profile.path)
        let cookie = try XCTUnwrap(read.single)
        XCTAssertEqual(profile.name, "main"); XCTAssertEqual(cookie.domain, ".work.io"); XCTAssertEqual(cookie.value, "abc")
        XCTAssertEqual(cookie.sameSite, .strict); XCTAssertTrue(cookie.httpOnly)
    }

    func testReadingASnapshotLeavesTheOriginalAloneAndSeesTheWal() throws {
        let path = tmp.appendingPathComponent("w.sqlite").path
        let queue = try DatabasePool(path: path)    // WAL mode
        try queue.write { try $0.execute(sql: "CREATE TABLE t (v TEXT)"); try $0.execute(sql: "INSERT INTO t VALUES ('in-wal')") }
        // Not checkpointed: the row lives in the -wal file.
        XCTAssertTrue(FileManager.default.fileExists(atPath: path + "-wal"))
        let values = try readSQLiteSnapshot(path) { try String.fetchAll($0, sql: "SELECT v FROM t") }
        XCTAssertEqual(values, ["in-wal"])
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: FileManager.default.temporaryDirectory.path).filter { $0.hasPrefix("worknexus_cookies_") }.count, 0)
    }

    // MARK: Safari

    private func cookieRecord() -> [UInt8] {
        var strings: [UInt8] = []
        for s in [".work.io", "sid", "/", "abc"] { strings += Array(s.utf8) + [0] }
        let head = 56
        var record = [UInt8](repeating: 0, count: head + strings.count)
        func le32(_ v: Int, at: Int) { for i in 0..<4 { record[at + i] = UInt8((v >> (8 * i)) & 0xff) } }
        le32(head + strings.count, at: 0)
        le32(5, at: 8)               // secure + HttpOnly
        le32(head, at: 16); le32(head + 9, at: 20); le32(head + 13, at: 24); le32(head + 15, at: 28)
        let bits = Double(800_000_000).bitPattern
        for i in 0..<8 { record[40 + i] = UInt8((bits >> (8 * UInt64(i))) & 0xff) }
        record.replaceSubrange(head..<record.count, with: strings)
        return record
    }

    private func binaryCookies(_ record: [UInt8]) -> Data {
        var page = [UInt8](repeating: 0, count: 16 + record.count)
        page[0] = 0; page[1] = 0; page[2] = 1; page[3] = 0          // 0x00000100 big-endian
        page[4] = 1                                                   // one cookie (little-endian)
        page[8] = 16                                                  // at offset 16
        page.replaceSubrange(16..<page.count, with: record)
        var file: [UInt8] = Array("cook".utf8) + [0, 0, 0, 1]         // one page
        file += [UInt8((page.count >> 24) & 0xff), UInt8((page.count >> 16) & 0xff), UInt8((page.count >> 8) & 0xff), UInt8(page.count & 0xff)]
        return Data(file + page)
    }

    func testParsesABinaryCookiesPage() throws {
        let cookies = try BinaryCookies.parse(binaryCookies(cookieRecord()))
        let c = try XCTUnwrap(cookies.single)
        XCTAssertEqual(c.domain, ".work.io"); XCTAssertEqual(c.name, "sid"); XCTAssertEqual(c.path, "/"); XCTAssertEqual(c.value, "abc")
        XCTAssertTrue(c.secure); XCTAssertTrue(c.httpOnly)
        XCTAssertEqual(Calendar(identifier: .gregorian).component(.year, from: try XCTUnwrap(c.expires)), 2026)
    }

    func testRefusesAnotherFileOrATruncatedOne() {
        XCTAssertThrowsError(try BinaryCookies.parse(Data("nope0000".utf8))) { XCTAssertTrue($0 is BinaryCookies.FormatError) }
        XCTAssertThrowsError(try BinaryCookies.parse(binaryCookies(cookieRecord()).prefix(40)))
    }

    func testRefusedPermissionIsRecognised() {
        XCTAssertTrue(LocalBrowserCookieRepository.isRefused(CocoaError(.fileReadNoPermission) as NSError))
        XCTAssertTrue(LocalBrowserCookieRepository.isRefused(NSError(domain: NSPOSIXErrorDomain, code: 1)))
        XCTAssertTrue(LocalBrowserCookieRepository.isRefused(NSError(domain: "x", code: 0, userInfo: [NSUnderlyingErrorKey: NSError(domain: NSPOSIXErrorDomain, code: 13)])))
        XCTAssertFalse(LocalBrowserCookieRepository.isRefused(CocoaError(.fileNoSuchFile) as NSError))
    }
}
