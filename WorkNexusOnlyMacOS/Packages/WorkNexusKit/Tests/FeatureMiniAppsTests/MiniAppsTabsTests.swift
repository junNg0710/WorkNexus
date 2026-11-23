import AppKit
import CoreDomain
import WebKit
import XCTest
@testable import FeatureMiniApps

// MARK: The tabs of a mini app

final class IsMiniAppSiteTests: XCTestCase {
    func testALinkOnTheAppsSiteOrItsRegistrableDomainIsTheSite() {
        let same = IsMiniAppSite()
        XCTAssertTrue(same("https://zentao.corp.com/a", "https://zentao.corp.com/b?x=1"))
        XCTAssertTrue(same("https://zentao.corp.com", "https://files.corp.com/x"), "another host of the same domain")
        XCTAssertTrue(same("https://zentao.corp.com", "http://corp.com/x"), "the scheme does not matter on the web")
        XCTAssertTrue(same("https://a.example.com.vn", "https://b.example.com.vn"), "a country domain's second level")
        XCTAssertFalse(same("https://a.example.com.vn", "https://b.other.com.vn"))
        XCTAssertFalse(same("https://zentao.corp.com", "https://corp.org/x"))
        XCTAssertFalse(same("https://zentao.corp.com", "https://evilcorp.com/x"))
    }

    func testOnlyWebLinksCount() {
        let same = IsMiniAppSite()
        XCTAssertFalse(same("https://corp.com", "about:blank"))
        XCTAssertFalse(same("https://corp.com", "javascript:alert(1)"))
        XCTAssertFalse(same("https://corp.com", "mailto:a@corp.com"))
        XCTAssertFalse(same("https://corp.com", ""))
        XCTAssertFalse(same("not a url", "https://corp.com"))
        XCTAssertTrue(same("http://localhost:3000", "http://localhost:4000/x"), "a host with no domain is itself")
        XCTAssertFalse(same("http://localhost:3000", "http://127.0.0.1:3000"))
    }
}

@MainActor
final class MiniAppTabsModelTests: XCTestCase {
    /// An app that is shown is kept running (a database change would otherwise close the pages of an app that is not).
    private func tabs(_ h: Harness, _ a: MiniApp) -> MiniAppTabsModel { h.model.show(a.id); return h.model.tabsModel(for: a) }

    func testAppStartsOnOneTabAndNewOnesJoinTheEnd() async throws {
        let h = try await Harness()
        let a = app("a", "https://a.io")
        await h.seed([a])
        let t = tabs(h, a)
        XCTAssertEqual(t.tabs.count, 1)
        XCTAssertTrue(h.model.tabsModel(for: a) === t, "one set per running app")
        XCTAssertFalse(t.canCloseTab)
        let second = try XCTUnwrap(t.newTab(url: "https://a.io/two"))
        XCTAssertEqual(t.tabs.count, 2); XCTAssertEqual(t.selected.id, second.id, "a new tab comes to the front")
        XCTAssertEqual(second.initialUrl, "https://a.io/two")
        let background = try XCTUnwrap(t.newTab(url: "https://a.io/three", select: false))
        XCTAssertEqual(t.selected.id, second.id); XCTAssertEqual(t.tabs.last?.id, background.id)
    }

    func testClosingTheSelectedTabLeavesItsNeighbourAndTheLastTabStays() async throws {
        let h = try await Harness()
        let a = app("a", "https://a.io")
        await h.seed([a])
        let t = tabs(h, a)
        let first = t.selected
        let second = try XCTUnwrap(t.newTab(url: "https://a.io/2"))
        let third = try XCTUnwrap(t.newTab(url: "https://a.io/3"))
        t.select(second.id)
        XCTAssertTrue(t.close(second.id))
        XCTAssertEqual(t.tabs.map(\.id), [first.id, third.id])
        XCTAssertEqual(t.selected.id, third.id, "the one that took its place")
        XCTAssertTrue(t.close(third.id)); XCTAssertEqual(t.selected.id, first.id)
        XCTAssertFalse(t.close(first.id), "the last tab is never closed this way")
        XCTAssertEqual(t.tabs.count, 1)
        XCTAssertFalse(t.close(UUID()))
    }

