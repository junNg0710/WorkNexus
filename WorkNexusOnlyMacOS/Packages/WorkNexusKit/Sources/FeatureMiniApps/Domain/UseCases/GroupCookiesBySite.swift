import Foundation

/// Ported from: lib/features/mini_apps/domain/usecases/group_cookies_by_site.dart
/// Groups a browser profile's cookies into the sites a user picks from: the ones a mini app opens first, then by name.
/// Expired and empty cookies are left out, as a web view would not take them.
public struct GroupCookiesBySite: Sendable {
    public init() {}

    public func callAsFunction(_ cookies: [BrowserCookie], miniAppUrls: [String], now: Date) -> [CookieSite] {
        let appSites = Set(miniAppUrls.compactMap { URL(string: $0)?.host }.filter { !$0.isEmpty }.map(cookieSite(of:)))
        var bySite: [String: [BrowserCookie]] = [:]
        for c in cookies where !c.value.isEmpty && !c.isExpired(at: now) { bySite[cookieSite(of: c.domain), default: []].append(c) }
        return bySite.map { CookieSite(site: $0.key, cookies: $0.value, usedByMiniApp: appSites.contains($0.key)) }
            .sorted { a, b in
                if a.usedByMiniApp != b.usedByMiniApp { return a.usedByMiniApp }
                return a.site < b.site
            }
    }
}
