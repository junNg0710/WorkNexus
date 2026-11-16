import CoreDomain
import WebKit
import XCTest
@testable import FeatureMiniApps

/// Keeping session cookies between runs (new, no Dart counterpart). The web view and the keychain are doubles throughout.

final class FakeCookieSource: WebViewCookieSource, @unchecked Sendable {
    private let state = Locked<(cookies: Outcome<[BrowserCookie]>, listeners: [AsyncStream<Void>.Continuation])>((.success([]), []))
    var cookies: Outcome<[BrowserCookie]> {
        get { state.withLock { $0.cookies } }
        set { state.withLock { $0.cookies = newValue } }
    }
    func all() async -> Outcome<[BrowserCookie]> { cookies }
    func changes() -> AsyncStream<Void> { AsyncStream { c in state.withLock { $0.listeners.append(c) } } }
    /// The web view's cookies changed.
    func change() { state.withLock { $0.listeners }.forEach { $0.yield(()) } }
}

/// A store that counts its writes and can hold a read back until told to go on.
final class CountingSessionStore: SessionCookieStore, @unchecked Sendable {
    let inner: KeychainSessionCookieStore
    let items = InMemoryKeychainItemStore()
    private let counts = Locked<(saves: Int, gate: CheckedContinuation<Void, Never>?, held: Bool)>((0, nil, false))
    init() { inner = KeychainSessionCookieStore(items: items) }

    var saves: Int { counts.withLock { $0.saves } }
    /// Makes the next `load` wait for `open()`.
    func hold() { counts.withLock { $0.held = true } }
    func open() { counts.withLock { s in s.held = false; s.gate?.resume(); s.gate = nil } }

    func load() async -> Outcome<[BrowserCookie]> {
        if counts.withLock({ $0.held }) { await withCheckedContinuation { c in counts.withLock { $0.gate = c } } }
        return await inner.load()
    }
    func save(_ cookies: [BrowserCookie]) async -> Outcome<Void> { counts.withLock { $0.saves += 1 }; return await inner.save(cookies) }
}

private func session(_ name: String, _ domain: String, value: String = "v", httpOnly: Bool = true) -> BrowserCookie {
    BrowserCookie(name: name, value: value, domain: domain, path: "/", expires: nil, secure: true, httpOnly: httpOnly, sameSite: .lax)
}
private func lasting(_ name: String, _ domain: String) -> BrowserCookie {
    BrowserCookie(name: name, value: "v", domain: domain, expires: Date().addingTimeInterval(86_400))
}

@MainActor
final class SessionCookieTests: XCTestCase {
    private func harness() async throws -> Harness {
        let h = try await Harness()
        await h.seed([app("work", "https://app.work.io/#/home"), app("lan", "http://192.168.1.20:8080")])
        return h
    }

    private func parts(_ h: Harness, imports: FixtureImports = FixtureImports(), source: FakeCookieSource = FakeCookieSource(),
                       web: FixtureWebCookies = FixtureWebCookies(), store: CountingSessionStore = CountingSessionStore(),
                       debounce: Duration = .milliseconds(40)) -> (SessionCookieKeeper, FakeCookieSource, FixtureWebCookies, CountingSessionStore) {
        let sites = SessionCookieSites(h.feature.apps, imports)
        let keeper = SessionCookieKeeper(restore: RestoreSessionCookies(store, web, sites), snapshot: SnapshotSessionCookies(source, store, sites),
                                         forget: ForgetSessionCookies(store), changes: { source.changes() }, debounce: debounce)
        return (keeper, source, web, store)
    }

    func testOnlySessionCookiesOfTheKeptSitesAreSelected() {
        let picked = SessionCookieSnapshot.select([
            session("sid", "app.work.io"), session("sso", ".work.io"), session("sid", "app.work.io", value: "dup"), lasting("remember", "app.work.io"),
            session("sid", "tracker.ads.com"), session("sid", "work.io.evil.com"), session("lan", "192.168.1.20"), session("", "work.io"),
        ], sites: ["work.io", "192.168.1.20"])
        XCTAssertEqual(picked.map { "\($0.domain) \($0.name) \($0.value)" }, [".work.io sso v", "192.168.1.20 lan v", "app.work.io sid v"])
    }

    func testTheKeptSitesAreTheMiniAppsAndTheImportedOnes() async throws {
        let h = try await harness()
        let imports = FixtureImports()
        imports.items = [CookieImport(site: "github.com", source: chromeSource, importedAt: Date(), keys: [])]
        let sites = await SessionCookieSites(h.feature.apps, imports)()
        XCTAssertEqual(sites, ["work.io", "192.168.1.20", "github.com"])
    }

