import AppKit
import SwiftUI
import WebKit

/// Ported from: lib/features/mini_apps/presentation/widgets/mini_app_web_view.dart
/// The web page of a tab of a mini app, with the app's answers to what the page asks for (`MiniAppWebDelegate`), the
/// capabilities the app lends it (notifications, saved login) and its own windows. What the page does is reported to the
/// tab's `MiniAppBrowserModel`, which also keeps the web view (a tab a page opened arrives with its own).
///
/// A page kept behind the one on screen (another app on the rail, another tab, the mini apps while a different place is
/// shown) stays in the window, only see-through - and a web view in a window counts as on screen: every such page went on
/// drawing itself and running its animations at the display's rate, taking frames from whatever the user was looking at.
/// While `shown` is false the web view is hidden for real, so the page knows it is in the background (`document.hidden`):
/// it stops drawing and its timers slow down, as a browser's background tabs do. It keeps running - its sockets, its
/// notifications - and is there at once when shown again.
struct MiniAppWebView: NSViewRepresentable {
    let app: MiniApp
    let model: MiniAppsModel
    let tabs: MiniAppTabsModel
    let browser: MiniAppBrowserModel
    var shown = true

    @MainActor
    func makeNSView(context: Context) -> WKWebView {
        let web = browser.parts?.web ?? MiniAppWebParts.make(app: app, model: model, browser: browser, tabs: tabs).web
        Self.show(shown, web)
        return web
    }

    func updateNSView(_ web: WKWebView, context: Context) { Self.show(shown, web) }

    /// Hides `view` unless `shown`, touching it only when that changes.
    @MainActor
    static func show(_ shown: Bool, _ view: NSView) {
        if view.isHidden == shown { view.isHidden = !shown }
    }
}

/// A window the page opened, shown inside the app.
struct HostedWebView: NSViewRepresentable {
    let web: WKWebView
    func makeNSView(context: Context) -> WKWebView { web }
    func updateNSView(_ web: WKWebView, context: Context) {}
}
