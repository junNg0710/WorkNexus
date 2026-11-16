import CoreDomain
import Foundation

/// New (no Dart counterpart): which cookies are kept between runs. The web view forgets a cookie without an expiry when the
/// app quits, and many sites keep their sign-in in just such a cookie.
public enum SessionCookieSnapshot {
    /// The session cookies of `cookies` that belong to one of `sites` (registrable domains, as `cookieSite(of:)` names
    /// them), each once, in a stable order.
    public static func select(_ cookies: [BrowserCookie], sites: Set<String>) -> [BrowserCookie] {
        var seen = Set<String>()
        return cookies
            .filter { $0.expires == nil && !$0.name.isEmpty && sites.contains(cookieSite(of: $0.domain)) }
            .filter { seen.insert("\($0.domain)\u{0}\($0.path)\u{0}\($0.name)").inserted }
            .sorted { ($0.domain, $0.path, $0.name) < ($1.domain, $1.path, $1.name) }
    }
}

/// The sites whose session cookies are kept: the mini apps' own and the ones whose cookies were imported from a browser.
public struct SessionCookieSites: Sendable {
    private let apps: MiniAppRepository
    private let imports: CookieImportRepository

    public init(_ apps: MiniAppRepository, _ imports: CookieImportRepository) { self.apps = apps; self.imports = imports }

    public func callAsFunction() async -> Set<String> {
        var sites = Set<String>()
        for await list in apps.watchAll() {
            for app in list { if let host = URL(string: app.url)?.host, !host.isEmpty { sites.insert(cookieSite(of: host)) } }
            break
        }
        if case .success(let all) = await imports.all() { sites.formUnion(all.map(\.site)) }
        return sites
    }
}

/// Copies the session cookies of the kept sites out of the web view into the keychain item, replacing what was there: a
/// cookie the site dropped (a sign-out) or a site that is no longer kept goes with it. Answers what is now kept.
public struct SnapshotSessionCookies: Sendable {
    private let source: WebViewCookieSource
    private let store: SessionCookieStore
    private let sites: SessionCookieSites

    public init(_ source: WebViewCookieSource, _ store: SessionCookieStore, _ sites: SessionCookieSites) {
        self.source = source; self.store = store; self.sites = sites
    }

    /// - Parameters:
    ///   - previous: what the last snapshot kept; the keychain is not written when nothing changed.
    ///   - allowEmpty: false when an empty answer cannot be trusted (the app is quitting and the web view may be gone
    ///     already), so it never wipes what is kept.
    public func callAsFunction(previous: [BrowserCookie]? = nil, allowEmpty: Bool = true) async -> Outcome<[BrowserCookie]> {
        let live: [BrowserCookie]
        switch await source.all() {
        case .success(let all): live = all
        case .failure(let f): return .failure(f)
        }
        let kept = SessionCookieSnapshot.select(live, sites: await sites())
        if kept.isEmpty && !allowEmpty { return .success(previous ?? []) }
        if let previous, previous == kept { return .success(kept) }
        switch await store.save(kept) {
        case .success: return .success(kept)
        case .failure(let f): return .failure(f)
        }
    }
}

/// Puts the kept session cookies back into the web view (at launch, before a mini app's page loads). Only those of the
/// sites still kept, and never over a cookie the web view already has. Answers what is kept now.
public struct RestoreSessionCookies: Sendable {
    private let store: SessionCookieStore
    private let webView: WebViewCookieRepository
    private let sites: SessionCookieSites

    public init(_ store: SessionCookieStore, _ webView: WebViewCookieRepository, _ sites: SessionCookieSites) {
        self.store = store; self.webView = webView; self.sites = sites
    }

    public func callAsFunction() async -> Outcome<[BrowserCookie]> {
        let saved: [BrowserCookie]
        switch await store.load() {
        case .success(let all): saved = all
        case .failure(let f): return .failure(f)
        }
        let kept = SessionCookieSnapshot.select(saved, sites: await sites())
        // A site that is no longer kept (its mini app was removed while the app was closed, say) is dropped from the item.
        if kept.count != saved.count { _ = await store.save(kept) }
        guard !kept.isEmpty else { return .success([]) }
        var present = Set<CookieKey>()
        if case .success(let found) = await webView.present(kept.map(\.key)) { present = found }
        let missing = kept.filter { !present.contains($0.key) }
        if !missing.isEmpty, case .failure(let f) = await webView.write(missing) { return .failure(f) }
        return .success(kept)
    }
}

/// Forgets every kept session cookie ("clear all browsing data").
public struct ForgetSessionCookies: Sendable {
    private let store: SessionCookieStore

    public init(_ store: SessionCookieStore) { self.store = store }

    public func callAsFunction() async -> Outcome<Void> { await store.save([]) }
}
