/// Ported from: lib/features/mini_apps/domain/entities/cookie_site.dart
/// A site's cookies in one browser profile, offered as one choice. `usedByMiniApp`: a mini app opens this site, so it is offered first.
public struct CookieSite: Sendable, Equatable {
    public var site: String
    public var cookies: [BrowserCookie]
    public var usedByMiniApp: Bool
    public init(site: String, cookies: [BrowserCookie], usedByMiniApp: Bool = false) {
        self.site = site; self.cookies = cookies; self.usedByMiniApp = usedByMiniApp
    }
}
