import AppKit
import CoreDomain
import CoreUI
import SwiftUI
import XCTest
@testable import FeatureMiniApps

/// The saved passwords' models and views: the import dialog's opt-in, the tab's bar and list, settings. Renders go to
/// /tmp/wn-pw-render/pw-*.png (asserted only to be non-blank; they are there to be looked at).
@MainActor
final class WebLoginsViewsTests: XCTestCase {
    private let outDir = URL(fileURLWithPath: "/tmp/wn-pw-render")
    private let site = "https://intranet.example.com"

    private func render<V: View>(_ name: String, _ view: V, size: CGSize, dark: Bool = false, pad: CGFloat = 0) async throws {
        try FileManager.default.createDirectory(at: outDir, withIntermediateDirectories: true)
        var settings = AppSettings(); if dark { settings.variant = .dark }
        let theme = AppTheme(settings: settings)
        let host = NSHostingView(rootView: view.padding(pad).frame(width: size.width, height: size.height, alignment: .topLeading)
            .background(theme.colors.bg).environment(\.appTheme, theme).environment(\.colorScheme, theme.colorScheme)
            .environment(\.toasts, AppToastController()))
        host.frame = CGRect(origin: .zero, size: size)
        let window = NSWindow(contentRect: host.frame, styleMask: [.borderless], backing: .buffered, defer: false)
        window.contentView = host
        for _ in 0..<4 {
            host.layoutSubtreeIfNeeded()
            try await Task.sleep(for: .milliseconds(150))
        }
        guard let rep = host.bitmapImageRepForCachingDisplay(in: host.bounds) else { return XCTFail("no bitmap") }
        host.cacheDisplay(in: host.bounds, to: rep)
        let png = rep.representation(using: .png, properties: [:])!
        try png.write(to: outDir.appendingPathComponent("pw-\(name).png"))
        XCTAssertGreaterThan(png.count, 2_000, "\(name) rendered blank")
        window.contentView = nil
    }

    private func seeded() async throws -> Harness {
        let h = try await Harness()
        var work = app("work", "http://localhost:9", position: 0); work.name = "Intranet"
        await h.seed([work, app("chat", "https://chat.example.com", position: 1)])
        return h
    }

    /// The cookie import model of `h` with a browser's saved passwords behind it.
    private func cookies(_ h: Harness, _ browsers: FixtureBrowsers, _ logins: FixtureBrowserLogins) -> CookieImportModel {
        let web = FixtureWebCookies(), imports = FixtureImports()
        return CookieImportModel(browsers: browsers, webView: web, imports: imports, importCookies: ImportBrowserCookies(browsers, web, imports),
                                 check: CheckCookieImports(imports, web), importLogins: ImportBrowserLogins(logins, h.feature.webLogins), model: h.model)
    }

    private func browsersWithCookies() -> FixtureBrowsers {
        let browsers = FixtureBrowsers()
        let found = [BrowserCookie(name: "sid", value: "v", domain: ".example.com"), BrowserCookie(name: "a", value: "v", domain: "chat.example.com"),
                     BrowserCookie(name: "sid", value: "v", domain: "localhost"), BrowserCookie(name: "sid", value: "v", domain: ".github.com")]
        for s in browsers.found { browsers.cookies[s] = .success(found) }
        return browsers
    }

    // MARK: Import dialog

    func testPasswordsAreImportedOnlyWhenAskedAndOnlyForThePickedSites() async throws {
        let h = try await seeded()
        let logins = FixtureBrowserLogins()
        logins.logins = .success(browserLoginsFixture)
        let m = CookieImportDialogModel(cookies: cookies(h, browsersWithCookies(), logins))
        await m.load()
        await m.choose(chromeSource)
        XCTAssertTrue(m.passwordsSupported)
        XCTAssertFalse(m.includePasswords, "off until the user asks")
        // Off: the cookies go in, the browser's passwords are not even read.
        let plainDone = await m.importPicked()
        let plain = try XCTUnwrap(plainDone)
        XCTAssertEqual(plain.result.value, 3)
        XCTAssertNil(plain.passwords)
        XCTAssertEqual(logins.reads, [])
        do { let kept = try got(await ListWebLogins(h.feature.webLogins)()); XCTAssertEqual(kept, []) }
        // On, with the mini apps' sites picked (example.com and localhost): github's password stays in the browser.
        m.includePasswords = true
        XCTAssertEqual(m.picked, ["example.com", "localhost"])
        let bothDone = await m.importPicked()
        let both = try XCTUnwrap(bothDone)
        XCTAssertEqual(both.passwords?.value, 3)
        let kept = try got(await ListWebLogins(h.feature.webLogins)())
        XCTAssertEqual(kept.map(\.origin), ["https://chat.example.com", "https://example.com", "http://localhost:9"])
        XCTAssertEqual(CookieImportFeedback.importedMessage(cookies: 3, passwords: 3), "Imported 3 cookies and 3 passwords.")
        XCTAssertEqual(CookieImportFeedback.importedMessage(cookies: 1, passwords: 1), "Imported 1 cookie and 1 password.")
    }

