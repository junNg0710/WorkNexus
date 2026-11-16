import CoreDomain
import Foundation
import Observation

/// Ported from: lib/features/mini_apps/presentation/providers/cookie_import_controller.dart (+ util/cookie_browser_name.dart)
/// The imported sites and whether their sign-in is still in the web view, and the commands behind the "Import cookies"
/// dialog: which browser profiles can be read, their cookies grouped into sites (the mini apps' first), importing, importing
/// again and forgetting. Importing reloads the open mini apps of those sites, so they show the sign-in at once.
@MainActor @Observable
public final class CookieImportModel {
    public private(set) var states: [CookieImportState] = []
    public private(set) var loadFailure: Failure?
    public private(set) var sources: [CookieSource] = []

    private let browsers: BrowserCookieRepository
    private let webView: WebViewCookieRepository
    private let imports: CookieImportRepository
    private let importCookies: ImportBrowserCookies
    private let check: CheckCookieImports
    private let model: MiniAppsModel

    init(browsers: BrowserCookieRepository, webView: WebViewCookieRepository, imports: CookieImportRepository,
         importCookies: ImportBrowserCookies, check: CheckCookieImports, model: MiniAppsModel) {
        self.browsers = browsers; self.webView = webView; self.imports = imports
        self.importCookies = importCookies; self.check = check; self.model = model
    }

    public var canImport: Bool { webView.canWrite }

    /// Looks at the imports again (are their sign-in cookies still in the web view?).
    public func refresh() async {
        switch await check() {
        case .success(let s): states = s; loadFailure = nil
        case .failure(let f): loadFailure = f
        }
    }

    /// The browser profiles here whose cookies can be read.
    public func loadSources() async {
        if case .success(let found) = await browsers.sources() { sources = found }
    }

    /// `source`'s cookies grouped into sites, the mini apps' first. Fails with the read's failure, e.g. `.auth` when the system refused.
    public func sites(of source: CookieSource) async -> Outcome<[CookieSite]> {
        switch await browsers.read(source) {
        case .success(let cookies):
            return .success(GroupCookiesBySite()(cookies, miniAppUrls: model.apps.map(\.url), now: Date()))
        case .failure(let f): return .failure(f)
        }
    }

    /// Imports `sites` from `source`; answers how many cookies went in.
    public func importSites(_ sites: Set<String>, from source: CookieSource) async -> Outcome<Int> {
        let result = await importCookies(source, sites: sites)
        if case .success = result { model.reloadRunningApps(ofSites: sites); await refresh() }
        return result
    }

    /// Imports `state`'s site again from where it came from.
    public func reimport(_ state: CookieImportState) async -> Outcome<Int> {
        await importSites([state.cookieImport.site], from: state.cookieImport.source)
    }

    public func forget(site: String) async -> Outcome<Void> {
        switch await imports.forget(site: site) {
        case .success: await refresh(); return .success(())
        case .failure(let f): return .failure(f)
        }
    }
}

public extension CookieBrowser {
    /// The browser's product name, the same in every language.
    var displayName: String {
        switch self {
        case .chrome: "Chrome"; case .edge: "Edge"; case .brave: "Brave"; case .arc: "Arc"; case .firefox: "Firefox"; case .safari: "Safari"
        }
    }
}
