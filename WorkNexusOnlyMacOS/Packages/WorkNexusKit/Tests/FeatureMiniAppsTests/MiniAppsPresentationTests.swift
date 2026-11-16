import CoreDomain
import CorePersistence
import CoreUI
import WebKit
import XCTest
@testable import FeatureMiniApps

final class FakeNotifier: DesktopNotifying, @unchecked Sendable {
    private let lock = NSLock()
    private var continuations: [AsyncStream<String>.Continuation] = []
    private(set) var shown: [(id: Int, title: String, body: String, payload: String?)] = []
    var taps: AsyncStream<String> { AsyncStream { c in lock.withLock { continuations.append(c) } } }
    func tap(_ payload: String) { lock.lock(); let cs = continuations; lock.unlock(); cs.forEach { $0.yield(payload) } }
    func initialize() async -> Bool { true }
    func permissionGranted() async -> Bool? { true }
    func requestPermission() async -> Bool { true }
    func openSystemSettings() {}
    func show(id: Int, title: String, body: String, payload: String?) async { lock.withLock { shown.append((id, title, body, payload)) } }
}

@MainActor
struct Harness {
    let feature: MiniAppsFeature
    let model: MiniAppsModel
    let notifier = FakeNotifier()
    let router = LinkRouter()
    let db: AppDatabase
    let dir: URL

    init(accounts: [Account] = [], vault: [String: String] = [:], liveLimit: Int = 3) async throws {
        db = try AppDatabase.inMemory(registrars: [MiniAppsMigrations.registrar])
        dir = FileManager.default.temporaryDirectory.appendingPathComponent("miniapps_ui_\(UUID().uuidString)")
        let store = InMemoryCredentialStore()
        for (k, v) in vault { _ = await store.write(k, value: v) }
        feature = MiniAppsFeature.make(database: db, accounts: { accounts }, credentials: store, notifier: notifier,
                                       settings: MiniAppsSettings(liveLimit: { liveLimit }), supportDirectory: dir, router: router,
                                       // Never the real keychain: saved passwords and session cookies stay in memory.
                                       secrets: .inMemory())
        model = feature.model
    }

    func seed(_ apps: [MiniApp]) async {
        for a in apps { _ = await feature.apps.save(a) }
        model.start()
        await settle { model.apps.count == apps.count }
    }

    func settle(_ ok: @MainActor () -> Bool) async {
        for _ in 0..<300 where !ok() { try? await Task.sleep(for: .milliseconds(10)) }
    }
}

// MARK: mini_apps_host.dart, mini_app_rail_section_test.dart

@MainActor
final class MiniAppsModelTests: XCTestCase {
    func testRailItemsFollowTheDatabaseAndTheSelection() async throws {
        let h = try await Harness()
        await h.seed([app("a", "https://a.io", position: 0), app("b", "https://b.io", position: 1)])
        XCTAssertEqual(h.model.railItems.map(\.id), ["a", "b"])
        XCTAssertEqual(h.model.railItems.map(\.selected), [false, false])
        h.model.show("b")
        XCTAssertEqual(h.model.railItems.map(\.selected), [false, true])
        XCTAssertEqual(h.model.railItems.map(\.running), [false, true])
        h.model.show(nil)
        XCTAssertFalse(h.model.onScreen)
        XCTAssertEqual(h.model.liveIds, ["b"], "a page left keeps running")
        XCTAssertEqual(h.model.railItems.map(\.selected), [false, false])
    }

    func testKeepsOnlyTheLimitEvictingTheLongestUnused() async throws {
        let h = try await Harness(liveLimit: 2)
        await h.seed([app("a", "https://a.io"), app("b", "https://b.io"), app("c", "https://c.io")])
        h.model.show("a"); h.model.show("b"); h.model.show("c")
        XCTAssertEqual(h.model.liveIds, ["b", "c"])
        h.model.show("b")
        XCTAssertEqual(h.model.liveIds, ["c", "b"])
        h.model.close("c")
        XCTAssertEqual(h.model.liveIds, ["b"])
    }

    func testARemovedAppIsDroppedFromTheRunningOnes() async throws {
        let h = try await Harness()
        await h.seed([app("a", "https://a.io"), app("b", "https://b.io")])
        h.model.show("a"); h.model.show("b")
        await h.model.remove("a")
        await h.settle { h.model.apps.count == 1 }
        XCTAssertEqual(h.model.liveIds, ["b"])
        XCTAssertEqual(h.model.apps.map(\.id), ["b"])
    }

