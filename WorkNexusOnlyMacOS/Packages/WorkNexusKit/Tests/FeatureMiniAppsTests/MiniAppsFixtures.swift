import CoreDomain
import Foundation
@testable import FeatureMiniApps

/// Doubles for the cookie import views' tests: no real browser, keychain or web profile is touched.
let chromeSource = CookieSource(browser: .chrome, profileId: "/chrome/Default", profileName: "Me")
let firefoxSource = CookieSource(browser: .firefox, profileId: "/firefox/p", profileName: "main")

func cookieSite(_ site: String, app: Bool = false) -> CookieSite {
    CookieSite(site: site, cookies: [BrowserCookie(name: "sid", value: "v", domain: site)], usedByMiniApp: app)
}

final class FixtureBrowsers: BrowserCookieRepository, @unchecked Sendable {
    var found: [CookieSource] = [chromeSource, firefoxSource]
    /// What each profile has cookies for.
    var cookies: [CookieSource: Outcome<[BrowserCookie]>] = [:]
    var delays: [CookieSource: Duration] = [:]
    private(set) var reads: [CookieSource] = []

    func sources() async -> Outcome<[CookieSource]> { .success(found) }
    func read(_ source: CookieSource) async -> Outcome<[BrowserCookie]> {
        reads.append(source)
        if let delay = delays[source] { try? await Task.sleep(for: delay) }
        return cookies[source] ?? .success([])
    }
}

final class FixtureWebCookies: WebViewCookieRepository, @unchecked Sendable {
    var written: [[BrowserCookie]] = []
    var presentKeys: Set<CookieKey> = []
    let canWrite = true
    func write(_ cookies: [BrowserCookie]) async -> Outcome<Void> { written.append(cookies); return .success(()) }
    func present(_ keys: [CookieKey]) async -> Outcome<Set<CookieKey>> { .success(presentKeys) }
}

final class FixtureImports: CookieImportRepository, @unchecked Sendable {
    var items: [CookieImport] = []
    func all() async -> Outcome<[CookieImport]> { .success(items) }
    func save(_ imports: [CookieImport]) async -> Outcome<[CookieImport]> {
        items = items.filter { old in !imports.contains { $0.site == old.site } } + imports
        return .success(items)
    }
    func forget(site: String) async -> Outcome<[CookieImport]> { items.removeAll { $0.site == site }; return .success(items) }
}

/// A page driver that counts the commands it is given.
@MainActor
final class FixturePageDriver: MiniAppPageDriver {
    var reloads = 0, loads: [String] = []
    func load(_ url: String) { loads.append(url) }
    func reload() { reloads += 1 }
    func hardReload() {}
    func stop() {}
    func goBack() {}
    func goForward() {}
}

extension Harness {
    /// A cookie import model over the fixtures above, tied to this harness's mini apps.
    @MainActor
    func cookieModel(browsers: FixtureBrowsers = FixtureBrowsers(), web: FixtureWebCookies = FixtureWebCookies(),
                     imports: FixtureImports = FixtureImports()) -> CookieImportModel {
        CookieImportModel(browsers: browsers, webView: web, imports: imports, importCookies: ImportBrowserCookies(browsers, web, imports),
                          check: CheckCookieImports(imports, web), model: model)
    }
}
