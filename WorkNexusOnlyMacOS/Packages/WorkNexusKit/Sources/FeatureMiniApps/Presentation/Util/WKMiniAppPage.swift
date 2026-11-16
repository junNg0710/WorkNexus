import AppKit
import Foundation
import WebKit

/// Ported from: lib/features/mini_apps/presentation/util/in_app_web_view_page.dart
/// A mini app's page in a `WKWebView`.
@MainActor
final class WKMiniAppPage: MiniAppPageDriver {
    private weak var web: WKWebView?
    init(_ web: WKWebView) { self.web = web }

    func load(_ url: String) { if let u = URL(string: url) { web?.load(URLRequest(url: u)) } }
    func reload() { web?.reload() }
    /// A reload that skips the cache (WKWebView: a reload from the origin).
    func hardReload() { web?.reloadFromOrigin() }
    func stop() { web?.stopLoading() }
    func goBack() { web?.goBack() }
    func goForward() { web?.goForward() }
}

/// Builds the web views of the mini apps: the web profile every mini app shares (so sign-ins survive and cookies imported
/// from a browser are seen), the capabilities' scripts and their bridge.
@MainActor
enum MiniAppWebFactory {
    static func makeConfiguration(bridge: MiniAppBridge, capabilities: [MiniAppPageCapability]) -> WKWebViewConfiguration {
        let config = WKWebViewConfiguration()
        config.websiteDataStore = .default()
        config.preferences.javaScriptCanOpenWindowsAutomatically = true
        config.preferences.isElementFullscreenEnabled = true
        let controller = config.userContentController
        for capability in capabilities {
            guard let script = capability.script else { continue }
            controller.addUserScript(WKUserScript(source: script.source, injectionTime: script.atDocumentStart ? .atDocumentStart : .atDocumentEnd,
                                                  forMainFrameOnly: true, in: capability.contentWorld))
        }
        // One handler per world: a capability in a world of its own is out of the page's reach, and the bridge refuses a
        // call that comes from another world than the capability's.
        for world in bridge.worlds { controller.addScriptMessageHandler(bridge, contentWorld: world, name: MiniAppBridge.handlerName) }
        return config
    }

    static func makeWebView(configuration: WKWebViewConfiguration) -> WKWebView {
        let web = WKWebView(frame: .zero, configuration: configuration)
        // Right-click → Inspect Element, in place of the Flutter build's developer-tools button.
        web.isInspectable = true
        web.allowsBackForwardNavigationGestures = true
        web.allowsMagnification = true
        return web
    }
}

/// A tab's web view with everything that has to live as long as it does: its delegate, its page driver, the bridge and
/// the capabilities (notifications, ZenTao login, saved passwords). Held by the tab's `MiniAppBrowserModel`.
@MainActor
struct MiniAppWebParts {
    let web: WKWebView
    let delegate: MiniAppWebDelegate
    let page: WKMiniAppPage
    let prompter: MiniAppPermissionPrompter

    /// A tab's own web view (a new tab, or the app's first page), with its own capabilities and bridge. It opens on
    /// `browser.initialUrl`, unless the caller loads something itself (`loadInitialPage` false).
    static func make(app: MiniApp, model: MiniAppsModel, browser: MiniAppBrowserModel, tabs: MiniAppTabsModel? = nil,
                     loadInitialPage: Bool = true) -> MiniAppWebParts {
        let prompter = tabs?.prompter ?? MiniAppPermissionPrompter(model: model)
        let notifications = MiniAppNotificationCapability(notifier: model.services.notifier, isWindowFocused: { NSApp.isActive && NSApp.keyWindow != nil })
        let login = MiniAppLoginCapability()
        let passwords = MiniAppPasswordCapability(tab: browser)
        let capabilities: [(MiniAppPageCapability, token: String)] = [(notifications, notifications.token), (login, login.token),
                                                                      (passwords, passwords.token)]
        let bridge = MiniAppBridge(capabilities: capabilities) { [unowned model] web in
            MiniAppPageContext(app: { model.current(app) }, pageURL: web?.url, model: model, prompter: prompter,
                               selectedTab: model.isSelectedTab(appId: app.id, web: web))
        }
        let config = MiniAppWebFactory.makeConfiguration(bridge: bridge, capabilities: capabilities.map(\.0))
        let parts = wire(MiniAppWebFactory.makeWebView(configuration: config), app: app, model: model, browser: browser, tabs: tabs,
                         prompter: prompter, bridge: bridge)
        if loadInitialPage, let url = URL(string: browser.initialUrl) {
            // At launch the session cookies kept from the last run go back into the web view first, so the page opens signed in.
            if let keeper = model.sessionCookies, !keeper.isReady {
                let web = parts.web
                Task { @MainActor in await keeper.ready(); web.load(URLRequest(url: url)) }
            } else { parts.web.load(URLRequest(url: url)) }
        }
        return parts
    }

    /// The web view of a window the page opened on the app's own site: built from the configuration WebKit handed over (so
    /// the page can talk back to its opener, and the opener's scripts and bridge are in it) and loaded by WebKit itself.
    static func adopt(_ web: WKWebView, app: MiniApp, model: MiniAppsModel, browser: MiniAppBrowserModel, tabs: MiniAppTabsModel,
                      prompter: MiniAppPermissionPrompter, bridge: MiniAppBridge?) -> MiniAppWebParts {
        wire(web, app: app, model: model, browser: browser, tabs: tabs, prompter: prompter, bridge: bridge)
    }

    private static func wire(_ web: WKWebView, app: MiniApp, model: MiniAppsModel, browser: MiniAppBrowserModel, tabs: MiniAppTabsModel?,
                             prompter: MiniAppPermissionPrompter, bridge: MiniAppBridge?) -> MiniAppWebParts {
        let delegate = MiniAppWebDelegate(app: app, model: model, browser: browser, prompter: prompter, bridge: bridge)
        delegate.tabs = tabs
        web.navigationDelegate = delegate
        web.uiDelegate = delegate
        delegate.observe(web)
        let page = WKMiniAppPage(web)
        browser.attach(page)
        browser.passwords.bind(model.services.webLogins, filler: WKLoginFiller(web: web))
        let parts = MiniAppWebParts(web: web, delegate: delegate, page: page, prompter: prompter)
        browser.parts = parts
        return parts
    }

    /// The tab closes: its page stops and nothing calls back into it. (The script handler is the opener's too when the tab
    /// came from a window request, so it stays; it goes with the web view.)
    func teardown() {
        web.stopLoading()
        web.navigationDelegate = nil
        web.uiDelegate = nil
    }
}