    func testMoveRenumbersTheRail() async throws {
        let h = try await Harness()
        await h.seed([app("a", "https://a.io", position: 0), app("b", "https://b.io", position: 1)])
        await h.model.move(from: 0, to: 1)
        XCTAssertEqual(h.model.apps.map(\.id), ["b", "a"])
        await h.settle { h.model.apps.first?.id == "b" }
        XCTAssertEqual(h.model.apps.first?.id, "b")
    }

    func testATappedLinkOpensInTheMiniAppOfThatSite() async throws {
        let h = try await Harness()
        await h.seed([app("work", "https://work.io"), app("sub", "https://a.work.io")])
        var shown: [String] = []
        h.model.requestShow = { shown.append($0) }
        XCTAssertTrue(h.model.handle("https://a.work.io/board/1"))
        XCTAssertFalse(h.model.handle("https://elsewhere.io/x"))
        XCTAssertEqual(shown, ["sub"])
        // The app was not running: its page starts on the link, once.
        let browser = h.model.browserModel(for: h.model.apps.first { $0.id == "sub" }!)
        XCTAssertEqual(browser.initialUrl, "https://a.work.io/board/1")
    }

    func testLinksReachTheModelThroughTheRouterAsTheMiniAppStage() async throws {
        let h = try await Harness()
        await h.seed([app("work", "https://work.io")])
        XCTAssertTrue(h.router.route("https://work.io/x"))
        XCTAssertFalse(h.router.route("https://work.io/x", skip: [.miniApp]))
        h.model.stop()
        XCTAssertFalse(h.router.route("https://work.io/x"))
    }

    func testAPageOpenedWindowThatIsASignInOrTheAppsOwnSiteStaysAPopUp() async throws {
        let h = try await Harness()
        await h.seed([app("work", "https://work.io"), app("other", "https://other.io")])
        // Never carried off, whatever site has a mini app.
        XCTAssertFalse(h.model.routeWindowLink("https://other.io/oauth/authorize", currentAppId: "work", width: nil, height: nil))
        XCTAssertFalse(h.model.routeWindowLink("https://other.io/x", currentAppId: "work", width: 500, height: 600))
        // Its own links stay in its window; another site's mini app takes a plain link.
        XCTAssertFalse(h.model.routeWindowLink("https://work.io/x", currentAppId: "work", width: nil, height: nil))
        XCTAssertTrue(h.model.routeWindowLink("https://other.io/x", currentAppId: "work", width: nil, height: nil))
        XCTAssertFalse(h.model.routeWindowLink("https://nowhere.io/x", currentAppId: "work", width: nil, height: nil))
    }

    func testATappedNotificationBringsItsAppForward() async throws {
        let h = try await Harness()
        await h.seed([app("a", "https://a.io")])
        var shown: [String] = []; var front = 0
        h.model.requestShow = { shown.append($0) }; h.model.bringToFront = { front += 1 }
        h.notifier.tap("chat:12")                       // some other feature's payload
        h.notifier.tap(miniAppNotificationPayload("a"))
        await h.settle { !shown.isEmpty }
        XCTAssertEqual(shown, ["a"]); XCTAssertEqual(front, 1)
        XCTAssertEqual(miniAppId(ofNotificationPayload: "mini:abc"), "abc")
        XCTAssertNil(miniAppId(ofNotificationPayload: "chat:abc"))
    }

    func testTrustedCertificatesAreRememberedBySite() async throws {
        let h = try await Harness()
        let before = await h.model.isTrusted("https://a.io:443")
        XCTAssertFalse(before)
        _ = await h.feature.trustedCertificates.trust(origin: "https://a.io:443", error: "e")
        let loaded = await h.model.isTrusted("https://a.io:443")      // first use reads the file
        XCTAssertTrue(loaded)
        XCTAssertEqual(MiniAppsModel.origin(of: URL(string: "https://a.io/x")), "https://a.io:443")
        XCTAssertEqual(MiniAppsModel.origin(of: URL(string: "https://a.io:8443/x")), "https://a.io:8443")
        XCTAssertNil(MiniAppsModel.origin(of: URL(string: "http://a.io")))
        XCTAssertNil(MiniAppsModel.origin(of: nil))
    }
}

// MARK: ask_mini_app_permission_test.dart

