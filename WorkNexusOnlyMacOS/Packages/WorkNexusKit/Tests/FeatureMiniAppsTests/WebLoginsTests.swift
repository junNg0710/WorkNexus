import CommonCrypto
import CoreDomain
import GRDB
import XCTest
@testable import FeatureMiniApps

/// The saved passwords (new, no Dart counterpart): origins, use cases, the keychain repository over an in-memory double —
/// the real keychain is never touched — and the Chromium `Login Data` reader over a fixture built here.

/// The value of an outcome that must have succeeded.
func got<T>(_ outcome: Outcome<T>, file: StaticString = #filePath, line: UInt = #line) throws -> T {
    switch outcome {
    case .success(let value): return value
    case .failure(let failure): XCTFail("failed: \(failure.message)", file: file, line: line); throw failure
    }
}

func webLoginsTempDir() -> URL {
    let d = FileManager.default.temporaryDirectory.appendingPathComponent("weblogins_test_\(UUID().uuidString)")
    try? FileManager.default.createDirectory(at: d, withIntermediateDirectories: true)
    return d
}

/// A keychain-backed repository over the in-memory double, and the double itself to count what was read.
func fakeWebLogins() -> (KeychainWebLoginRepository, InMemoryKeychainItemStore) {
    let items = InMemoryKeychainItemStore()
    return (KeychainWebLoginRepository(items: items, neverSaveFile: webLoginsTempDir().appendingPathComponent("never.json")), items)
}

/// Chromium's scheme, written out here so the fixture does not depend on the code under test: PBKDF2-HMAC-SHA1
/// (`saltysalt`, 1003 rounds, 16 bytes), AES-128-CBC with an IV of 16 spaces, PKCS#7, behind a `v10` / `v11` prefix.
func chromiumEncrypt(_ plain: String, keychainPassword: String, prefix: String = "v10") -> Data {
    var key = [UInt8](repeating: 0, count: 16)
    let salt = Array("saltysalt".utf8)
    CCKeyDerivationPBKDF(CCPBKDFAlgorithm(kCCPBKDF2), keychainPassword, keychainPassword.utf8.count, salt, salt.count,
                         CCPseudoRandomAlgorithm(kCCPRFHmacAlgSHA1), 1003, &key, key.count)
    let input = Array(plain.utf8), iv = [UInt8](repeating: 0x20, count: 16)
    var out = [UInt8](repeating: 0, count: input.count + 16), moved = 0
    CCCrypt(CCOperation(kCCEncrypt), CCAlgorithm(kCCAlgorithmAES), CCOptions(kCCOptionPKCS7Padding), key, key.count, iv,
            input, input.count, &out, out.count, &moved)
    return Data(prefix.utf8) + Data(out[0..<moved])
}

final class WebOriginTests: XCTestCase {
    func testAnOriginIsSchemeHostAndPortAsThePageSpellsIt() {
        XCTAssertEqual(webOrigin(ofAddress: "https://Intranet.Corp.com/#/?temp=1"), "https://intranet.corp.com")
        XCTAssertEqual(webOrigin(ofAddress: "https://intranet.corp.com:443/login"), "https://intranet.corp.com")
        XCTAssertEqual(webOrigin(ofAddress: "https://intranet.corp.com:8443/login"), "https://intranet.corp.com:8443")
        XCTAssertEqual(webOrigin(ofAddress: "http://nas.local:5000/"), "http://nas.local:5000")
        XCTAssertEqual(webOrigin(ofAddress: "http://192.168.1.20:80/x"), "http://192.168.1.20")
        XCTAssertEqual(webOrigin(scheme: "https", host: "a.io", port: 0), "https://a.io")
    }

    func testOnlyWebPagesHaveOne() {
        for text in ["file:///etc/passwd", "about:blank", "data:text/html,hi", "javascript:1", "ftp://a.io", "not a url", ""] {
            XCTAssertNil(webOrigin(ofAddress: text), text)
        }
    }

    func testTheHostShownAndWhetherItIsEncrypted() {
        XCTAssertEqual(webOriginHost("https://nas.local:5001"), "nas.local:5001")
        XCTAssertEqual(webOriginHostName("https://nas.local:5001"), "nas.local")
        XCTAssertTrue(webOriginIsSecure("https://a.io")); XCTAssertFalse(webOriginIsSecure("http://a.io"))
        XCTAssertEqual(WebLoginSummary(origin: "https://a.io", username: "u").host, "a.io")
    }
}

