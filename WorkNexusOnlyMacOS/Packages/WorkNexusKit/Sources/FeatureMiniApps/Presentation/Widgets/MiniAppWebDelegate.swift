import AppKit
import Foundation
import WebKit

/// Ported from: lib/features/mini_apps/presentation/widgets/mini_app_web_view.dart (+ mini_app_certificate_guard.dart, mini_app_popup.dart)
/// The app's answers to what a mini app's page asks for, for the page's `WKWebView` and for the windows it opens: what the
/// page does is reported to the app's `MiniAppBrowserModel` (or, for a pop-up, to its `MiniAppPopupWindow`).
/// Navigation half here; the page's own UI requests (windows, dialogs, files, camera) are in `MiniAppWebDelegate+UI.swift`.
@MainActor
final class MiniAppWebDelegate: NSObject, WKNavigationDelegate, WKUIDelegate {
    let app: MiniApp
    unowned let model: MiniAppsModel
    /// The tab the page is in (it owns this delegate, through its web view's parts).
    unowned let browser: MiniAppBrowserModel
    /// The app's tabs: where a link the page opens on the app's own site goes. Nil for a pop-up's page.
    weak var tabs: MiniAppTabsModel?
    let prompter: MiniAppPermissionPrompter
    /// Set for a window the page opened; nil for the mini app's own page.
    let popup: MiniAppPopupWindow?
    private var observers: [NSKeyValueObservation] = []
    let bridge: MiniAppBridge?

    init(app: MiniApp, model: MiniAppsModel, browser: MiniAppBrowserModel, prompter: MiniAppPermissionPrompter,
         popup: MiniAppPopupWindow? = nil, bridge: MiniAppBridge? = nil) {
        self.app = app; self.model = model; self.browser = browser; self.prompter = prompter; self.popup = popup; self.bridge = bridge
    }

    /// Follows the web view's progress, address and history, and reports them.
    func observe(_ web: WKWebView) {
        observers = [
            web.observe(\.estimatedProgress, options: [.new]) { [weak self] web, _ in
                MainActor.assumeIsolated { if web.isLoading { self?.browser.onProgress(web.estimatedProgress) } }
            },
            web.observe(\.isLoading, options: [.new]) { [weak self] web, _ in
                MainActor.assumeIsolated {
                    if web.isLoading { self?.browser.onProgress(max(web.estimatedProgress, 0.05)) } else { self?.browser.onProgress(1) }
                }
            },
            web.observe(\.url, options: [.new]) { [weak self] web, _ in MainActor.assumeIsolated { self?.visited(web) } },
            web.observe(\.canGoBack, options: [.new]) { [weak self] web, _ in MainActor.assumeIsolated { self?.history(web) } },
            web.observe(\.canGoForward, options: [.new]) { [weak self] web, _ in MainActor.assumeIsolated { self?.history(web) } },
            web.observe(\.title, options: [.new]) { [weak self] web, _ in MainActor.assumeIsolated { self?.titled(web) } },
        ]
    }

    private func titled(_ web: WKWebView) {
        if let popup { popup.title = web.title ?? "" } else { browser.onTitle(web.title ?? "") }
    }

    private func visited(_ web: WKWebView) {
        guard let url = web.url else { return }
        if let popup { popup.url = url; popup.canGoBack = web.canGoBack; popup.canGoForward = web.canGoForward; return }
        browser.onVisited(url, canGoBack: web.canGoBack, canGoForward: web.canGoForward)
    }

    private func history(_ web: WKWebView) {
        if let popup { popup.canGoBack = web.canGoBack; popup.canGoForward = web.canGoForward; return }
        browser.onNavigationState(canGoBack: web.canGoBack, canGoForward: web.canGoForward)
    }

    // MARK: Navigation

    /// Only web pages load in the view; a `mailto:` or another app's scheme goes to the system, which `open` would otherwise
    /// try as a local path.
    func webView(_ webView: WKWebView, decidePolicyFor action: WKNavigationAction) async -> WKNavigationActionPolicy {
        guard let url = action.request.url, let scheme = url.scheme?.lowercased() else { return .allow }
        if opensInBackgroundTab(action, url) { return .cancel }
        if ["http", "https", "about", "blob", "data", "file", "javascript"].contains(scheme) { return .allow }
        NSWorkspace.shared.open(url)
        return .cancel
    }