@MainActor
final class MiniAppPermissionPrompterTests: XCTestCase {
    func testBlocksAPageOnAnotherSiteWithoutAsking() async throws {
        let h = try await Harness()
        await h.seed([app("a", "https://a.io")])
        let prompter = MiniAppPermissionPrompter(model: h.model)
        var asked = 0
        prompter.present = { _, _ in asked += 1; return .allow }
        let answer = await prompter.ask(app: app("a", "https://a.io"), kinds: [.camera], origin: URL(string: "https://evil.io"))
        XCTAssertEqual(answer, .block); XCTAssertEqual(asked, 0)
        let none = await prompter.ask(app: app("a", "https://a.io"), kinds: [MiniAppPermissionKind](), origin: URL(string: "https://a.io"))
        XCTAssertEqual(none, .block)
    }

    func testAsksOnceWhenShownThenRemembers() async throws {
        let h = try await Harness()
        await h.seed([app("a", "https://a.io")])
        h.model.show("a")
        let prompter = MiniAppPermissionPrompter(model: h.model)
        var asked: [(String, [MiniAppPermissionKind])] = []
        prompter.present = { site, kinds in asked.append((site, kinds)); return .allow }
        let a = app("a", "https://a.io")
        let first = await prompter.ask(app: a, kinds: [.microphone, .camera], origin: URL(string: "https://a.io/x"))
        let again = await prompter.ask(app: a, kinds: [.camera, .microphone], origin: URL(string: "https://a.io/y"))
        XCTAssertEqual(first, .allow); XCTAssertEqual(again, .allow)
        XCTAssertEqual(asked.count, 1)
        XCTAssertEqual(asked.first?.0, "a.io"); XCTAssertEqual(asked.first?.1, [.camera, .microphone], "asked in a fixed order")
        let remembered = await h.feature.permissions.decision(miniAppId: "a", kind: .camera).value ?? nil
        XCTAssertEqual(remembered, .allow)
    }

    func testADismissedDialogBlocksOnceWithoutRemembering() async throws {
        let h = try await Harness()
        await h.seed([app("a", "https://a.io")])
        h.model.show("a")
        let prompter = MiniAppPermissionPrompter(model: h.model)
        prompter.present = { _, _ in nil }
        let answer = await prompter.ask(app: app("a", "https://a.io"), kinds: [.notifications], origin: URL(string: "https://a.io"))
        XCTAssertEqual(answer, .block)
        let remembered = await h.feature.permissions.decision(miniAppId: "a", kind: .notifications).value ?? nil
        XCTAssertNil(remembered)
    }

    func testAPageInTheBackgroundIsAskedOnlyOnceItsAppIsShown() async throws {
        let h = try await Harness()
        await h.seed([app("a", "https://a.io"), app("b", "https://b.io")])
        h.model.show("b")
        let prompter = MiniAppPermissionPrompter(model: h.model)
        var asked = 0
        prompter.present = { _, _ in asked += 1; return .block }
        let pending = Task { await prompter.ask(app: app("a", "https://a.io"), kinds: [.location], origin: URL(string: "https://a.io")) }
        try await Task.sleep(for: .milliseconds(150))
        XCTAssertEqual(asked, 0, "not over whatever the user is looking at")
        h.model.show("a")
        let answer = await pending.value
        XCTAssertEqual(answer, .block); XCTAssertEqual(asked, 1)
    }

    func testTwoRequestsAtOnceShareOneDialog() async throws {
        let h = try await Harness()
        await h.seed([app("a", "https://a.io")])
        h.model.show("a")
        let prompter = MiniAppPermissionPrompter(model: h.model)
        var asked = 0
        prompter.present = { _, _ in asked += 1; try? await Task.sleep(for: .milliseconds(80)); return .allow }
        let a = app("a", "https://a.io"); let o = URL(string: "https://a.io")
        async let x = prompter.ask(app: a, kinds: [.camera], origin: o)
        async let y = prompter.ask(app: a, kinds: [.camera], origin: o)
        let (r1, r2) = await (x, y)
        XCTAssertEqual([r1, r2], [.allow, .allow]); XCTAssertEqual(asked, 1)
    }

    func testKindsMapFromTheWebViewsMediaCapture() {
        XCTAssertEqual(miniAppPermissionKinds(of: .camera), [.camera])
        XCTAssertEqual(miniAppPermissionKinds(of: .cameraAndMicrophone), [.camera, .microphone])
        XCTAssertEqual(MiniAppPermissionKind.camera.systemImage, "camera")
    }
}

