import CoreDomain
import XCTest
@testable import FeatureMiniApps

// MARK: doubles

actor FakeMiniAppRepo: MiniAppRepository {
    private(set) var saved: [MiniApp] = []
    private(set) var order: [String] = []
    private(set) var icons = 0
    var failSave = false
    nonisolated func watchAll() -> AsyncStream<[MiniApp]> { AsyncStream { $0.finish() } }
    func save(_ app: MiniApp) async -> Outcome<Void> {
        if failSave { return .failure(.storage("nope")) }
        saved.append(app); return .success(())
    }
    func saveLastUrl(id: String, url: String) async -> Outcome<Void> { .success(()) }
    func saveOrder(_ ids: [String]) async -> Outcome<Void> { order = ids; return .success(()) }
    func delete(id: String) async -> Outcome<Void> { .success(()) }
    func fetchSiteIcon(id: String, pageUrl: String) async -> Outcome<String?> { icons += 1; return .success(nil) }
    func importIcon(id: String, sourcePath: String) async -> Outcome<String> { .success(sourcePath) }
}

final class FakePermissions: MiniAppPermissionRepository, @unchecked Sendable {
    var answers: [String: MiniAppPermissionDecision] = [:]
    var failRead = false
    func watch(miniAppId: String) -> AsyncStream<[MiniAppPermissionGrant]> { AsyncStream { $0.finish() } }
    func decision(miniAppId: String, kind: MiniAppPermissionKind) async -> Outcome<MiniAppPermissionDecision?> {
        failRead ? .failure(.storage("x")) : .success(answers["\(miniAppId)|\(kind.rawValue)"])
    }
    func save(_ grant: MiniAppPermissionGrant) async -> Outcome<Void> { answers["\(grant.miniAppId)|\(grant.kind.rawValue)"] = grant.decision; return .success(()) }
    func clear(miniAppId: String, kind: MiniAppPermissionKind) async -> Outcome<Void> { answers["\(miniAppId)|\(kind.rawValue)"] = nil; return .success(()) }
}

func app(_ id: String, _ url: String = "https://x.io", position: Int = 0) -> MiniApp { MiniApp(id: id, name: id.uppercased(), url: url, position: position) }

// MARK: add_mini_app_test.dart, move_mini_app_test.dart

final class MiniAppUseCaseTests: XCTestCase {
    func testNormalizeUrl() {
        let n = NormalizeMiniAppUrl()
        XCTAssertEqual(n("example.com/a")?.absoluteString, "https://example.com/a")
        XCTAssertEqual(n(" http://x.dev ")?.scheme, "http")
        XCTAssertEqual(n("https://x.dev")?.scheme, "https")
        XCTAssertEqual(n("localhost:3000")?.absoluteString, "https://localhost:3000")
        XCTAssertNil(n("file:///C:/a.html")); XCTAssertNil(n("javascript:alert(1)")); XCTAssertNil(n("   ")); XCTAssertNil(n("not a url"))
        XCTAssertEqual(n.defaultName(URL(string: "https://www.example.com")!), "example.com")
    }

    func testAddNamesItAfterHostAndPutsItLast() async throws {
        let repo = FakeMiniAppRepo()
        let res = await AddMiniApp(repo, RefreshMiniAppIcon(repo), newId: { "new" })(url: "www.example.com", existing: [app("a", position: 4)])
        let added = try XCTUnwrap(res.value)
        XCTAssertEqual(added.name, "example.com"); XCTAssertEqual(added.position, 5); XCTAssertEqual(added.id, "new")
        let saved = await repo.saved
        XCTAssertEqual(saved, [added])
    }

    func testAddKeepsGivenNameTrimmedAndFirstPositionIsZero() async throws {
        let repo = FakeMiniAppRepo()
        let res = await AddMiniApp(repo, RefreshMiniAppIcon(repo))(url: "https://x.io", name: "  Board ", existing: [])
        XCTAssertEqual(res.value?.name, "Board"); XCTAssertEqual(res.value?.position, 0)
    }

    func testAddFailsOnBadAddressWithoutSaving() async {
        let repo = FakeMiniAppRepo()
        let res = await AddMiniApp(repo, RefreshMiniAppIcon(repo))(url: "ftp://x", existing: [])
        guard case .failure(.parse) = res else { return XCTFail("expected parse failure") }
        let saved = await repo.saved
        XCTAssertTrue(saved.isEmpty)
    }

