import CoreUI
import SwiftUI

/// Ported from: lib/features/mini_apps/presentation/widgets/mini_app_cookie_button.dart
/// A mini app's toolbar button to sign it in with a browser's cookies: opens the import on this app's site, from the browser
/// it last came from. Tinted once those cookies are gone; each page load checks again, as that is when a site signs one out.
/// Hidden where the web view takes no cookies.
struct MiniAppCookieButton: View {
    @Environment(\.appTheme) private var theme
    let app: MiniApp
    let browser: MiniAppBrowserModel
    let cookies: CookieImportModel
    @State private var open = false
    @State private var hovering = false

    var body: some View {
        let host = URL(string: app.url)?.host ?? ""
        if !host.isEmpty && cookies.canImport {
            let site = cookieSite(of: host)
            let state = cookies.states.first { $0.cookieImport.site == site }
            let source = state?.cookieImport.source
            let expired = (state?.expired ?? false) && source != nil
            let help = expired
                ? appFormat("miniAppCookiesExpiredTooltip", "Sign-in cookies expired: import them again from %1$@", source?.browser.displayName ?? "")
                : appString("miniAppCookiesImport", "Import from a browser…")
            Button { open = true } label: {
                Image(systemName: "person.badge.key").font(.system(size: theme.sizes.icon16))
                    .foregroundStyle(expired ? theme.colors.amber : (hovering ? theme.colors.tx : theme.colors.tx2))
                    .frame(width: theme.sizes.control32, height: theme.sizes.control32)
                    .background(hovering ? theme.colors.tx.opacity(0.08) : .clear, in: Circle())
                    .contentShape(Circle())
            }
            .buttonStyle(.plain).onHover { hovering = $0 }.help(help)
            .task { await cookies.refresh() }
            // A load just ended: a site signs one out while loading, so look at the cookies again.
            .onChange(of: browser.loading) { was, loading in
                if was && !loading { Task { await cookies.refresh() } }
            }
            .appDialog(isPresented: $open) {
                CookieImportDialog(cookies: cookies, site: site, source: source) { open = false }
            }
        }
    }
}