    func testClosingABackgroundTabKeepsTheSelection() async throws {
        let h = try await Harness()
        let a = app("a", "https://a.io")
        await h.seed([a])
        let t = tabs(h, a)
        let first = t.selected
        let second = try XCTUnwrap(t.newTab(url: "https://a.io/2", select: false))
        XCTAssertTrue(t.close(second.id)); XCTAssertEqual(t.selected.id, first.id)
    }

    func testSwitchingWrapsAround() async throws {
        let h = try await Harness()
        let a = app("a", "https://a.io")
        await h.seed([a])
        let t = tabs(h, a)
        let first = t.selected
        let second = try XCTUnwrap(t.newTab(url: "https://a.io/2")), third = try XCTUnwrap(t.newTab(url: "https://a.io/3"))
        XCTAssertEqual(t.selected.id, third.id)
        t.selectNext(); XCTAssertEqual(t.selected.id, first.id)
        t.selectPrevious(); XCTAssertEqual(t.selected.id, third.id)
        t.selectPrevious(); XCTAssertEqual(t.selected.id, second.id)
        t.select(UUID()); XCTAssertEqual(t.selected.id, second.id, "an unknown tab changes nothing")
    }

    func testTheLimitStopsNewTabs() async throws {
        let h = try await Harness()
        let a = app("a", "https://a.io")
        await h.seed([a])
        let t = tabs(h, a)
        for i in 1..<MiniAppTabsModel.maxTabs { XCTAssertNotNil(t.newTab(url: "https://a.io/\(i)")) }
        XCTAssertFalse(t.canOpenTab); XCTAssertEqual(t.tabs.count, MiniAppTabsModel.maxTabs)
        XCTAssertNil(t.newTab(url: "https://a.io/more")); XCTAssertNil(t.makeTab(url: "https://a.io/more"))
    }

    func testOnlyTheSelectedTabKeepsThePageToReopenOn() async throws {
        let h = try await Harness()
        let a = app("a", "https://a.io")
        await h.seed([a])
        let t = tabs(h, a)
        let first = t.selected
        first.onVisited(URL(string: "https://a.io/first")!, canGoBack: false, canGoForward: false)
        let second = try XCTUnwrap(t.newTab(url: "https://a.io/second"))
        second.onVisited(URL(string: "https://a.io/second")!, canGoBack: false, canGoForward: false)
        // Switching writes the page the first tab was on and starts keeping the second's.
        await h.settle { h.model.apps.first?.lastUrl == "https://a.io/first" }
        XCTAssertEqual(h.model.apps.first?.lastUrl, "https://a.io/first")
        first.onVisited(URL(string: "https://a.io/first-b")!, canGoBack: false, canGoForward: false)
        XCTAssertFalse(first.persistsLastUrl); XCTAssertTrue(second.persistsLastUrl)
        t.select(first.id)
        h.model.close("a")                                        // the app closes: the selected tab's page is written
        await h.settle { h.model.apps.first?.lastUrl == "https://a.io/first-b" }
        XCTAssertEqual(h.model.apps.first?.lastUrl, "https://a.io/first-b")
    }

    func testClosingTheAppTearsDownEveryTabAndItReopensOnOne() async throws {
        let h = try await Harness()
        let a = app("a", "https://a.io")
        await h.seed([a])
        h.model.show("a")
        let t = tabs(h, a)
        _ = t.newTab(url: "https://a.io/2")
        h.model.close("a")
        XCTAssertTrue(h.model.tabsModel(for: a) !== t); XCTAssertEqual(h.model.tabsModel(for: a).tabs.count, 1)
    }

    func testALinkOpensInTheSelectedTab() async throws {
        let h = try await Harness()
        await h.seed([app("a", "https://a.io")])
        let a = h.model.apps[0]
        let t = tabs(h, a)
        let first = t.selected, second = try XCTUnwrap(t.newTab(url: "https://a.io/2"))
        let d1 = FixturePageDriver(), d2 = FixturePageDriver()
        first.attach(d1); second.attach(d2)
        XCTAssertTrue(h.model.handle("https://a.io/board/1"))
        XCTAssertEqual(d2.loads, ["https://a.io/board/1"]); XCTAssertEqual(d1.loads, [])
    }