    func testAddPassesOnAStorageFailure() async {
        let repo = FakeMiniAppRepo(); await repo.setFailSave()
        let res = await AddMiniApp(repo, RefreshMiniAppIcon(repo))(url: "x.io", existing: [])
        guard case .failure(.storage) = res else { return XCTFail("expected storage failure") }
    }

    func testUpdateResetsLastPageForANewAddressAndRefreshesIconWhenNone() async throws {
        let repo = FakeMiniAppRepo()
        var old = app("a", "https://a.io"); old.lastUrl = "https://a.io/deep"; old.position = 2
        let same = await UpdateMiniApp(repo, RefreshMiniAppIcon(repo))(app: old, url: "https://a.io", name: "", iconPath: "/i.png")
        XCTAssertEqual(same.value?.lastUrl, "https://a.io/deep"); XCTAssertEqual(same.value?.name, "a.io"); XCTAssertEqual(same.value?.position, 2)
        let moved = await UpdateMiniApp(repo, RefreshMiniAppIcon(repo))(app: old, url: "b.io", name: "B", iconPath: nil)
        XCTAssertNil(moved.value?.lastUrl); XCTAssertEqual(moved.value?.url, "https://b.io")
    }

    func testMoveReordersAndRenumbers() async {
        let repo = FakeMiniAppRepo()
        let apps = [app("a", position: 0), app("b", position: 1), app("c", position: 2)]
        let res = await MoveMiniApp(repo)(apps, from: 0, to: 2)
        XCTAssertEqual(res.value?.map(\.id), ["b", "c", "a"])
        XCTAssertEqual(res.value?.map(\.position), [0, 1, 2])
        let order = await repo.order
        XCTAssertEqual(order, ["b", "c", "a"])
    }

    func testMoveOutOfRangeOrNowhereChangesNothing() async {
        let repo = FakeMiniAppRepo()
        let apps = [app("a"), app("b")]
        for (from, to) in [(0, 0), (-1, 1), (5, 0), (0, 2), (0, -1)] {
            let res = await MoveMiniApp(repo)(apps, from: from, to: to)
            XCTAssertEqual(res.value, apps, "\(from)→\(to)")
        }
        let order = await repo.order
        XCTAssertTrue(order.isEmpty)
    }
}

extension FakeMiniAppRepo { func setFailSave() { failSave = true } }

// MARK: is_mini_app_origin_test, is_sign_in_window_test, live_mini_apps_test, links

final class MiniAppRuleTests: XCTestCase {
    func testOrigin() {
        let origin = IsMiniAppOrigin()
        let app = "https://work.io/board"
        XCTAssertTrue(origin(app, URL(string: "https://work.io/other")))
        XCTAssertTrue(origin(app, URL(string: "HTTPS://WORK.io/x")))
        XCTAssertFalse(origin(app, URL(string: "https://evil.io/")))
        XCTAssertFalse(origin(app, URL(string: "http://work.io/")))
        XCTAssertFalse(origin(app, URL(string: "https://work.io:8443/")))
        XCTAssertFalse(origin(app, URL(string: "https://sub.work.io/")))
        XCTAssertFalse(origin(app, nil))
        XCTAssertFalse(origin("not a url", URL(string: "https://work.io")))
    }

    private func signIn(_ url: String, width: Double? = nil, height: Double? = nil) -> Bool {
        IsSignInWindow()(OpenedWindow(url: url, width: width, height: height))
    }

    func testSizedWindowIsAPopUp() {
        XCTAssertTrue(signIn("https://example.com/x", width: 500, height: 600))
        XCTAssertFalse(signIn("https://example.com/x", width: 500))
        XCTAssertFalse(signIn("https://example.com/x", width: 0, height: 0))
        XCTAssertFalse(signIn("https://example.com/x"))
    }

