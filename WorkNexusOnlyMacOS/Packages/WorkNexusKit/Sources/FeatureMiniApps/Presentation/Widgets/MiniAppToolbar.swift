import CoreUI
import SwiftUI

/// Ported from: lib/features/mini_apps/presentation/widgets/mini_app_toolbar.dart
/// A browser-style bar over a mini app's page: back, forward, reload / stop, home, the address field, `trailing` (the cookie
/// import) and "open in browser". The browser's keys (see `MiniAppShortcuts`) are heard by `MiniAppKeyMonitor`.
struct MiniAppToolbar<Trailing: View>: View {
    @Environment(\.appTheme) private var theme
    @Binding var address: String
    var focus: FocusState<Bool>.Binding
    let browser: MiniAppBrowserModel
    let onSubmit: (String) -> Void
    let onHome: () -> Void
    let onOpenExternal: () -> Void
    @ViewBuilder var trailing: Trailing

    var body: some View {
        HStack(spacing: theme.spacing.s4) {
            AppIconButton("chevron.left", help: appString("miniAppBack", "Back")) { browser.goBack() }
                .disabled(!browser.canGoBack).opacity(browser.canGoBack ? 1 : 0.4)
            AppIconButton("chevron.right", help: appString("miniAppForward", "Forward")) { browser.goForward() }
                .disabled(!browser.canGoForward).opacity(browser.canGoForward ? 1 : 0.4)
            if browser.loading { AppIconButton("xmark", help: appString("miniAppStop", "Stop")) { browser.stop() } }
            else { AppIconButton("arrow.clockwise", help: appString("miniAppReload", "Reload")) { browser.reload() } }
            AppIconButton("house", help: appString("miniAppHome", "Home")) { onHome() }
            TextField(appString("miniAppUrlHint", "example.com"), text: $address)
                .textFieldStyle(.plain).font(theme.typography.paragraph).foregroundStyle(theme.colors.tx)
                .focused(focus).onSubmit { onSubmit(address) }
                .padding(.horizontal, theme.spacing.s10).frame(height: theme.sizes.control32)
                .background(theme.colors.panel2, in: RoundedRectangle(cornerRadius: theme.radii.md))
                .overlay(RoundedRectangle(cornerRadius: theme.radii.md).stroke(theme.colors.line, lineWidth: theme.borders.hairline))
            trailing
            AppIconButton("safari", help: appString("miniAppOpenInBrowser", "Open in browser")) { onOpenExternal() }
        }
        .padding(.horizontal, theme.spacing.s10).padding(.vertical, theme.spacing.s6)
        .background(theme.colors.panel)
        .overlay(alignment: .bottom) { Rectangle().fill(theme.colors.line).frame(height: theme.borders.hairline) }
    }
}
