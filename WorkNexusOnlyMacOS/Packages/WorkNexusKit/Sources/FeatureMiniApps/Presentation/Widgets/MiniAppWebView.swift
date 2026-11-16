import AppKit
import SwiftUI
import WebKit

/// Ported from: lib/features/mini_apps/presentation/widgets/mini_app_web_view.dart
/// The web page of a tab of a mini app, with the app's answers to what the page asks for (`MiniAppWebDelegate`), the
/// capabilities the app lends it (notifications, saved login) and its own windows. What the page does is reported to the
/// tab's `MiniAppBrowserModel`, which also keeps the web view (a tab a page opened arrives with its own).
struct MiniAppWebView: NSViewRepresentable {
    let app: MiniApp
    let model: MiniAppsModel
    let tabs: MiniAppTabsModel
    let browser: MiniAppBrowserModel

    @MainActor
    func makeNSView(context: Context) -> WKWebView {
        if let parts = browser.parts { return parts.web }
        return MiniAppWebParts.make(app: app, model: model, browser: browser, tabs: tabs).web
    }

    func updateNSView(_ web: WKWebView, context: Context) {}
}

/// A window the page opened, shown inside the app.
struct HostedWebView: NSViewRepresentable {
    let web: WKWebView
    func makeNSView(context: Context) -> WKWebView { web }
    func updateNSView(_ web: WKWebView, context: Context) {}
}