    func testSignInAddresses() {
        for url in ["https://github.com/login/oauth/authorize?scope=x", "https://accounts.google.com/o/oauth2/v2/auth",
                    "https://login.microsoftonline.com/common/oauth2/authorize", "https://example.auth0.com/authorize",
                    "https://example.com/sso/start", "https://example.com/saml/login", "https://example.com/sign-in",
                    "https://example.com/log_in", "https://zentao.example.com/zentao/user-login-Lw==.html",
                    "https://app.example.com/start?client_id=abc", "https://app.example.com/cb?redirect_uri=https%3A%2F%2Fx",
                    "https://auth.example.com/"] { XCTAssertTrue(signIn(url), url) }
    }

    func testOrdinaryLinksAreNotSignIns() {
        for url in ["https://www.figma.com/design/abc?node-id=1", "https://miro.com/app/board/uXjVabc=/", "https://github.com/dyno/worknexus/pull/66",
                    "https://example.com/authors/jane", "https://example.com/blog/how-to-author", "https://trello.com/c/ZYZ5x2jD/88-thay-doi",
                    "https://example.com/", "https://login.com/", "about:blank", "", "::not a url::"] { XCTAssertFalse(signIn(url), url) }
    }

    func testLiveApps() {
        XCTAssertEqual(liveMiniApps(live: ["a", "b"], current: "c", existing: ["a", "b", "c"], max: 5), ["a", "b", "c"])
        XCTAssertEqual(liveMiniApps(live: ["a", "b", "c"], current: "a", existing: ["a", "b", "c"], max: 5), ["b", "c", "a"])
        XCTAssertEqual(liveMiniApps(live: ["a", "b", "c"], current: "d", existing: ["a", "b", "c", "d"], max: 3), ["b", "c", "d"])
        XCTAssertEqual(liveMiniApps(live: ["a", "b"], current: nil, existing: ["b"], max: 5), ["b"], "removed apps are dropped")
        XCTAssertEqual(liveMiniApps(live: ["a", "b"], current: "b", existing: ["a", "b"], max: 1), ["b"], "the current one is never closed")
        XCTAssertEqual(liveMiniApps(live: [], current: "gone", existing: ["a"], max: 5), [])
    }

    func testFindMiniAppForLinkPrefersTheMoreSpecificHost() {
        let targets = [MiniAppLinkTarget(id: "root", host: "example.com"), MiniAppLinkTarget(id: "sub", host: "a.example.com")]
        XCTAssertEqual(findMiniAppForLink(targets, "https://a.example.com/x"), "sub")
        XCTAssertEqual(findMiniAppForLink(targets, "https://b.example.com/x"), "root")
        XCTAssertEqual(findMiniAppForLink(targets, "https://example.com"), "root")
        XCTAssertNil(findMiniAppForLink(targets, "https://notexample.com"))
        XCTAssertNil(findMiniAppForLink(targets, "mailto:a@example.com"))
        XCTAssertNil(findMiniAppForLink(targets, "ftp://example.com"))
    }

    func testCertificateProblems() {
        XCTAssertEqual(CertificateProblem.of("net::ERR_CERT_DATE_INVALID"), .dates)
        XCTAssertEqual(CertificateProblem.of("net::ERR_CERT_COMMON_NAME_INVALID"), .name)
        XCTAssertEqual(CertificateProblem.of("net::ERR_CERT_AUTHORITY_INVALID"), .authority)
        XCTAssertEqual(CertificateProblem.of("net::ERR_CERT_REVOKED"), .other)
        XCTAssertTrue(CertificateProblem.isCertificateError("net::ERR_CERT_REVOKED"))
        XCTAssertFalse(CertificateProblem.isCertificateError("net::ERR_INTERNET_DISCONNECTED"))
        XCTAssertEqual(CertificateProblem.code(forURLErrorCode: -1202), "net::ERR_CERT_AUTHORITY_INVALID")
        XCTAssertNil(CertificateProblem.code(forURLErrorCode: -1009))
    }
}

// MARK: find_saved_web_login_test.dart, is_pinned_certificate_test.dart, mini_app_permissions_test.dart (resolve)

final class MiniAppSecurityTests: XCTestCase {
    private func account(type: ProviderType = .zentao, baseUrl: String? = "https://zentao.example.com", ref: String? = "secret:a") -> Account {
        Account(id: "a", workspaceId: "w", providerType: type, handle: "Dyno", baseUrl: baseUrl, credentialsRef: ref)
    }

