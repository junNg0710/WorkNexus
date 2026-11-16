import CoreDomain
import XCTest
@testable import FeatureMiniApps

// MARK: cookie_import_dialog_test.dart

@MainActor
final class CookieImportDialogModelTests: XCTestCase {
    private func cookies(_ h: Harness, _ browsers: FixtureBrowsers = FixtureBrowsers()) -> CookieImportModel {
        for source in browsers.found {
            browsers.cookies[source] = .success([
                BrowserCookie(name: "sid", value: "v", domain: "alpha.com"),
                BrowserCookie(name: "sid", value: "v", domain: "mac-mini-2.local"),
                BrowserCookie(name: "sid", value: "v", domain: "zeta.com"),
            ])
        }
        return h.cookieModel(browsers: browsers)
    }

    private func loaded(_ m: CookieImportDialogModel) -> [CookieSite] {
        if case .loaded(let sites) = m.sites { return sites }
        return []
    }

    func testFromSettingsEveryMiniAppSiteIsPicked() async throws {
        let h = try await Harness()
        await h.seed([app("a", "https://alpha.com"), app("m", "https://mac-mini-2.local")])
        let m = CookieImportDialogModel(cookies: cookies(h))
        XCTAssertTrue(m.loadingSources)
        await m.load()
        XCTAssertFalse(m.loadingSources)
        XCTAssertNil(m.source, "nothing is read (no keychain prompt) until a browser is chosen")
        XCTAssertEqual(m.browsers.first, .chrome, "Chrome is offered first")
        await m.chooseBrowser(.chrome)
        XCTAssertEqual(m.source, chromeSource, "its main profile")
        XCTAssertEqual(CookieImportFeedback.label(chromeSource), "Chrome · Me")
        XCTAssertEqual(m.picked, ["alpha.com", "mac-mini-2.local"])
        XCTAssertEqual(loaded(m).map(\.site), ["alpha.com", "mac-mini-2.local", "zeta.com"])
        XCTAssertTrue(m.canImport)
    }

    func testFromAMiniAppItsSiteAloneIsPickedFirstFromItsLastBrowser() async throws {
        let h = try await Harness()
        await h.seed([app("a", "https://alpha.com"), app("m", "https://mac-mini-2.local")])
        let m = CookieImportDialogModel(cookies: cookies(h), site: "mac-mini-2.local", source: firefoxSource)
        await m.load()
        XCTAssertEqual(m.source, firefoxSource)
        XCTAssertEqual(CookieImportFeedback.label(firefoxSource), "Firefox · main")
        XCTAssertEqual(m.picked, ["mac-mini-2.local"])
        XCTAssertEqual(loaded(m).first?.site, "mac-mini-2.local", "listed first")
        XCTAssertEqual(loaded(m).map(\.site), ["mac-mini-2.local", "alpha.com", "zeta.com"])
    }

    func testAProfileThatIsGoneWaitsForTheUsersChoice() async throws {
        let h = try await Harness()
        let browsers = FixtureBrowsers(); browsers.found = [chromeSource]
        let m = CookieImportDialogModel(cookies: cookies(h, browsers), site: "x.com", source: firefoxSource)
        await m.load()
        XCTAssertNil(m.source)
        await m.chooseBrowser(.chrome)
        XCTAssertEqual(m.source, chromeSource)
    }

    func testNoBrowserLeavesNothingToImport() async throws {
        let h = try await Harness()
        let browsers = FixtureBrowsers(); browsers.found = []
        let m = CookieImportDialogModel(cookies: h.cookieModel(browsers: browsers))
        await m.load()
        await m.chooseBrowser(.chrome)
        XCTAssertNil(m.source); XCTAssertFalse(m.loadingSources); XCTAssertFalse(m.canImport)
        let none = await m.importPicked()
        XCTAssertNil(none)
    }

    func testPickingBySearchAndAllOrNone() async throws {
        let h = try await Harness()
        let m = CookieImportDialogModel(cookies: cookies(h))
        await m.load()
        await m.chooseBrowser(.chrome)
        XCTAssertEqual(m.picked, [])
        XCTAssertFalse(m.canImport, "nothing picked")
        m.toggle("zeta.com"); XCTAssertEqual(m.picked, ["zeta.com"])
        m.pick(loaded(m).filter { $0.site.contains("a.com") }); XCTAssertEqual(m.picked, ["zeta.com", "alpha.com"], "adds to the picks")
        m.toggle("zeta.com"); XCTAssertEqual(m.picked, ["alpha.com"])
        m.pickNone(); XCTAssertTrue(m.picked.isEmpty)
    }

    func testChoosingAnotherProfileDropsThePicksAndTheLateAnswerOfTheFirst() async throws {
        let h = try await Harness()
        let browsers = FixtureBrowsers()
        browsers.cookies[chromeSource] = .success([BrowserCookie(name: "a", value: "1", domain: "slow.com")])
        browsers.cookies[firefoxSource] = .success([BrowserCookie(name: "a", value: "1", domain: "fast.com")])
        browsers.delays[chromeSource] = .milliseconds(200)
        let m = CookieImportDialogModel(cookies: h.cookieModel(browsers: browsers))
        await m.load()                                     // chrome (slow) is first
        let slow = Task { await m.choose(chromeSource) }
        try await Task.sleep(for: .milliseconds(30))
        await m.choose(firefoxSource)
        await slow.value
        XCTAssertEqual(m.source, firefoxSource); XCTAssertEqual(loaded(m).map(\.site), ["fast.com"])
    }