    func testImportingCookiesAndClearingDataReloadEveryTabOfTheApps() async throws {
        let h = try await Harness()
        await h.seed([app("a", "https://work.io"), app("b", "https://other.io")])
        let a = h.model.apps[0], b = h.model.apps[1]
        let ta = tabs(h, a), tb = tabs(h, b)
        let first = ta.selected
        let second = try XCTUnwrap(ta.newTab(url: "https://work.io/2"))
        let drivers = [FixturePageDriver(), FixturePageDriver(), FixturePageDriver()]
        first.attach(drivers[0]); second.attach(drivers[1]); tb.selected.attach(drivers[2])
        h.model.reloadRunningApps(ofSites: ["work.io"])
        XCTAssertEqual(drivers.map(\.reloads), [1, 1, 0])
        h.model.reloadRunningApps(ids: ["b"])
        XCTAssertEqual(drivers.map(\.reloads), [1, 1, 1])
    }

    func testAWindowOnTheAppsSiteIsATabButASignInOrAnotherSiteIsNot() async throws {
        let h = try await Harness()
        await h.seed([app("work", "https://zentao.corp.com")])
        let m = h.model
        XCTAssertTrue(m.opensAsTab("https://zentao.corp.com/task-view-1.html", appId: "work", width: nil, height: nil))
        XCTAssertTrue(m.opensAsTab("https://files.corp.com/a.pdf", appId: "work", width: nil, height: nil))
        XCTAssertFalse(m.opensAsTab("https://zentao.corp.com/oauth/authorize", appId: "work", width: nil, height: nil), "a sign-in is a pop-up")
        XCTAssertFalse(m.opensAsTab("https://zentao.corp.com/x", appId: "work", width: 500, height: 600), "so is a sized window")
        XCTAssertFalse(m.opensAsTab("https://elsewhere.io/x", appId: "work", width: nil, height: nil))
        XCTAssertFalse(m.opensAsTab("about:blank", appId: "work", width: nil, height: nil))
        XCTAssertFalse(m.opensAsTab("https://corp.com", appId: "nobody", width: nil, height: nil))
    }
}

// MARK: mini_app_shortcuts.dart

final class MiniAppShortcutsTests: XCTestCase {
    private func key(_ code: UInt16, _ chars: String = "", _ mods: NSEvent.ModifierFlags = []) -> MiniAppShortcut? {
        miniAppShortcut(keyCode: code, characters: chars, modifiers: mods)
    }

    func testTheBrowsersUsualKeys() {
        XCTAssertEqual(key(15, "r", .command), .reload)
        XCTAssertEqual(key(15, "r", [.command, .shift]), .hardReload)
        XCTAssertEqual(key(96), .reload); XCTAssertEqual(key(96, "", .control), .hardReload)
        XCTAssertEqual(key(37, "l", .command), .focusAddress); XCTAssertEqual(key(97), .focusAddress)
        XCTAssertEqual(key(34, "i", [.command, .shift]), .devTools); XCTAssertEqual(key(111), .devTools)
        XCTAssertEqual(key(33, "[", .command), .back); XCTAssertEqual(key(30, "]", .command), .forward)
        XCTAssertEqual(key(123, "", .option), .back); XCTAssertEqual(key(124, "", .option), .forward)
        XCTAssertEqual(key(115, "", .option), .home)
    }

    func testTheTabKeys() {
        XCTAssertEqual(key(17, "t", .command), .newTab)
        XCTAssertEqual(key(13, "w", .command), .closeTab)
        XCTAssertEqual(key(30, "}", [.command, .shift]), .nextTab); XCTAssertEqual(key(33, "{", [.command, .shift]), .previousTab)
        XCTAssertEqual(key(48, "", .control), .nextTab); XCTAssertEqual(key(48, "", [.control, .shift]), .previousTab)
    }

    func testOtherKeysAreTheirOwn() {
        XCTAssertNil(key(0, "a", .command)); XCTAssertNil(key(15, "r")); XCTAssertNil(key(13, "w"))
        XCTAssertNil(key(13, "w", [.command, .shift])); XCTAssertNil(key(13, "w", [.command, .option]))
        XCTAssertNil(key(53), "Esc is left to the page"); XCTAssertNil(key(123)); XCTAssertNil(key(123, "", [.option, .shift]))
        XCTAssertEqual(key(15, "R", .command), .reload, "caps lock")
    }
}

// MARK: The windows a page opens, in a real WKWebView