final class WebLoginUseCaseTests: XCTestCase {
    private let site = "https://intranet.corp.com"

    func testSavingTheSameUserAgainUpdatesThePasswordInsteadOfAddingOne() async throws {
        let (repo, _) = fakeWebLogins()
        let save = SaveWebLogin(repo), find = FindWebLogins(repo)
        _ = try got(await save(WebLogin(origin: site, username: "alice", password: "one")))
        _ = try got(await save(WebLogin(origin: site, username: "alice", password: "two")))
        _ = try got(await save(WebLogin(origin: site, username: "bob", password: "b")))
        let found = try got(await find(for: URL(string: "\(site)/#/login?temp=1")))
        XCTAssertEqual(found, [WebLogin(origin: site, username: "alice", password: "two"), WebLogin(origin: site, username: "bob", password: "b")])
    }

    func testSaveRefusesWhatIsNotASignInOfAWebSite() async {
        let (repo, items) = fakeWebLogins()
        let save = SaveWebLogin(repo)
        for bad in [WebLogin(origin: "file:///x", username: "u", password: "p"), WebLogin(origin: "https://a.io/path", username: "u", password: "p"),
                    WebLogin(origin: "HTTPS://A.io", username: "u", password: "p"), WebLogin(origin: site, username: "u", password: ""),
                    WebLogin(origin: site, username: "u", password: String(repeating: "x", count: SaveWebLogin.maxLength + 1))] {
            guard case .failure(.validation) = await save(bad) else { return XCTFail("\(bad.origin) was kept") }
        }
        XCTAssertEqual(try items.entries(), [])
    }

    func testASignInIsFoundOnItsExactOriginOnly() async throws {
        let (repo, _) = fakeWebLogins()
        _ = await SaveWebLogin(repo)(WebLogin(origin: site, username: "alice", password: "pw"))
        _ = await SaveWebLogin(repo)(WebLogin(origin: "http://nas.local:5000", username: "admin", password: "lan"))
        let find = FindWebLogins(repo)
        for other in ["http://intranet.corp.com/", "https://intranet.corp.com:8443/", "https://intranet.corp.com.evil.io/", "https://corp.com/",
                      "https://sub.intranet.corp.com/", "https://nas.local:5000/", "http://nas.local/", "file:///x", "about:blank"] {
            let found = try got(await find(for: URL(string: other)))
            XCTAssertEqual(found, [], other)
        }
        let none = try got(await find(for: nil))
        XCTAssertEqual(none, [])
        // An `http` origin gets a sign-in only when it was saved on that very origin (a tool on the local network).
        let lan = try got(await find(for: URL(string: "http://nas.local:5000/admin")))
        XCTAssertEqual(lan.map(\.username), ["admin"])
    }

    func testListingNeverReadsAPassword() async throws {
        let (repo, items) = fakeWebLogins()
        _ = await SaveWebLogin(repo)(WebLogin(origin: site, username: "alice", password: "pw"))
        _ = await SaveWebLogin(repo)(WebLogin(origin: "https://b.io", username: "", password: "pw2"))
        let list = ListWebLogins(repo)
        let all = try got(await list())
        XCTAssertEqual(all, [WebLoginSummary(origin: "https://b.io", username: ""), WebLoginSummary(origin: site, username: "alice")])
        let one = try got(await list(origin: site))
        XCTAssertEqual(one.map(\.username), ["alice"])
        XCTAssertEqual(items.secretReads, 0, "a list is attributes only: the keychain is not asked for a secret")
    }

    func testForgetOneAndAll() async throws {
        let (repo, items) = fakeWebLogins()
        for u in ["a", "b", "c"] { _ = await SaveWebLogin(repo)(WebLogin(origin: site, username: u, password: "p")) }
        let forget = ForgetWebLogin(repo)
        _ = try got(await forget(WebLoginSummary(origin: site, username: "b")))
        let left = try got(await ListWebLogins(repo)())
        XCTAssertEqual(left.map(\.username), ["a", "c"])
        _ = try got(await forget.all())
        XCTAssertEqual(try items.entries(), [])
    }

