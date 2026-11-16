import AppKit
import Foundation
import WebKit

/// The page's own UI requests: its windows, its dialogs, file choosers and media permissions.
extension MiniAppWebDelegate {
    // MARK: Windows

    /// A page's own window (`target=_blank`, `window.open`, a sign-in pop-up). A link the app or another mini app takes goes
    /// there and no window opens. A link on the app's own site opens as another tab of the app. Anything else — a sign-in,
    /// another site — is a pop-up over the page; the browser only opens from its button. Must answer a web view built from
    /// `configuration` so the page can talk back to its opener.
    func webView(_ webView: WKWebView, createWebViewWith configuration: WKWebViewConfiguration, for action: WKNavigationAction,
                 windowFeatures: WKWindowFeatures) -> WKWebView? {
        // Where any other tapped link goes: the app if it shows that link itself, else the mini app of that site (never
        // this very app, whose own links stay in its window), else a tab or the pop-up below. A sign-in is always the
        // pop-up: the page waits on it for the answer.
        let width = windowFeatures.width?.doubleValue, height = windowFeatures.height?.doubleValue
        let link = action.request.url?.absoluteString
        if let link, model.routeWindowLink(link, currentAppId: app.id, width: width, height: height) { return nil }
        if popup == nil, let link, let tabs, tabs.canOpenTab, model.opensAsTab(link, appId: app.id, width: width, height: height) {
            return openTab(configuration: configuration, link: link, tabs: tabs)
        }
        let web = MiniAppWebFactory.makeWebView(configuration: configuration)
        let window = MiniAppPopupWindow(web: web)
        let delegate = MiniAppWebDelegate(app: app, model: model, browser: browser, prompter: prompter, popup: window, bridge: bridge)
        web.navigationDelegate = delegate
        web.uiDelegate = delegate
        delegate.observe(web)
        window.delegate = delegate
        browser.add(window)
        return web
    }

    /// The page's window as a tab of its own, in front. WebKit loads `link` in it.
    private func openTab(configuration: WKWebViewConfiguration, link: String, tabs: MiniAppTabsModel) -> WKWebView? {
        guard let tab = tabs.makeTab(url: link) else { return nil }
        tab.openedByPage = true
        let web = MiniAppWebFactory.makeWebView(configuration: configuration)
        _ = MiniAppWebParts.adopt(web, app: app, model: model, browser: tab, tabs: tabs, prompter: prompter, bridge: bridge)
        tabs.add(tab, select: true)
        return web
    }

    /// The page closes its own window when it is done (sign-in, a tab it opened).
    func webViewDidClose(_ webView: WKWebView) {
        if let popup { browser.remove(popup); return }
        // Only a tab the page itself opened can close itself: the app's pages are closed by the user.
        if browser.openedByPage { tabs?.close(browser.id) }
    }

    // MARK: Media

    /// Camera and microphone: the answer remembered for the app, else the user's — asked once, for the app's own site only.
    func webView(_ webView: WKWebView, requestMediaCapturePermissionFor origin: WKSecurityOrigin, initiatedByFrame frame: WKFrameInfo,
                 type: WKMediaCaptureType) async -> WKPermissionDecision {
        var comps = URLComponents()
        comps.scheme = origin.protocol; comps.host = origin.host; if origin.port != 0 { comps.port = origin.port }
        let decision = await prompter.ask(app: model.current(app), kinds: miniAppPermissionKinds(of: type), origin: comps.url)
        return decision == .allow ? .grant : .deny
    }

    // MARK: Dialogs and files (WebKit shows none of them by itself)

    func webView(_ webView: WKWebView, runJavaScriptAlertPanelWithMessage message: String, initiatedByFrame frame: WKFrameInfo) async {
        let alert = dialog(message, frame)
        alert.addButton(withTitle: String(localized: "confirm"))
        _ = await MiniAppPermissionPrompter.run(alert)
    }

    func webView(_ webView: WKWebView, runJavaScriptConfirmPanelWithMessage message: String, initiatedByFrame frame: WKFrameInfo) async -> Bool {
        let alert = dialog(message, frame)
        alert.addButton(withTitle: String(localized: "confirm"))
        alert.addButton(withTitle: String(localized: "cancel"))
        return await MiniAppPermissionPrompter.run(alert) == .alertFirstButtonReturn
    }

    func webView(_ webView: WKWebView, runJavaScriptTextInputPanelWithPrompt prompt: String, defaultText: String?,
                 initiatedByFrame frame: WKFrameInfo) async -> String? {
        let alert = dialog(prompt, frame)
        let field = NSTextField(frame: NSRect(x: 0, y: 0, width: 260, height: 24))
        field.stringValue = defaultText ?? ""
        alert.accessoryView = field
        alert.addButton(withTitle: String(localized: "confirm"))
        alert.addButton(withTitle: String(localized: "cancel"))
        return await MiniAppPermissionPrompter.run(alert) == .alertFirstButtonReturn ? field.stringValue : nil
    }

    func webView(_ webView: WKWebView, runOpenPanelWith parameters: WKOpenPanelParameters, initiatedByFrame frame: WKFrameInfo) async -> [URL]? {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = parameters.allowsMultipleSelection
        panel.canChooseDirectories = parameters.allowsDirectories
        panel.canChooseFiles = true
        let response = await withCheckedContinuation { cont in
            if let window = webView.window { panel.beginSheetModal(for: window) { cont.resume(returning: $0) } }
            else { panel.begin { cont.resume(returning: $0) } }
        }
        return response == .OK ? panel.urls : nil
    }

    private func dialog(_ message: String, _ frame: WKFrameInfo) -> NSAlert {
        let alert = NSAlert()
        alert.messageText = frame.request.url?.host ?? app.name
        alert.informativeText = message
        return alert
    }
}
