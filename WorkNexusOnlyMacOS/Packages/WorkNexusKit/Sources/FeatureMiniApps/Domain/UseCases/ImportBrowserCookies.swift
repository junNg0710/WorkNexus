import CoreDomain
import Foundation

/// Ported from: lib/features/mini_apps/domain/usecases/import_browser_cookies.dart
/// Brings the cookies of the chosen `sites` from a browser profile into the mini apps' web view, and remembers where they
/// came from so they can be imported again once they run out. Answers how many cookies went in. It reads the profile
/// afresh rather than taking cookies already shown, so importing again picks up the sign-in the browser has now.
public struct ImportBrowserCookies: Sendable {
    private let browsers: BrowserCookieRepository
    private let webView: WebViewCookieRepository
    private let imports: CookieImportRepository
    private let now: @Sendable () -> Date

    public init(_ browsers: BrowserCookieRepository, _ webView: WebViewCookieRepository, _ imports: CookieImportRepository,
                now: @escaping @Sendable () -> Date = { Date() }) {
        self.browsers = browsers; self.webView = webView; self.imports = imports; self.now = now
    }

    public func callAsFunction(_ source: CookieSource, sites: Set<String>) async -> Outcome<Int> {
        let at = now()
        let cookies: [BrowserCookie]
        switch await browsers.read(source) {
        case .success(let c): cookies = c
        case .failure(let f): return .failure(f)
        }
        let chosen = cookies.filter { !$0.value.isEmpty && !$0.isExpired(at: at) && sites.contains(cookieSite(of: $0.domain)) }
        if chosen.isEmpty { return .failure(.notFound("The browser has no such cookies")) }
        if case .failure(let f) = await webView.write(chosen) { return .failure(f) }
        var bySite: [String: [BrowserCookie]] = [:]
        for c in chosen { bySite[cookieSite(of: c.domain), default: []].append(c) }
        let saved = await imports.save(bySite.map { CookieImport(site: $0.key, source: source, importedAt: at, keys: Self.signInKeys($0.value)) })
        switch saved {
        case .success: return .success(chosen.count)
        case .failure(let f): return .failure(f)
        }
    }

    /// The cookies a sign-in rests on. Sites keep their session in HttpOnly cookies, while the rest are mostly short-lived
    /// analytics that come and go; watching those would call a live sign-in expired. A site with no HttpOnly cookie is watched whole.
    static func signInKeys(_ cookies: [BrowserCookie]) -> [CookieKey] {
        let httpOnly = cookies.filter(\.httpOnly)
        var seen = Set<CookieKey>(), keys: [CookieKey] = []
        for c in httpOnly.isEmpty ? cookies : httpOnly where seen.insert(c.key).inserted { keys.append(c.key) }
        return keys
    }
}