    func testNeverSaveListAndWhatIsOffered() async throws {
        let (repo, items) = fakeWebLogins()
        let never = NeverSaveForSite(repo), offer = ResolveWebLoginOffer(repo)
        let typed = WebLogin(origin: site, username: "alice", password: "pw")
        // A first sign-in: "save", and no secret was read to decide it.
        do { let o = await offer(typed).value; XCTAssertEqual(o, .save) }
        XCTAssertEqual(items.secretReads, 0)
        _ = await SaveWebLogin(repo)(typed)
        do { let o = await offer(typed).value; XCTAssertEqual(o, WebLoginOffer.none, "saved as it is") }
        do { let o = await offer(WebLogin(origin: site, username: "alice", password: "new")).value; XCTAssertEqual(o, .update) }
        do { let o = await offer(WebLogin(origin: site, username: "bob", password: "pw")).value; XCTAssertEqual(o, .save) }
        do { let o = await offer(WebLogin(origin: site, username: "bob", password: "")).value; XCTAssertEqual(o, WebLoginOffer.none) }
        // "Never for this site": nothing is offered there any more, other sites are.
        _ = try got(await never(site))
        do { let o = await offer(WebLogin(origin: site, username: "bob", password: "pw")).value; XCTAssertEqual(o, WebLoginOffer.none) }
        do { let o = await offer(WebLogin(origin: "https://b.io", username: "bob", password: "pw")).value; XCTAssertEqual(o, .save) }
        do { let l = await never.list().value; XCTAssertEqual(l, [site]) }
        _ = try got(await never.allow(site))
        do { let l = await never.list().value; XCTAssertEqual(l, []) }
        guard case .failure(.validation) = await never("not a site") else { return XCTFail("kept a non-site") }
    }

    func testTheKeychainItemsHoldThePasswordAsTheSecretAndNothingElseDoes() async throws {
        let (repo, items) = fakeWebLogins()
        _ = await SaveWebLogin(repo)(WebLogin(origin: site, username: "alice smith", password: "s3cret-pw"))
        let entries = try items.entries()
        XCTAssertEqual(entries, [KeychainEntry(account: "\(site) alice smith", label: "WorkNexus: intranet.corp.com (alice smith)")])
        XCTAssertFalse(entries.contains { $0.account.contains("s3cret-pw") || $0.label.contains("s3cret-pw") })
        XCTAssertEqual(try items.data(account: entries[0].account), Data("s3cret-pw".utf8))
        // A user name with spaces comes back whole; an account that is not ours is ignored.
        XCTAssertEqual(KeychainWebLoginRepository.summary(ofAccount: entries[0].account), WebLoginSummary(origin: site, username: "alice smith"))
        XCTAssertNil(KeychainWebLoginRepository.summary(ofAccount: "something-else"))
        XCTAssertEqual(KeychainWebLoginRepository.summary(ofAccount: "\(site) "), WebLoginSummary(origin: site, username: ""))
    }

    func testASignInNeverPrintsItsPassword() {
        let login = WebLogin(origin: site, username: "alice", password: "s3cret-pw")
        var dumped = ""
        dump(login, to: &dumped)
        for text in ["\(login)", String(describing: login), String(reflecting: login), dumped, "\([login])", "\(Outcome<[WebLogin]>.success([login]))"] {
            XCTAssertFalse(text.contains("s3cret-pw"), text)
            XCTAssertTrue(text.contains("alice"))
        }
    }

    func testTheNeverSaveFileHoldsOriginsOnly() async throws {
        let dir = webLoginsTempDir()
        let file = dir.appendingPathComponent("never.json")
        let repo = KeychainWebLoginRepository(items: InMemoryKeychainItemStore(), neverSaveFile: file)
        _ = await SaveWebLogin(repo)(WebLogin(origin: site, username: "alice", password: "s3cret-pw"))
        _ = await repo.setNeverSave(origin: "https://b.io", true)
        let text = try String(contentsOf: file, encoding: .utf8)
        XCTAssertTrue(text.contains("b.io")); XCTAssertFalse(text.contains("s3cret-pw")); XCTAssertFalse(text.contains("alice"))
        // Nothing else was written beside it.
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: dir.path), ["never.json"])
    }
}

// MARK: Chromium `Login Data`

