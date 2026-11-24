import CoreUI
import SwiftUI

/// One tab's page: its web view, the loading bar, the cover for a page that failed and the windows the page opened.
struct MiniAppTabPage: View {
    @Environment(\.appTheme) private var theme
    let app: MiniApp
    let model: MiniAppsModel
    let tabs: MiniAppTabsModel
    let tab: MiniAppBrowserModel
    /// The page is the one on screen; a page kept behind another stops drawing (`MiniAppWebView`).
    var shown = true

    var body: some View {
        ZStack(alignment: .top) {
            // The same web view is kept while the tab is open, so the page is left alone on every progress tick.
            MiniAppWebView(app: app, model: model, tabs: tabs, browser: tab, shown: shown)
            if tab.loading {
                ProgressView(value: tab.progress).progressViewStyle(.linear).tint(theme.colors.accent)
            }
            if let error = tab.loadError { MiniAppLoadErrorView(message: error) { tab.reload() } }
            if let popup = tab.popups.last {
                theme.colors.scrim.opacity(0.35).onTapGesture {}
                MiniAppPopupView(popup: popup) { tab.remove(popup) }.padding(theme.spacing.s24).frame(maxHeight: .infinity)
            }
        }
        .onChange(of: tab.certificateError?.origin) { _, _ in askToTrust() }
    }

    /// The page's certificate was refused: ask whether to trust the site and, if so, load the page again.
    private func askToTrust() {
        guard let refused = tab.certificateError else { return }
        tab.clearCertificateError()
        Task {
            if await model.askToTrust(origin: refused.origin, error: refused.error) { tab.reload() }
        }
    }
}