    func testTheSnapshotIsOneKeychainItemAndComesBackWhole() async throws {
        let store = CountingSessionStore()
        let cookies = [session("sid", ".work.io"), BrowserCookie(name: "t", value: "a=b; \"q\" ✓", domain: "app.work.io", path: "/x", sameSite: .strict)]
        _ = try got(await store.save(cookies))
        XCTAssertEqual(try store.items.entries().map(\.account), ["session-cookies"])
        let back = try got(await store.load())
        XCTAssertEqual(back, cookies)
        // None kept removes the item; a damaged item keeps nothing.
        _ = try got(await store.save([]))
        XCTAssertEqual(try store.items.entries(), [])
        try store.items.set(account: "session-cookies", label: "", data: Data("not json".utf8))
        let damaged = try got(await store.load())
        XCTAssertEqual(damaged, [])
    }

    func testSnapshotWritesOnlyWhenTheSessionCookiesChanged() async throws {
        let h = try await harness()
        let (_, source, _, store) = parts(h)
        let snapshot = SnapshotSessionCookies(source, store, SessionCookieSites(h.feature.apps, FixtureImports()))
        source.cookies = .success([session("sid", "app.work.io"), lasting("ga", "app.work.io"), session("x", "other.com")])
        let first = try got(await snapshot())
        XCTAssertEqual(first.map(\.name), ["sid"])
        XCTAssertEqual(store.saves, 1)
        // An analytics cookie came and went: the session cookies are the same, nothing is written.
        source.cookies = .success([session("sid", "app.work.io"), lasting("ga2", "app.work.io")])
        _ = try got(await snapshot(previous: first))
        XCTAssertEqual(store.saves, 1)
        // The site signed the user out (its cookie is gone): the kept copy goes too.
        source.cookies = .success([])
        _ = try got(await snapshot(previous: first))
        let kept = try got(await store.load())
        XCTAssertEqual(kept, [])
    }

    func testAnEmptyAnswerWhileQuittingOrAFailedReadNeverWipesWhatIsKept() async throws {
        let h = try await harness()
        let (_, source, _, store) = parts(h)
        let snapshot = SnapshotSessionCookies(source, store, SessionCookieSites(h.feature.apps, FixtureImports()))
        source.cookies = .success([session("sid", "app.work.io")])
        let first = try got(await snapshot())
        source.cookies = .success([])
        _ = try got(await snapshot(previous: first, allowEmpty: false))
        source.cookies = .failure(.storage("gone"))
        guard case .failure = await snapshot(previous: first) else { return XCTFail("expected the failure") }
        let kept = try got(await store.load())
        XCTAssertEqual(kept.map(\.name), ["sid"])
    }

    func testRestorePutsBackWhatIsMissingAndDropsTheSitesNoLongerKept() async throws {
        let h = try await harness()
        let (_, _, web, store) = parts(h)
        _ = await store.save([session("sid", "app.work.io"), session("sso", ".work.io"), session("old", "removed-app.com")])
        // The web view already has `sso` (a newer one): it is left alone.
        web.presentKeys = [CookieKey(host: "work.io", path: "/", name: "sso")]
        let restore = RestoreSessionCookies(store, web, SessionCookieSites(h.feature.apps, FixtureImports()))
        let kept = try got(await restore())
        XCTAssertEqual(kept.map(\.name), ["sso", "sid"])
        XCTAssertEqual(web.written.map { $0.map(\.name) }, [["sid"]])
        XCTAssertNil(web.written[0][0].expires, "it goes back as a session cookie")
        let left = try got(await store.load())
        XCTAssertEqual(Set(left.map(\.domain)), [".work.io", "app.work.io"])
    }

    func testTheKeeperRestoresFirstThenCopiesAMomentAfterEachChange() async throws {
        let h = try await harness()
        let (keeper, source, web, store) = parts(h)
        _ = await store.save([session("sid", "app.work.io")])
        store.hold()
        XCTAssertTrue(keeper.isReady, "never started: nothing waits (a test, the demo build)")
        keeper.start()
        XCTAssertFalse(keeper.isReady)
        var waited = false
        let waiter = Task { await keeper.ready(); waited = true }
        try await Task.sleep(for: .milliseconds(80))
        XCTAssertFalse(waited, "a page waits for the kept cookies")
        store.open()
        await waiter.value
        XCTAssertTrue(keeper.isReady)
        XCTAssertEqual(web.written.map { $0.map(\.name) }, [["sid"]])
        // A burst of changes is one copy.
        let before = store.saves
        source.cookies = .success([session("sid", "app.work.io", value: "next"), session("csrf", "app.work.io", httpOnly: false)])
        for _ in 0..<5 { source.change() }
        await h.settle { store.saves == before + 1 }
        try await Task.sleep(for: .milliseconds(120))
        XCTAssertEqual(store.saves, before + 1)
        let kept = try got(await store.load())
        XCTAssertEqual(kept.map { "\($0.name)=\($0.value)" }, ["csrf=v", "sid=next"])
        // Quitting: a last copy, even with a change still waiting for its moment.
        source.cookies = .success([session("sid", "app.work.io", value: "last")])
        source.change()
        await keeper.stop()
        let last = try got(await store.load())
        XCTAssertEqual(last.map(\.value), ["last"])
    }