final class ChromiumLoginReaderTests: XCTestCase {
    private var tmp: URL!
    override func setUp() { tmp = webLoginsTempDir() }
    override func tearDown() { try? FileManager.default.removeItem(at: tmp) }

    /// A Chrome profile with a `Login Data` like the browser's: one row each for the cases the reader must tell apart.
    private func makeProfile(file: String = "Login Data") throws -> URL {
        let profile = tmp.appendingPathComponent("Library/Application Support/Google/Chrome/Default")
        try FileManager.default.createDirectory(at: profile, withIntermediateDirectories: true)
        let db = try DatabaseQueue(path: profile.appendingPathComponent(file).path)
        try db.write { db in
            try db.execute(sql: """
            CREATE TABLE logins (origin_url VARCHAR NOT NULL, action_url VARCHAR, username_element VARCHAR, username_value VARCHAR,
              password_element VARCHAR, password_value BLOB, signon_realm VARCHAR NOT NULL, blacklisted_by_user INTEGER NOT NULL)
            """)
            let rows: [(String, String, Data, Int)] = [
                ("https://intranet.corp.com/#/login", "alice", chromiumEncrypt("hunter2", keychainPassword: "pw"), 0),
                ("http://nas.local:5000/", "admin", chromiumEncrypt("lan-pässword ✓", keychainPassword: "pw", prefix: "v11"), 0),
                ("https://other.org/signin", "bob", chromiumEncrypt("b0b", keychainPassword: "pw"), 0),
                ("https://blocked.com/", "", Data(), 1),
                ("https://never.com/", "eve", chromiumEncrypt("x", keychainPassword: "pw"), 1),
                ("https://empty.com/", "carol", Data(), 0),
                ("https://wrongkey.com/", "dave", chromiumEncrypt("nope", keychainPassword: "another"), 0),
                ("android://hash@com.example.app/", "mob", chromiumEncrypt("m", keychainPassword: "pw"), 0),
            ]
            for r in rows {
                try db.execute(sql: "INSERT INTO logins VALUES (?, '', '', ?, '', ?, ?, ?)", arguments: [r.0, r.1, r.2, r.0, r.3])
            }
        }
        try db.close()
        return profile
    }

    private func reader(status: Int32 = 0, asked: Locked<Int> = Locked(0)) -> ChromiumLoginReader {
        ChromiumLoginReader(keys: ChromiumCookieReader(home: tmp.path, run: { _, args in
            asked.withLock { $0 += 1 }
            XCTAssertEqual(args, ["find-generic-password", "-w", "-s", "Chrome Safe Storage"])
            return CommandResult(status: status, stdout: "pw\n")
        }))
    }

    func testDecryptsTheSavedPasswordsAndSkipsTheBlockedAndTheEmpty() async throws {
        let profile = try makeProfile()
        let asked = Locked(0)
        let r = reader(asked: asked)
        let logins = try await r.read(.chrome, profilePath: profile.path)
        XCTAssertEqual(Set(logins), [WebLogin(origin: "https://intranet.corp.com", username: "alice", password: "hunter2"),
                                     WebLogin(origin: "http://nas.local:5000", username: "admin", password: "lan-pässword ✓"),
                                     WebLogin(origin: "https://other.org", username: "bob", password: "b0b")])
        _ = try await r.read(.chrome, profilePath: profile.path)
        XCTAssertEqual(asked.withLock { $0 }, 1, "the browser's key is asked of the keychain once")
        // The browser's own file is left as it was (a copy is read).
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: profile.path), ["Login Data"])
    }

    func testAProfileWithoutSavedPasswordsReadsAsNone() async throws {
        let profile = tmp.appendingPathComponent("Library/Application Support/Google/Chrome/Default")
        try FileManager.default.createDirectory(at: profile, withIntermediateDirectories: true)
        let asked = Locked(0)
        let logins = try await reader(asked: asked).read(.chrome, profilePath: profile.path)
        XCTAssertEqual(logins, [])
        XCTAssertEqual(asked.withLock { $0 }, 0, "no file: the keychain is not asked at all")
    }

    func testRefusalsAreReportedLikeTheCookies() async throws {
        let profile = try makeProfile()
        let source = CookieSource(browser: .chrome, profileId: profile.path, profileName: "Me")
        let denied = LocalBrowserLoginRepository(reader: reader(status: 51))
        do { let r = await denied.read(source); guard case .failure(let f) = r else { return XCTFail("expected a refusal") }
             XCTAssertEqual(f, .auth(CookieReadRefusal.keychain)) }
        // Privacy (Full Disk Access) keeps the app out of the browser's folder.
        let chrome = profile.deletingLastPathComponent()
        try FileManager.default.setAttributes([.posixPermissions: 0o000], ofItemAtPath: chrome.path)
        defer { try? FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: chrome.path) }
        do { let r = await LocalBrowserLoginRepository(reader: reader()).read(source)
             guard case .failure(let f) = r else { return XCTFail("expected a refusal") }
             XCTAssertEqual(f, .auth(CookieReadRefusal.system)) }
    }

    func testFirefoxAndSafariAreNotSupported() async throws {
        let repo = LocalBrowserLoginRepository(reader: reader())
        XCTAssertEqual(CookieBrowser.allCases.filter(repo.supports), [.chrome, .edge, .brave, .arc])
        let none = try got(await repo.read(CookieSource(browser: .firefox, profileId: tmp.path, profileName: "x")))
        XCTAssertEqual(none, [])
    }
}