    func testAReadTheSystemRefusedIsShownAndCanBeRetried() async throws {
        let h = try await Harness()
        let browsers = FixtureBrowsers()
        browsers.found = [CookieSource(browser: .safari, profileId: "s", profileName: "Safari")]
        browsers.cookies[browsers.found[0]] = .failure(.auth("denied"))
        let m = CookieImportDialogModel(cookies: h.cookieModel(browsers: browsers))
        await m.load()
        await m.chooseBrowser(.safari)
        guard case .failed(let failure) = m.sites else { return XCTFail("expected a refused read") }
        XCTAssertTrue(CookieImportFeedback.needsFullDiskAccess(browsers.found[0], failure))
        XCTAssertFalse(CookieImportFeedback.needsFullDiskAccess(chromeSource, failure))
        browsers.cookies[browsers.found[0]] = .success([BrowserCookie(name: "a", value: "1", domain: "x.com")])
        await m.retry()
        XCTAssertEqual(loaded(m).map(\.site), ["x.com"])
        XCTAssertEqual(browsers.reads.count, 2)
    }

    func testImportingGoesIntoTheWebViewReloadsThePagesAndRefreshesTheList() async throws {
        let h = try await Harness()
        await h.seed([app("a", "https://alpha.com")])
        h.model.show("a")
        let tab = h.model.tabsModel(for: h.model.apps[0]).selected
        let page = FixturePageDriver(); tab.attach(page)
        let web = FixtureWebCookies(), imports = FixtureImports()
        let browsers = FixtureBrowsers()
        browsers.cookies[chromeSource] = .success([BrowserCookie(name: "sid", value: "v", domain: ".alpha.com", httpOnly: true),
                                                   BrowserCookie(name: "x", value: "v", domain: "zeta.com")])
        let model = h.cookieModel(browsers: browsers, web: web, imports: imports)
        let m = CookieImportDialogModel(cookies: model)
        await m.load()
        await m.chooseBrowser(.chrome)
        XCTAssertEqual(m.picked, ["alpha.com"])
        let imported = await m.importPicked()
        let done = try XCTUnwrap(imported)
        XCTAssertEqual(done.source, chromeSource); XCTAssertEqual(done.result.value, 1)
        XCTAssertEqual(web.written.first?.map(\.name), ["sid"], "only the picked site's cookies")
        XCTAssertEqual(imports.items.map(\.site), ["alpha.com"])
        XCTAssertEqual(page.reloads, 1, "the running page of the site shows the sign-in at once")
        XCTAssertEqual(model.states.map { $0.cookieImport.site }, ["alpha.com"])
        XCTAssertFalse(m.importing)
    }

    func testAFailedImportIsReportedAndTheDialogCanTryAgain() async throws {
        let h = try await Harness()
        await h.seed([app("a", "https://alpha.com")])
        let browsers = FixtureBrowsers()
        browsers.cookies[chromeSource] = .success([BrowserCookie(name: "sid", value: "v", domain: "alpha.com")])
        let model = h.cookieModel(browsers: browsers)
        let m = CookieImportDialogModel(cookies: model)
        await m.load()
        await m.chooseBrowser(.chrome)
        browsers.cookies[chromeSource] = .failure(.auth("denied"))          // the keychain says no on the second read
        let imported = await m.importPicked()
        let done = try XCTUnwrap(imported)
        XCTAssertNil(done.result.value)
        XCTAssertEqual(CookieImportFeedback.failureMessage(done.source, .auth("x")).contains("Chrome"), true)
        XCTAssertFalse(m.importing); XCTAssertTrue(m.canImport)
    }
}

// MARK: cookie_import_feedback.dart

final class CookieImportFeedbackTests: XCTestCase {
    func testFailuresAreToldInTheUsersWords() {
        let safari = CookieSource(browser: .safari, profileId: "s", profileName: "Safari")
        XCTAssertTrue(CookieImportFeedback.failureMessage(safari, .auth("x")).contains("Full Disk Access"))
        XCTAssertTrue(CookieImportFeedback.failureMessage(chromeSource, .auth("x")).contains("Chrome"))
        XCTAssertTrue(CookieImportFeedback.failureMessage(chromeSource, .notFound("x")).contains("no cookies"))
        XCTAssertEqual(CookieImportFeedback.failureMessage(chromeSource, .storage("x")), "Could not import the cookies.")
    }

    func testTheImportedToastCountsCookies() {
        XCTAssertEqual(CookieImportFeedback.importedMessage(1), "Imported 1 cookie.")
        XCTAssertEqual(CookieImportFeedback.importedMessage(12), "Imported 12 cookies.")
    }

    func testOnlySafariSendsTheUserToThePrivacySettings() {
        let safari = CookieSource(browser: .safari, profileId: "s", profileName: "Safari")
        XCTAssertTrue(CookieImportFeedback.needsFullDiskAccess(safari, .auth("x")))
        XCTAssertFalse(CookieImportFeedback.needsFullDiskAccess(safari, .notFound("x")))
        XCTAssertFalse(CookieImportFeedback.needsFullDiskAccess(firefoxSource, .auth("x")))
        XCTAssertEqual(CookieImportFeedback.fullDiskAccessUrl.scheme, "x-apple.systempreferences")
        XCTAssertTrue(CookieImportFeedback.fullDiskAccessUrl.absoluteString.hasSuffix("Privacy_AllFiles"))
    }

    func testAProfileWithTheBrowsersNameIsNotRepeated() {
        XCTAssertEqual(CookieImportFeedback.label(CookieSource(browser: .brave, profileId: "p", profileName: "Brave")), "Brave")
        XCTAssertEqual(CookieImportFeedback.label(CookieSource(browser: .arc, profileId: "p", profileName: "Work")), "Arc · Work")
    }
}