    func testARemovedMiniAppAForgottenImportAndClearAllDropWhatWasKept() async throws {
        let h = try await harness()
        let imports = FixtureImports()
        imports.items = [CookieImport(site: "github.com", source: chromeSource, importedAt: Date(), keys: [])]
        let (keeper, source, _, store) = parts(h, imports: imports)
        h.model.sessionCookies = keeper
        keeper.start()
        await keeper.ready()
        source.cookies = .success([session("sid", "app.work.io"), session("lan", "192.168.1.20"), session("gh", ".github.com")])
        await keeper.snapshotNow()
        do { let kept = try got(await store.load()); XCTAssertEqual(kept.map(\.name), ["gh", "lan", "sid"]) }
        // The mini app is removed: its site is no longer kept (the web view still has the cookie).
        await h.model.remove("lan")
        do { let kept = try got(await store.load()); XCTAssertEqual(kept.map(\.name), ["gh", "sid"]) }
        // The imported site is forgotten.
        let cookies = CookieImportModel(browsers: FixtureBrowsers(), webView: FixtureWebCookies(), imports: imports,
                                        importCookies: ImportBrowserCookies(FixtureBrowsers(), FixtureWebCookies(), imports),
                                        check: CheckCookieImports(imports, FixtureWebCookies()), model: h.model)
        _ = await cookies.forget(site: "github.com")
        do { let kept = try got(await store.load()); XCTAssertEqual(kept.map(\.name), ["sid"]) }
        // "Clear all browsing data".
        let data = MiniAppBrowsingDataModel(data: NoopBrowsingData(), model: h.model)
        let cleared = await data.clearAll(h.model.apps)
        XCTAssertTrue(cleared)
        XCTAssertEqual(try store.items.entries(), [])
    }

    func testAMiniAppsFirstPageWaitsForTheKeptCookies() async throws {
        let h = try await Harness()
        let a = app("blank", "about:blank")
        await h.seed([a])
        let (keeper, _, _, store) = parts(h)
        h.model.sessionCookies = keeper
        store.hold()
        keeper.start()
        let parts = MiniAppWebParts.make(app: a, model: h.model, browser: h.model.browserModel(for: a))
        try await Task.sleep(for: .milliseconds(150))
        XCTAssertNil(parts.web.url, "nothing loads until the session cookies are back")
        store.open()
        await h.settle { parts.web.url != nil }
        XCTAssertEqual(parts.web.url?.absoluteString, "about:blank")
    }

    /// The real plumbing, in the test runner's own web profile (not the app's, and no site is opened): a session cookie set
    /// in the web view's store is announced by `WKHTTPCookieStoreObserver` and read back as a session cookie.
    func testTheWebViewsCookieStoreAnnouncesAndListsASessionCookie() async throws {
        let repo = WKWebViewCookieRepository()
        let name = "wn_test_\(UUID().uuidString.prefix(8))"
        let cookie = BrowserCookie(name: name, value: "1", domain: "session-test.invalid", path: "/", secure: true, httpOnly: true)
        let heard = Locked(false)
        let listening = Task { for await _ in repo.changes() { heard.withLock { $0 = true } } }
        defer { listening.cancel() }
        try await Task.sleep(for: .milliseconds(200))
        _ = try got(await repo.write([cookie]))
        let store = WKWebsiteDataStore.default().httpCookieStore
        for _ in 0..<200 where !heard.withLock({ $0 }) { try await Task.sleep(for: .milliseconds(25)) }
        let all = try got(await repo.all())
        for http in await store.allCookies() where http.name == name { await store.deleteCookie(http) }
        guard let found = all.first(where: { $0.name == name }) else { throw XCTSkip("the web view's cookie store is not available here") }
        XCTAssertNil(found.expires); XCTAssertTrue(found.httpOnly)
        XCTAssertEqual(SessionCookieSnapshot.select(all, sites: ["session-test.invalid"]).map(\.name), [name])
        XCTAssertTrue(heard.withLock { $0 }, "the change was announced")
    }

    func testAWebViewCookieIsMappedBothWays() throws {
        let kept = session("sid", ".work.io")
        let http = try XCTUnwrap(WebViewCookieDataSource.httpCookie(kept))
        XCTAssertTrue(http.isSessionOnly); XCTAssertTrue(http.isHTTPOnly); XCTAssertTrue(http.isSecure)
        XCTAssertEqual(WebViewCookieDataSource.browserCookie(http), kept)
        let persistent = try XCTUnwrap(WebViewCookieDataSource.httpCookie(lasting("ga", "app.work.io")))
        XCTAssertNotNil(WebViewCookieDataSource.browserCookie(persistent).expires, "a cookie with an expiry is not a session cookie")
    }
}

private final class NoopBrowsingData: MiniAppBrowsingDataRepository, @unchecked Sendable {
    let canClear = true
    func clearCache() async -> Outcome<Void> { .success(()) }
    func clearSite(url: String) async -> Outcome<Void> { .success(()) }
    func clearAll(urls: [String]) async -> Outcome<Void> { .success(()) }
}