// MARK: mini_app_browser_controller_test.dart, login_capability_script_test.dart

@MainActor
final class MiniAppBrowserModelTests: XCTestCase {
    func testStartsOnTheLastPageAndSavesNewOnesAfterTheyFlush() async throws {
        let h = try await Harness()
        var a = app("a", "https://a.io"); a.lastUrl = "https://a.io/last"
        await h.seed([a])
        let browser = h.model.browserModel(for: a)
        XCTAssertEqual(browser.initialUrl, "https://a.io/last")
        XCTAssertTrue(h.model.browserModel(for: a) === browser, "one per running app")
        browser.onVisited(URL(string: "https://a.io/next")!, canGoBack: true, canGoForward: false)
        browser.onVisited(URL(string: "about:blank")!, canGoBack: true, canGoForward: false)   // not a web page: not kept
        XCTAssertEqual(browser.address, "about:blank"); XCTAssertTrue(browser.canGoBack)
        h.model.close("a")                                       // closing the app writes the page now
        await h.settle { h.model.apps.first?.lastUrl == "https://a.io/next" }
        XCTAssertEqual(h.model.apps.first?.lastUrl, "https://a.io/next")
    }

    func testReportsProgressErrorsAndNavigation() async throws {
        let h = try await Harness()
        let browser = MiniAppBrowserModel(appId: "a", initialUrl: "https://a.io", apps: h.feature.apps)
        XCTAssertFalse(browser.loading)
        browser.onProgress(0.4); XCTAssertTrue(browser.loading)
        browser.onError("offline"); XCTAssertEqual(browser.loadError, "offline")
        browser.onCertificateError(origin: "https://a.io:443", error: "net::ERR_CERT_DATE_INVALID")
        browser.onLoadStart(); XCTAssertNil(browser.loadError); XCTAssertNil(browser.certificateError)
        browser.goBack(); browser.goForward()                    // nothing to drive: no crash
    }

    func testScriptsCarryTheirTokenAndTalkThroughTheBridge() {
        let n = MiniAppNotificationCapability(token: "tok-1", notifier: FakeNotifier(), isWindowFocused: { false })
        let source = n.script?.source ?? ""
        XCTAssertTrue(source.contains("'tok-1'")); XCTAssertFalse(source.contains("__TOKEN__"))
        XCTAssertTrue(source.contains("webkit.messageHandlers.wnBridge"))
        XCTAssertEqual(n.script?.atDocumentStart, true)
        let l = MiniAppLoginCapability(token: "tok-2")
        XCTAssertTrue(l.script?.source.contains("'tok-2'") == true)
        XCTAssertEqual(l.script?.atDocumentStart, false)
        XCTAssertNotEqual(newMiniAppPageToken(), newMiniAppPageToken())
        XCTAssertEqual(newMiniAppPageToken().count, 32)
        XCTAssertEqual(MiniAppNotificationCapability.stableId("a", "t"), MiniAppNotificationCapability.stableId("a", "t"))
        XCTAssertNotEqual(MiniAppNotificationCapability.stableId("a", "t"), MiniAppNotificationCapability.stableId("a", "u"))
    }
}

// MARK: The scripts, the bridge and the capabilities in a real WKWebView

@MainActor
final class MiniAppWebViewIntegrationTests: XCTestCase {
    private func load(_ html: String, base: String, parts: MiniAppWebParts) async throws {
        parts.web.frame = NSRect(x: 0, y: 0, width: 800, height: 600)
        parts.web.loadHTMLString(html, baseURL: URL(string: base))
        for _ in 0..<500 where parts.web.isLoading || parts.web.url == nil { try await Task.sleep(for: .milliseconds(10)) }
        if parts.web.isLoading || parts.web.url == nil { throw XCTSkip("WebKit did not load a page in this environment") }
    }

    private func js(_ web: WKWebView, _ source: String) async throws -> Any? {
        try await web.evaluateJavaScript(source)
    }

    private func zentao() -> (Account, [String: String]) {
        (Account(id: "z", workspaceId: "w", providerType: .zentao, handle: "dyno", baseUrl: "https://zentao.example.com", credentialsRef: "secret:z"), ["secret:z": "s3cret"])
    }