// MARK: Import (picked sites only)

final class FixtureBrowserLogins: BrowserLoginRepository, @unchecked Sendable {
    var logins: Outcome<[WebLogin]> = .success([])
    private(set) var reads: [CookieSource] = []
    func supports(_ browser: CookieBrowser) -> Bool { browser.isChromium }
    func read(_ source: CookieSource) async -> Outcome<[WebLogin]> { reads.append(source); return logins }
}

let browserLoginsFixture = [
    WebLogin(origin: "https://chat.example.com", username: "me", password: "chat-pw"),
    WebLogin(origin: "https://example.com", username: "root", password: "ex-pw"),
    WebLogin(origin: "https://example.com", username: "root", password: "ex-pw-newer"),
    WebLogin(origin: "https://example.com.evil.io", username: "phish", password: "evil"),
    WebLogin(origin: "https://github.com", username: "octo", password: "gh-pw"),
    WebLogin(origin: "http://localhost:9", username: "dev", password: "local"),
    WebLogin(origin: "https://docs.example.com", username: "blank", password: ""),
]

final class ImportBrowserLoginsTests: XCTestCase {
    func testOnlyThePickedSitesPasswordsAreImported() async throws {
        let browsers = FixtureBrowserLogins()
        browsers.logins = .success(browserLoginsFixture)
        let (repo, _) = fakeWebLogins()
        let imported = await ImportBrowserLogins(browsers, repo)(chromeSource, sites: ["example.com"]).value
        XCTAssertEqual(imported, 2)
        let kept = try got(await ListWebLogins(repo)())
        XCTAssertEqual(kept, [WebLoginSummary(origin: "https://chat.example.com", username: "me"), WebLoginSummary(origin: "https://example.com", username: "root")])
        // The later row of the same site and user wins; nothing of github, localhost or the look-alike came along.
        let root = try got(await FindWebLogins(repo)(for: URL(string: "https://example.com/")))
        XCTAssertEqual(root.map(\.password), ["ex-pw-newer"])
    }

    func testNothingPickedOrAnUnsupportedBrowserImportsNothingAndReadsNothing() async throws {
        let browsers = FixtureBrowserLogins()
        browsers.logins = .success(browserLoginsFixture)
        let (repo, items) = fakeWebLogins()
        let use = ImportBrowserLogins(browsers, repo)
        do { let n = await use(chromeSource, sites: []).value; XCTAssertEqual(n, 0) }
        do { let n = await use(firefoxSource, sites: ["example.com"]).value; XCTAssertEqual(n, 0) }
        XCTAssertEqual(browsers.reads, [chromeSource], "Firefox's passwords are never read")
        XCTAssertEqual(try items.entries(), [])
    }

    func testARefusedReadIsTheFailure() async {
        let browsers = FixtureBrowserLogins()
        browsers.logins = .failure(.auth(CookieReadRefusal.keychain))
        let (repo, _) = fakeWebLogins()
        guard case .failure(.auth) = await ImportBrowserLogins(browsers, repo)(chromeSource, sites: ["example.com"]) else { return XCTFail("expected the refusal") }
    }
}