    func testFirefoxHasNoPasswordOptionAndTheChoiceIsNotCarriedToAnotherProfile() async throws {
        let h = try await seeded()
        let logins = FixtureBrowserLogins()
        logins.logins = .success(browserLoginsFixture)
        let m = CookieImportDialogModel(cookies: cookies(h, browsersWithCookies(), logins))
        await m.load()
        await m.choose(chromeSource)
        m.includePasswords = true
        await m.choose(firefoxSource)
        XCTAssertFalse(m.passwordsSupported, "the checkbox is hidden")
        XCTAssertFalse(m.includePasswords)
        m.includePasswords = true
        let doneDone = await m.importPicked()
        let done = try XCTUnwrap(doneDone)
        XCTAssertNil(done.passwords)
        XCTAssertEqual(logins.reads, [])
        // A failed cookie import imports no password either.
        let failing = FixtureBrowsers()
        failing.cookies[chromeSource] = .success([])
        let m2 = CookieImportDialogModel(cookies: cookies(h, failing, logins))
        await m2.load(); await m2.choose(chromeSource)
        m2.includePasswords = true; m2.toggle("example.com")
        let failedDone = await m2.importPicked()
        let failed = try XCTUnwrap(failedDone)
        guard case .failure = failed.result else { return XCTFail("expected the cookies to fail") }
        XCTAssertNil(failed.passwords); XCTAssertEqual(logins.reads, [])
    }

    // MARK: The tab's model

    func testAnUnansweredOfferRunsOutAndWhatTheBarShowsNeverHoldsThePassword() async throws {
        let h = try await seeded()
        let passwords = MiniAppPasswordsModel()
        passwords.bind(h.model.services.webLogins, filler: WKLoginFiller(web: nil))
        passwords.offer(WebLogin(origin: site, username: "alice", password: "hunter2"), isUpdate: false)
        let offer = try XCTUnwrap(passwords.offer)
        XCTAssertFalse(String(describing: offer).contains("hunter2"))
        XCTAssertFalse(MiniAppPasswordSaveBar.title(offer).contains("hunter2") || MiniAppPasswordSaveBar.detail(offer).contains("hunter2"))
        XCTAssertEqual(MiniAppPasswordSaveBar.title(offer), "Save password for intranet.example.com?")
        XCTAssertEqual(MiniAppPasswordSaveBar.site("http://nas.local:5000"), "http://nas.local:5000", "an unencrypted site shows its scheme")
        XCTAssertGreaterThan(MiniAppPasswordsModel.offerLifetime, .seconds(30))
        passwords.dismiss()
        do { let saved = await passwords.saveOffer(); XCTAssertFalse(saved) }
        do { let kept = try got(await ListWebLogins(h.feature.webLogins)()); XCTAssertEqual(kept, []) }
    }

    func testSettingsListsSitesAndUsersDeletesAndAllowsAgain() async throws {
        let h = try await seeded()
        let repo = h.feature.webLogins
        for login in [WebLogin(origin: site, username: "alice", password: "a"), WebLogin(origin: site, username: "bob", password: "b"),
                      WebLogin(origin: "http://nas.local:5000", username: "admin", password: "c")] { _ = try got(await SaveWebLogin(repo)(login)) }
        _ = try got(await NeverSaveForSite(repo)("https://bank.example.org"))
        let model = h.feature.webLoginsModel
        await model.load()
        XCTAssertEqual(model.items.map { "\($0.host) \($0.username)" }, ["intranet.example.com alice", "intranet.example.com bob", "nas.local:5000 admin"])
        XCTAssertEqual(model.neverSave, ["https://bank.example.org"])
        do { let ok = await model.delete(model.items[1]); XCTAssertTrue(ok) }
        XCTAssertEqual(model.items.map(\.username), ["alice", "admin"])
        do { let ok = await model.allow("https://bank.example.org"); XCTAssertTrue(ok) }
        XCTAssertEqual(model.neverSave, [])
        do { let ok = await model.deleteAll(); XCTAssertTrue(ok) }
        XCTAssertEqual(model.items, [])
    }

    // MARK: Renders

