import AppKit
import CoreDomain
import CoreUI
import SwiftUI
import XCTest
@testable import FeatureMiniApps

/// Renders the mini app views off-screen (PNGs in /tmp/wn-mini-render/mini-*.png) so layout problems show up; asserts only that
/// something non-blank was drawn.
@MainActor
final class MiniAppsRenderTests: XCTestCase {
    private let outDir = URL(fileURLWithPath: "/tmp/wn-mini-render")

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
        try png.write(to: outDir.appendingPathComponent("mini-\(name).png"))
        XCTAssertGreaterThan(png.count, 2_000, "\(name) rendered blank")
        window.contentView = nil
    }

    private func seeded() async throws -> Harness {
        let h = try await Harness()
        var work = app("work", "http://localhost:9", position: 0); work.name = "ZenTao"
        await h.seed([work, app("chat", "https://chat.example.com", position: 1), app("docs", "https://docs.example.com", position: 2)])
        return h
    }

    func testBrowserBarWithTabsAndTheCookieButton() async throws {
        let h = try await seeded()
        let work = h.model.apps[0]
        h.model.show("work")
        let tabs = h.model.tabsModel(for: work)
        tabs.selected.onTitle("My tasks - ZenTao")
        let second = try XCTUnwrap(tabs.newTab(url: "http://localhost:9/task-view-12.html"))
        second.onTitle("Task #12: Fix the login redirect for SSO users")
        second.onProgress(0.5)
        let third = try XCTUnwrap(tabs.newTab(url: "http://localhost:9/bug-view-3.html", select: false))
        third.onTitle("Bug #3")
        tabs.select(second.id)
        let view = MiniAppHostView(miniApp: work).miniApps(h.feature)
        try await render("browser-tabs", view, size: CGSize(width: 900, height: 420))
        try await render("browser-tabs-dark", view, size: CGSize(width: 900, height: 420), dark: true)
    }

    /// Folded, the browser bar is gone and the tab strip (with the button that brings it back) is the first thing drawn.
    func testTheBrowserBarFoldsAwayAndTheTabStripStays() async throws {
        let h = try await seeded()
        let work = h.model.apps[0]
        h.model.show("work")
        h.model.tabsModel(for: work).selected.onTitle("My tasks - ZenTao")
        for collapsed in [false, true] {
            let view = MiniAppHostView(miniApp: work).miniApps(h.feature).environment(\.miniAppBars, MiniAppBars(collapsed: collapsed))
            try await render("bars-\(collapsed ? "collapsed" : "open")", view, size: CGSize(width: 900, height: 220))
        }
    }

    func testTheCookieButtonIsTintedOnceTheSignInIsGone() async throws {
        let h = try await seeded()
        let work = h.model.apps[0]
        let imports = FixtureImports()
        imports.items = [CookieImport(site: "localhost", source: chromeSource, importedAt: Date(), keys: [CookieKey(host: "localhost", path: "/", name: "sid")])]
        let cookies = h.cookieModel(imports: imports)
        await cookies.refresh()
        XCTAssertEqual(cookies.states.first?.expired, true, "the web view has no such cookie")
        let browser = MiniAppBrowserModel(appId: "work", initialUrl: work.url, apps: h.feature.apps)
        try await render("cookie-button-expired", MiniAppCookieButton(app: work, browser: browser, cookies: cookies), size: CGSize(width: 120, height: 60), pad: 12)
    }

    func testCookieImportDialog() async throws {
        let h = try await seeded()
        let browsers = FixtureBrowsers()
        let cookies = [BrowserCookie(name: "sid", value: "v", domain: ".example.com"), BrowserCookie(name: "a", value: "v", domain: "chat.example.com"),
                       BrowserCookie(name: "b", value: "v", domain: "chat.example.com"), BrowserCookie(name: "sid", value: "v", domain: "localhost"),
                       BrowserCookie(name: "sid", value: "v", domain: ".github.com"), BrowserCookie(name: "sid", value: "v", domain: "news.ycombinator.com")]
        for s in browsers.found { browsers.cookies[s] = .success(cookies) }
        let model = h.cookieModel(browsers: browsers)
        try await render("cookie-dialog", CookieImportDialog(cookies: model, onClose: {}), size: CGSize(width: 560, height: 560), pad: 24)
        try await render("cookie-dialog-site", CookieImportDialog(cookies: model, site: "localhost", source: firefoxSource, onClose: {}),
                         size: CGSize(width: 560, height: 560), dark: true, pad: 24)
    }

    func testCookieImportDialogShowsAKeychainOrSafariFailure() async throws {
        let h = try await seeded()
        let browsers = FixtureBrowsers()
        browsers.found = [CookieSource(browser: .safari, profileId: "s", profileName: "Safari"), chromeSource]
        browsers.cookies[browsers.found[0]] = .failure(.auth("denied"))
        try await render("cookie-dialog-safari", CookieImportDialog(cookies: h.cookieModel(browsers: browsers), onClose: {}),
                         size: CGSize(width: 560, height: 360), pad: 24)
    }

    func testEditDialogWithIconPermissionsAndCertificate() async throws {
        let h = try await seeded()
        let work = h.model.apps[0]
        _ = await h.feature.permissions.save(MiniAppPermissionGrant(miniAppId: "work", kind: .notifications, decision: .allow))
        _ = await h.feature.permissions.save(MiniAppPermissionGrant(miniAppId: "work", kind: .camera, decision: .block))
        let secure = app("secure", "https://zentao.corp.com", position: 3)
        await h.seed([work, secure])
        try await render("edit-dialog", MiniAppDialog(feature: h.feature, existing: secure, onClose: {}), size: CGSize(width: 480, height: 700), pad: 24)
        try await render("edit-dialog-permissions", MiniAppDialog(feature: h.feature, existing: work, onClose: {}), size: CGSize(width: 480, height: 560), dark: true, pad: 24)
        try await render("add-dialog", MiniAppDialog(feature: h.feature, onClose: {}), size: CGSize(width: 480, height: 360), pad: 24)
    }

    func testSettingsCardClosedAndOpen() async throws {
        let h = try await seeded()
        _ = await h.feature.trustedCertificates.trust(origin: "https://zentao.corp.com:443", error: trustedByChoice)
        _ = await h.feature.trustedCertificates.trust(origin: "https://nas.local:5001", error: "net::ERR_CERT_AUTHORITY_INVALID")
        _ = await h.feature.cookieImports.save([CookieImport(site: "example.com", source: chromeSource, importedAt: Date().addingTimeInterval(-3600),
                                                             keys: [CookieKey(host: "example.com", path: "/", name: "sid")])])
        func card(_ open: Bool) -> some View {
            MiniAppSettingsCard(feature: h.feature, liveLimit: 5, notifyInBackground: true, initiallyExpanded: open, onLiveLimit: { _ in }, onNotifyInBackground: { _ in })
        }
        try await render("settings-card-closed", card(false), size: CGSize(width: 720, height: 120), pad: 24)
        try await render("settings-card-open", card(true), size: CGSize(width: 720, height: 1180), pad: 24)
        try await render("settings-card-open-dark", card(true), size: CGSize(width: 720, height: 1180), dark: true, pad: 24)
    }
}
