import CoreDomain
import Foundation

/// Ported from: lib/features/mini_apps/data/repositories/local_web_view_cookie_repository.dart
/// `WebViewCookieRepository` over the shared WKWebView cookie store.
public final class WKWebViewCookieRepository: WebViewCookieRepository, Sendable {
    public init() {}
    public var canWrite: Bool { true }

    public func write(_ cookies: [BrowserCookie]) async -> Outcome<Void> {
        let source = WebViewCookieDataSource()
        var refused = 0
        for c in cookies where !(await source.write(c)) { refused += 1 }
        return !cookies.isEmpty && refused == cookies.count ? .failure(.storage("The web view refused the cookies")) : .success(())
    }

    public func present(_ keys: [CookieKey]) async -> Outcome<Set<CookieKey>> {
        .success(await WebViewCookieDataSource().present(keys))
    }
}