    private func login(_ accounts: [Account], _ url: String?, vault: [String: String] = ["secret:a": "pw"]) async -> SavedWebLogin? {
        await FindSavedWebLogin(accounts: { accounts }, secret: { vault[$0] })(url.flatMap(URL.init(string:))).value ?? nil
    }

    func testGivesTheLoginOnTheLoginPageOfTheAccountsServer() async {
        let found = await login([account()], "https://zentao.example.com/user-login.html")
        XCTAssertEqual(found, SavedWebLogin(account: "Dyno", password: "pw"))
    }

    func testKnowsTheLoginPageInEachURLStyle() async {
        for url in ["https://zentao.example.com/zentao/user-login-L3plbnRhby8=.html", "https://zentao.example.com/index.php?m=user&f=login"] {
            let found = await login([account()], url)
            XCTAssertNotNil(found, url)
        }
    }

    func testAnotherPageOfTheSameServerGetsNothing() async {
        for url in ["https://zentao.example.com/", "https://zentao.example.com/user-edit-1.html", "https://zentao.example.com/my-changepassword.html",
                    "https://zentao.example.com/index.php?m=user&f=delete"] {
            let found = await login([account()], url)
            XCTAssertNil(found, url)
        }
    }

    func testDefaultPortCountsAsTheSchemesOwn() async {
        let found = await login([account(baseUrl: "https://zentao.example.com:443")], "https://zentao.example.com/user-login.html")
        XCTAssertNotNil(found)
    }

    func testAnotherHostPortOrSchemeGetsNothing() async {
        for url in ["https://zentao.example.com.evil.io/user-login.html", "https://evil.zentao.example.com/user-login.html",
                    "https://zentao.example.com:8443/user-login.html", "http://zentao.example.com/user-login.html"] {
            let found = await login([account()], url)
            XCTAssertNil(found, url)
        }
        let none = await login([account()], nil)
        XCTAssertNil(none)
    }

    func testOnlyAZenTaoAccountWithASavedPasswordCounts() async {
        let page = "https://zentao.example.com/user-login.html"
        let gitlab = await login([account(type: .gitlab)], page)
        let noRef = await login([account(ref: nil)], page)
        let emptyVault = await login([account()], page, vault: [:])
        XCTAssertNil(gitlab); XCTAssertNil(noRef); XCTAssertNil(emptyVault)
    }

    private struct Pins: PinnedCertificateSource {
        var result: Outcome<Set<String>>
        func fingerprints() async -> Outcome<Set<String>> { result }
    }

    func testPinnedCertificate() async {
        let der = Data([1, 2, 3, 4])
        // SHA-256 of 01020304, upper-case hex.
        let fp = "9F64A747E1B97F131FABB6B447296C9B6F0201E79FB3C5356E6C77E89B6A806A"
        let ok = await IsPinnedCertificate(Pins(result: .success([fp])))(der)
        let other = await IsPinnedCertificate(Pins(result: .success([fp])))(Data([9, 9]))
        let unreadable = await IsPinnedCertificate(Pins(result: .failure(.storage("x"))))(der)
        let empty = await IsPinnedCertificate(Pins(result: .success([])))(der)
        let blank = await IsPinnedCertificate(Pins(result: .success([fp])))(Data())
        XCTAssertTrue(ok); XCTAssertFalse(other); XCTAssertFalse(unreadable); XCTAssertFalse(empty); XCTAssertFalse(blank)
    }

    func testResolvePermission() async {
        let repo = FakePermissions()
        let resolve = ResolveMiniAppPermission(repo)
        let none = await resolve("a", [.notifications])
        XCTAssertNil(none, "asks when nothing is remembered")
        repo.answers["a|notifications"] = .allow
        let allow = await resolve("a", [.notifications])
        XCTAssertEqual(allow, .allow)
        repo.answers["a|camera"] = .block
        let mixed = await resolve("a", [.notifications, .camera])
        XCTAssertEqual(mixed, .block, "allowed only when all are")
        let partial = await resolve("a", [.notifications, .microphone])
        XCTAssertNil(partial, "asks when any kind was never answered")
        repo.failRead = true
        let failing = await resolve("a", [.notifications])
        XCTAssertNil(failing, "a storage failure asks rather than silently granting")
    }
}