@MainActor
final class MiniAppTabWindowTests: XCTestCase {
    /// The app lives at `localhost` so the windows' loads are refused at once: nothing leaves the machine.
    private let appUrl = "http://localhost:9"

    private func start(_ h: Harness) async throws -> (MiniAppTabsModel, WKWebView) {
        let a = app("a", appUrl)
        await h.seed([a])
        h.model.show("a")
        let tabs = h.model.tabsModel(for: a)
        let parts = MiniAppWebParts.make(app: a, model: h.model, browser: tabs.selected, tabs: tabs, loadInitialPage: false)
        parts.web.frame = NSRect(x: 0, y: 0, width: 800, height: 600)
        parts.web.loadHTMLString("<html><body>hi</body></html>", baseURL: URL(string: appUrl + "/"))
        for _ in 0..<500 where parts.web.isLoading || parts.web.url == nil { try await Task.sleep(for: .milliseconds(10)) }
        if parts.web.isLoading || parts.web.url == nil { throw XCTSkip("WebKit did not load a page in this environment") }
        return (tabs, parts.web)
    }

    private func open(_ web: WKWebView, _ script: String) async throws {
        _ = try await web.evaluateJavaScript(script)
        try await Task.sleep(for: .milliseconds(300))
    }

    func testAWindowOnTheAppsSiteOpensAsATabSharingTheScriptsAndCookies() async throws {
        let h = try await Harness()
        let (tabs, web) = try await start(h)
        try await open(web, "window.open('http://localhost:9/task-view-5.html'); 1")
        XCTAssertEqual(tabs.tabs.count, 2)
        XCTAssertEqual(tabs.selected.id, tabs.tabs[1].id, "in front")
        XCTAssertTrue(tabs.selected.openedByPage)
        XCTAssertTrue(tabs.selected.popups.isEmpty); XCTAssertTrue(tabs.tabs[0].popups.isEmpty)
        let opened = try XCTUnwrap(tabs.selected.parts?.web)
        XCTAssertTrue(opened.configuration.userContentController === web.configuration.userContentController,
                      "the page's scripts and bridge (notifications, saved login) are in the new tab too")
        XCTAssertTrue(opened.configuration.websiteDataStore === web.configuration.websiteDataStore, "so is the sign-in")
        XCTAssertFalse(tabs.tabs[0].persistsLastUrl); XCTAssertTrue(tabs.selected.persistsLastUrl)
    }

    func testASignInAndAnotherSiteKeepThePopUp() async throws {
        let h = try await Harness()
        let (tabs, web) = try await start(h)
        try await open(web, "window.open('http://localhost:9/oauth/authorize?client_id=1'); 1")
        XCTAssertEqual(tabs.tabs.count, 1); XCTAssertEqual(tabs.selected.popups.count, 1)
        try await open(web, "window.open('http://elsewhere.invalid/x'); 1")
        XCTAssertEqual(tabs.tabs.count, 1); XCTAssertEqual(tabs.selected.popups.count, 2)
    }

    func testAtTheLimitAWindowFallsBackToAPopUp() async throws {
        let h = try await Harness()
        let (tabs, web) = try await start(h)
        for i in 1..<MiniAppTabsModel.maxTabs { tabs.newTab(url: "http://localhost:9/\(i)", select: false) }
        try await open(web, "window.open('http://localhost:9/one-more'); 1")
        XCTAssertEqual(tabs.tabs.count, MiniAppTabsModel.maxTabs); XCTAssertEqual(tabs.tabs[0].popups.count, 1)
    }

    func testAPageClosesATabItOpened() async throws {
        let h = try await Harness()
        let (tabs, web) = try await start(h)
        try await open(web, "window.__w = window.open('http://localhost:9/x'); 1")
        XCTAssertEqual(tabs.tabs.count, 2)
        try await open(web, "window.__w.close(); 1")
        XCTAssertEqual(tabs.tabs.count, 1); XCTAssertEqual(tabs.selected.id, tabs.tabs[0].id)
    }

    func testTheAppsOwnFirstPageIsNotClosedByThePage() async throws {
        let h = try await Harness()
        let (tabs, web) = try await start(h)
        try await open(web, "window.close(); 1")
        XCTAssertEqual(tabs.tabs.count, 1)
    }
}
