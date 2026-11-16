import CoreDomain
import Foundation

/// Ported from: lib/features/mini_apps/data/repositories/local_web_view_cookie_repository.dart
/// `WebViewCookieRepository` over the shared WKWebView cookie store; also what the session-cookie keeper reads and listens to.
public final class WKWebViewCookieRepository: WebViewCookieRepository, WebViewCookieSource, Sendable {
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

    public func all() async -> Outcome<[BrowserCookie]> { .success(await WebViewCookieDataSource().all()) }

    public func changes() -> AsyncStream<Void> {
        // The store is the main actor's: the observer is added there and its events are passed on.
        AsyncStream(bufferingPolicy: .bufferingNewest(1)) { continuation in
            let task = Task { @MainActor in
                for await _ in WebViewCookieDataSource().changes() { continuation.yield(()) }
                continuation.finish()
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }
}