    /// A middle click or ⌘-click on a link to the app's own site opens it in another tab (in front with ⇧), as in a browser.
    private func opensInBackgroundTab(_ action: WKNavigationAction, _ url: URL) -> Bool {
        guard popup == nil, let tabs, action.navigationType == .linkActivated, url.scheme == "http" || url.scheme == "https",
              action.buttonNumber == MiniAppWebDelegate.middleButton || action.modifierFlags.contains(.command),
              IsMiniAppSite()(model.current(app).url, url.absoluteString) else { return false }
        return tabs.newTab(url: url.absoluteString, select: action.modifierFlags.contains(.shift)) != nil
    }

    /// `WKNavigationAction.buttonNumber` of the middle mouse button (left is 1, right 2).
    static let middleButton = 4

    func webView(_ webView: WKWebView, didStartProvisionalNavigation navigation: WKNavigation!) {
        if popup == nil { browser.onLoadStart() }
    }

    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) { failed(error) }
    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) { failed(error) }

    private func failed(_ error: Error) {
        let ns = error as NSError
        // A load replaced by another (cancelled) or turned into a download (frame load interrupted) is not a failure.
        if ns.domain == NSURLErrorDomain && ns.code == NSURLErrorCancelled { return }
        if ns.domain == "WebKitErrorDomain" && ns.code == 102 { return }
        guard popup == nil else { return }
        if ns.domain == NSURLErrorDomain, let code = CertificateProblem.code(forURLErrorCode: ns.code),
           let origin = MiniAppsModel.origin(of: ns.userInfo[NSURLErrorFailingURLErrorKey] as? URL) {
            browser.onCertificateError(origin: origin, error: code)
        }
        browser.onError(ns.localizedDescription)
    }

    /// The page's process died (out of memory, mostly): bring it back instead of leaving a blank view.
    func webViewWebContentProcessDidTerminate(_ webView: WKWebView) { webView.reload() }

    /// A server the system refuses is let through when the user chose to trust its site (`MiniAppsModel.askToTrust`, or the
    /// edit dialog's switch, also for the servers the mini app's own trusted site calls), or when
    /// its certificate is one the user already accepted in the app (the ZenTao chat server's self-signed one, which
    /// ZenTao's own web chat calls) — for that very certificate only. Every other answer stays the web view's own.
    ///
    /// Trust is for the site, not for one problem: while the page shown is a trusted site's, errors of every kind are
    /// accepted (the page's own requests, such as the blocks a dashboard fills in after loading, meet the same
    /// certificate and would fail otherwise).
    func webView(_ webView: WKWebView, respondTo challenge: URLAuthenticationChallenge) async -> (URLSession.AuthChallengeDisposition, URLCredential?) {
        let space = challenge.protectionSpace
        guard space.authenticationMethod == NSURLAuthenticationMethodServerTrust, let trust = space.serverTrust else { return (.performDefaultHandling, nil) }
        // The system's own answer stands when it trusts the certificate.
        if SecTrustEvaluateWithError(trust, nil) { return (.performDefaultHandling, nil) }
        let origin = "https://\(space.host):\(space.port == 0 ? 443 : space.port)"
        let shown = MiniAppsModel.origin(of: webView.url)
        if await model.isTrusted(origin) { return (.useCredential, URLCredential(trust: trust)) }
        if let shown, await model.isTrusted(shown) { return (.useCredential, URLCredential(trust: trust)) }
        // The mini app's own site, trusted in its settings: the servers its page calls are let through too, wherever
        // the page has gone since.
        if let home = MiniAppsModel.origin(of: URL(string: app.url)), await model.isTrusted(home) {
            return (.useCredential, URLCredential(trust: trust))
        }
        if let leaf = (SecTrustCopyCertificateChain(trust) as? [SecCertificate])?.first,
           await model.services.isPinnedCertificate(SecCertificateCopyData(leaf) as Data) {
            return (.useCredential, URLCredential(trust: trust))
        }
        return (.performDefaultHandling, nil)
    }
}
