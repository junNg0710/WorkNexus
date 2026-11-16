import Foundation
import WebKit

/// Ported from: lib/features/mini_apps/data/datasources/web_view_cookie_datasource.dart
/// The cookies of the web profile the mini apps' web views share (`WKWebsiteDataStore.default()`), through the web view's
/// own cookie store — HttpOnly and expiry included.
struct WebViewCookieDataSource {
    @MainActor private var store: WKHTTPCookieStore { WKWebsiteDataStore.default().httpCookieStore }

    /// Sets `cookie`; false when the web view refused it (or it cannot be expressed as an HTTP cookie).
    @MainActor func write(_ cookie: BrowserCookie) async -> Bool {
        guard let http = Self.httpCookie(cookie) else { return false }
        await store.setCookie(http)
        return true
    }

    /// Which of `keys` the web view has (live ones only).
    @MainActor func present(_ keys: [CookieKey]) async -> Set<CookieKey> {
        let live = await store.allCookies().filter { $0.expiresDate.map { $0 > Date() } ?? true }
        return Set(keys.filter { key in live.contains { Self.matches($0, key) } })
    }

    nonisolated static func matches(_ cookie: HTTPCookie, _ key: CookieKey) -> Bool {
        guard cookie.name == key.name else { return false }
        let includesSubdomains = cookie.domain.hasPrefix(".")
        let host = includesSubdomains ? String(cookie.domain.dropFirst()) : cookie.domain
        let hostMatches = host.lowercased() == key.host.lowercased() || (includesSubdomains && key.host.lowercased().hasSuffix("." + host.lowercased()))
        return hostMatches && key.path.hasPrefix(cookie.path)
    }

    nonisolated static func httpCookie(_ c: BrowserCookie) -> HTTPCookie? {
        var props: [HTTPCookiePropertyKey: Any] = [.name: c.name, .value: c.value, .path: c.path,
                                                   // A leading dot means subdomains too; none means this host only.
                                                   .domain: c.includesSubdomains ? c.domain : c.host]
        if c.secure { props[.secure] = "TRUE" }
        if c.httpOnly { props[HTTPCookiePropertyKey("HttpOnly")] = "TRUE" }
        if let expires = c.expires { props[.expires] = expires }
        switch c.sameSite {
        case .lax: props[.sameSitePolicy] = HTTPCookieStringPolicy.sameSiteLax
        case .strict: props[.sameSitePolicy] = HTTPCookieStringPolicy.sameSiteStrict
        case .none, .unspecified: break
        }
        return HTTPCookie(properties: props)
    }
}

/// Ported from: lib/features/mini_apps/data/datasources/web_profile_datasource.dart
/// The web profile every mini app shares, cleared through `WKWebsiteDataStore`.
struct WebProfileDataSource {
    @MainActor private var store: WKWebsiteDataStore { .default() }

    @MainActor func clearCache() async {
        await store.removeData(ofTypes: [WKWebsiteDataTypeDiskCache, WKWebsiteDataTypeMemoryCache], modifiedSince: .distantPast)
    }

    /// Every kind of storage the sites of `hosts` keep, cookies included.
    @MainActor func clearSites(hosts: Set<String>) async {
        let all = WKWebsiteDataStore.allWebsiteDataTypes()
        let records = await store.dataRecords(ofTypes: all)
        // A record is named after the registrable domain (`example.com`), so a host matches when it is that domain or under it.
        let doomed = records.filter { r in hosts.contains { $0 == r.displayName || $0.hasSuffix("." + r.displayName) } }
        await store.removeData(ofTypes: all, for: doomed)
    }

    @MainActor func clearAll() async {
        await store.removeData(ofTypes: WKWebsiteDataStore.allWebsiteDataTypes(), modifiedSince: .distantPast)
    }
}
