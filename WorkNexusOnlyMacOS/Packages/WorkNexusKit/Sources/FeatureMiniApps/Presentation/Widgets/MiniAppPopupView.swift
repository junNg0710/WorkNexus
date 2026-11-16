import AppKit
import CoreUI
import SwiftUI

/// Ported from: lib/features/mini_apps/presentation/widgets/mini_app_popup.dart + mini_app_popup_header.dart
/// The window a page asked for shown over the mini app. Its bar goes back and forward through the pages it has been to,
/// opens the current page in the browser, and closes it.
struct MiniAppPopupView: View {
    @Environment(\.appTheme) private var theme
    let popup: MiniAppPopupWindow
    let onClose: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: theme.spacing.s4) {
                AppIconButton("chevron.left", help: String(localized: "miniAppBack")) { popup.web.goBack() }.disabled(!popup.canGoBack)
                AppIconButton("chevron.right", help: String(localized: "miniAppForward")) { popup.web.goForward() }.disabled(!popup.canGoForward)
                Text(popup.title.isEmpty ? (popup.url?.host ?? "") : popup.title).font(theme.typography.bodyStrong)
                    .foregroundStyle(theme.colors.tx).lineLimit(1).frame(maxWidth: .infinity, alignment: .leading)
                if MiniAppPopupWindow.isWebAddress(popup.url), let url = popup.url {
                    AppIconButton("safari", help: String(localized: "miniAppOpenInBrowser")) { NSWorkspace.shared.open(url) }
                }
                AppIconButton("xmark", help: String(localized: "close"), action: onClose)
            }
            .padding(.horizontal, theme.spacing.s8).frame(height: theme.sizes.control36).background(theme.colors.panel)
            Divider().overlay(theme.colors.line)
            HostedWebView(web: popup.web)
        }
        .frame(width: 520, height: 720)
        .background(theme.colors.card, in: RoundedRectangle(cornerRadius: theme.radii.lg))
        .clipShape(RoundedRectangle(cornerRadius: theme.radii.lg))
        .overlay(RoundedRectangle(cornerRadius: theme.radii.lg).stroke(theme.colors.line, lineWidth: theme.borders.hairline))
        .shadow(radius: 24)
    }
}