    func testTheLoginFormIsFilledWithTheSavedAccountAndSubmittedOnce() async throws {
        let (account, vault) = zentao()
        let h = try await Harness(accounts: [account], vault: vault)
        let a = app("z", "https://zentao.example.com")
        await h.seed([a])
        let browser = h.model.browserModel(for: a)
        let parts = MiniAppWebParts.make(app: a, model: h.model, browser: browser, loadInitialPage: false)
        let html = """
        <html><body><form id="f" onsubmit="window.__submitted=(window.__submitted||0)+1;return false">
        <input name="account" id="account"><input type="password" name="password"><button type="submit">Go</button></form></body></html>
        """
        try await load(html, base: "https://zentao.example.com/user-login.html", parts: parts)
        for _ in 0..<200 {
            if let n = try await js(parts.web, "window.__submitted || 0") as? Int, n > 0 { break }
            try await Task.sleep(for: .milliseconds(25))
        }
        do { let r = try await js(parts.web, "document.getElementById('account').value") as? String; XCTAssertEqual(r, "dyno") }
        do { let r = try await js(parts.web, "document.querySelector('input[name=password]').value") as? String; XCTAssertEqual(r, "s3cret") }
        do { let r = try await js(parts.web, "window.__submitted") as? Int; XCTAssertEqual(r, 1) }
    }

    func testAnotherServersLoginPageGetsNothing() async throws {
        let (account, vault) = zentao()
        let h = try await Harness(accounts: [account], vault: vault)
        let a = app("z", "https://evil.example.com")
        await h.seed([a])
        let parts = MiniAppWebParts.make(app: a, model: h.model, browser: h.model.browserModel(for: a), loadInitialPage: false)
        try await load("""
        <html><body><form><input name="account" id="account"><input type="password" name="password"></form></body></html>
        """, base: "https://evil.example.com/user-login.html", parts: parts)
        try await Task.sleep(for: .milliseconds(600))
        do { let r = try await js(parts.web, "document.querySelector('input[name=password]').value") as? String; XCTAssertEqual(r, "") }
    }

    func testNotificationShimReportsPermissionAndShowsAnOSNotificationOnlyWhenAllowed() async throws {
        let h = try await Harness()
        let a = app("n", "https://chat.example.com")
        await h.seed([a])
        let parts = MiniAppWebParts.make(app: a, model: h.model, browser: h.model.browserModel(for: a), loadInitialPage: false)
        try await load("<html><body>hi</body></html>", base: "https://chat.example.com/", parts: parts)
        // Not asked yet: the page sees `default`, and a notification it raises is dropped.
        try await Task.sleep(for: .milliseconds(200))
        do { let r = try await js(parts.web, "typeof Notification === 'function' && Notification.permission") as? String; XCTAssertEqual(r, "default") }
        _ = try await js(parts.web, "new Notification('Hello', { body: 'World', tag: 't1' }); 1")
        try await Task.sleep(for: .milliseconds(300))
        XCTAssertTrue(h.notifier.shown.isEmpty)
        // The user allowed it (remembered): the same call becomes an OS notification that finds its app on tap.
        _ = await h.feature.permissions.save(MiniAppPermissionGrant(miniAppId: "n", kind: .notifications, decision: .allow))
        _ = try await js(parts.web, "new Notification('Hello', { body: 'World', tag: 't1' }); 1")
        await h.settle { !h.notifier.shown.isEmpty }
        let n = try XCTUnwrap(h.notifier.shown.first)
        XCTAssertEqual(n.title, "Hello"); XCTAssertEqual(n.body, "World"); XCTAssertEqual(n.payload, "mini:n")
        XCTAssertEqual(n.id, MiniAppNotificationCapability.stableId("n", "t1"))
    }

    func testAPageOnAnotherSiteIsAlwaysDeniedNotifications() async throws {
        let h = try await Harness()
        let a = app("n", "https://chat.example.com")
        await h.seed([a])
        _ = await h.feature.permissions.save(MiniAppPermissionGrant(miniAppId: "n", kind: .notifications, decision: .allow))
        let parts = MiniAppWebParts.make(app: a, model: h.model, browser: h.model.browserModel(for: a), loadInitialPage: false)
        try await load("<html><body>x</body></html>", base: "https://elsewhere.example.org/", parts: parts)
        try await Task.sleep(for: .milliseconds(300))
        do { let r = try await js(parts.web, "Notification.permission") as? String; XCTAssertEqual(r, "denied") }
        _ = try await js(parts.web, "new Notification('Hi'); 1")
        try await Task.sleep(for: .milliseconds(300))
        XCTAssertTrue(h.notifier.shown.isEmpty)
    }
}