    func testRenderTheSaveBarTheKeyButtonAndItsList() async throws {
        let h = try await seeded()
        let work = h.model.apps[0]
        _ = try got(await SaveWebLogin(h.feature.webLogins)(WebLogin(origin: "http://localhost:9", username: "jun@corp.com", password: "x")))
        _ = try got(await SaveWebLogin(h.feature.webLogins)(WebLogin(origin: "http://localhost:9", username: "admin", password: "y")))
        h.model.show("work")
        let tabs = h.model.tabsModel(for: work)
        tabs.selected.onTitle("Sign in - Intranet")
        let view = MiniAppHostView(miniApp: work).miniApps(h.feature)
        // The bars as they are with nothing asked, then with the question.
        try await render("host-key-button", view, size: CGSize(width: 900, height: 300))
        tabs.selected.passwords.offer(WebLogin(origin: site, username: "jun@corp.com", password: "never-drawn"), isUpdate: false)
        try await render("host-save-bar", view, size: CGSize(width: 900, height: 300))
        try await render("host-save-bar-dark", view, size: CGSize(width: 900, height: 300), dark: true)

        let passwords = MiniAppPasswordsModel()
        passwords.bind(h.model.services.webLogins, filler: WKLoginFiller(web: nil))
        passwords.offer(WebLogin(origin: site, username: "jun@corp.com", password: "never-drawn"), isUpdate: false)
        try await render("save-bar", MiniAppPasswordSaveBar(passwords: passwords), size: CGSize(width: 820, height: 70))
        passwords.offer(WebLogin(origin: "http://nas.local:5000", username: "", password: "never-drawn"), isUpdate: true)
        try await render("save-bar-update-http", MiniAppPasswordSaveBar(passwords: passwords), size: CGSize(width: 820, height: 70), dark: true)
        passwords.offer(WebLogin(origin: "https://a-very-long-subdomain.of.some.internal.tool.corp.example.com:8443", username: "someone.with.a.long.name@corp.example.com",
                                 password: "never-drawn"), isUpdate: false)
        try await render("save-bar-narrow", MiniAppPasswordSaveBar(passwords: passwords), size: CGSize(width: 560, height: 70))

        await passwords.refresh(address: "http://localhost:9/#/login")
        XCTAssertEqual(passwords.saved.count, 2)
        try await render("key-list", AppPopupCard { MiniAppPasswordList(passwords: passwords, site: "http://localhost:9", onClose: {}) },
                         size: CGSize(width: 360, height: 220), pad: 20)
        try await render("key-list-dark", AppPopupCard { MiniAppPasswordList(passwords: passwords, site: "http://localhost:9", onClose: {}) },
                         size: CGSize(width: 360, height: 220), dark: true, pad: 20)
        await passwords.refresh(address: "https://nothing-saved.example.com/")
        try await render("key-list-empty", AppPopupCard { MiniAppPasswordList(passwords: passwords, site: "nothing-saved.example.com", onClose: {}) },
                         size: CGSize(width: 360, height: 160), pad: 20)
    }

    func testRenderSettingsAndTheImportOption() async throws {
        let h = try await seeded()
        let repo = h.feature.webLogins
        for login in [WebLogin(origin: site, username: "jun@corp.com", password: "a"), WebLogin(origin: site, username: "admin", password: "b"),
                      WebLogin(origin: "http://nas.local:5000", username: "", password: "c")] { _ = try got(await SaveWebLogin(repo)(login)) }
        _ = try got(await NeverSaveForSite(repo)("https://bank.example.org"))
        try await render("settings-section", MiniAppSavedPasswordsSection(model: h.feature.webLoginsModel), size: CGSize(width: 640, height: 360), pad: 24)
        try await render("settings-section-dark", MiniAppSavedPasswordsSection(model: h.feature.webLoginsModel), size: CGSize(width: 640, height: 360), dark: true, pad: 24)
        let empty = try await Harness()
        try await render("settings-section-empty", MiniAppSavedPasswordsSection(model: empty.feature.webLoginsModel), size: CGSize(width: 640, height: 90), pad: 24)
        let card = MiniAppSettingsCard(feature: h.feature, liveLimit: 5, notifyInBackground: true, initiallyExpanded: true, onLiveLimit: { _ in }, onNotifyInBackground: { _ in })
        try await render("settings-card", card, size: CGSize(width: 720, height: 1500), pad: 24)

        let logins = FixtureBrowserLogins()
        let model = cookies(h, browsersWithCookies(), logins)
        try await render("import-dialog-option", CookieImportDialog(cookies: model, site: "example.com", source: chromeSource, onClose: {}),
                         size: CGSize(width: 560, height: 620), pad: 24)
        try await render("import-dialog-firefox", CookieImportDialog(cookies: model, site: "example.com", source: firefoxSource, onClose: {}),
                         size: CGSize(width: 560, height: 620), dark: true, pad: 24)
    }
}
