import AppKit
import CoreUI
import SwiftUI

/// Ported from: lib/features/mini_apps/presentation/widgets/mini_app_view.dart
/// One mini app: a browser-style bar and a strip of tabs over the web page (the bar folds away with `MiniAppBars`). What each page is doing lives in its tab's
/// `MiniAppBrowserModel` (the app's tabs in `MiniAppTabsModel`); this only draws them and keeps the address field.
/// Needs `.miniApps(feature)` up the tree.
public struct MiniAppHostView: View {
    @Environment(\.miniApps) private var feature
    public let miniApp: MiniApp
    /// Whether the page is the one on screen (its browser keys only work then).
    public var active = true

    public init(miniApp: MiniApp, active: Bool = true) { self.miniApp = miniApp; self.active = active }

    public var body: some View {
        if let feature {
            // The model keeps one set of tabs per live app (and so the pages' state) while the app is kept running.
            MiniAppPageBody(app: miniApp, model: feature.model, tabs: feature.model.tabsModel(for: miniApp), cookies: feature.cookies, active: active)
        } else { Color.clear }
    }
}

private struct MiniAppPageBody: View {
    let app: MiniApp
    let model: MiniAppsModel
    let tabs: MiniAppTabsModel
    let cookies: CookieImportModel
    let active: Bool
    @Environment(\.miniAppBars) private var bars
    @State private var address = ""
    @State private var keys = MiniAppKeyMonitor()
    @FocusState private var addressFocused: Bool

    var body: some View {
        let browser = tabs.selected
        VStack(spacing: 0) {
            if !bars.collapsed {
                MiniAppToolbar(address: $address, focus: $addressFocused, browser: browser, onSubmit: go,
                               onHome: { browser.load(model.current(app).url) }, onOpenExternal: openExternal) {
                    MiniAppCookieButton(app: app, browser: browser, cookies: cookies)
                    MiniAppPasswordButton(browser: browser)
                }
                .transition(.move(edge: .top).combined(with: .opacity))
            }
            MiniAppTabStrip(app: app, tabs: tabs)
            // The selected tab's "Save password?" question, between the bars and its page.
            MiniAppPasswordSaveBar(passwords: browser.passwords)
            ZStack {
                // Every tab keeps its page; only the selected one shows (as the running apps do on the rail).
                ForEach(tabs.tabs.filter(\.activated)) { tab in
                    let shown = tab.id == tabs.selectedId
                    MiniAppTabPage(app: app, model: model, tabs: tabs, tab: tab, shown: shown && active)
                        .opacity(shown ? 1 : 0).allowsHitTesting(shown).accessibilityHidden(!shown)
                }
            }
            // The page's room is the page's whatever it holds: with no page in it the bars above floated to the middle.
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .onAppear { address = browser.address }
        .onChange(of: browser.address) { _, new in if !addressFocused { address = new } }
        .onChange(of: tabs.selectedId) { _, _ in address = tabs.selected.address }
        .onChange(of: active, initial: true) { _, on in listen(on) }
        .onChange(of: bars.collapsed) { _, _ in listen(active) }
        .onDisappear { keys.stop() }
    }

    /// Goes to what was typed in the address bar.
    private func go(_ text: String) {
        guard let url = NormalizeMiniAppUrl()(text) else { return }
        tabs.selected.load(url.absoluteString)
        addressFocused = false
    }

    private func openExternal() {
        if let url = URL(string: address) ?? URL(string: app.url) { NSWorkspace.shared.open(url) }
    }

    /// Puts the keys in the address field. It is in the bar that folds away: that comes back first, and the field takes the
    /// keys once it is there.
    private func focusAddress(_ bars: MiniAppBars) {
        guard bars.collapsed else { addressFocused = true; return }
        bars.set(false)
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(60))
            addressFocused = true
        }
    }

    /// Hears the browser's keys while this app is the one on screen.
    private func listen(_ on: Bool) {
        keys.web = { [tabs] in tabs.selected.parts?.web }
        keys.perform = { [tabs, model, app, bars] shortcut in
            switch shortcut {
            case .reload: tabs.selected.reload()
            case .hardReload: tabs.selected.hardReload()
            case .back: tabs.selected.goBack()
            case .forward: tabs.selected.goForward()
            case .home: tabs.selected.load(model.current(app).url)
            case .focusAddress: focusAddress(bars)
            case .devTools: MiniAppInspector.show(tabs.selected.parts?.web)
            case .newTab: tabs.newTab(url: model.current(app).url)
            // The last tab is not closed by ⌘W: the key goes on to close the window, which keeps the page running.
            case .closeTab: return tabs.close(tabs.selectedId)
            case .nextTab: tabs.selectNext(); return tabs.canCloseTab
            case .previousTab: tabs.selectPrevious(); return tabs.canCloseTab
            }
            return true
        }
        if on { keys.start() } else { keys.stop() }
    }
}
