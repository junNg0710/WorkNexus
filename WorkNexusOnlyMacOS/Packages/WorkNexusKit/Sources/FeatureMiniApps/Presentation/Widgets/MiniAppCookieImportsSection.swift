import CoreUI
import SwiftUI

/// Ported from: lib/features/mini_apps/presentation/widgets/mini_app_cookie_imports_section.dart
/// Settings' imported cookies: a button to import from a browser, then each imported site with where it came from, whether its
/// sign-in is still there and a way to import it again.
struct MiniAppCookieImportsSection: View {
    @Environment(\.appTheme) private var theme
    let cookies: CookieImportModel
    var dateFormat = "iso"
    @State private var importing = false

    var body: some View {
        VStack(alignment: .leading, spacing: theme.spacing.s10) {
            AppButton(appString("miniAppCookiesImport", "Import from a browser…"), systemImage: "person.badge.key") { importing = true }
                .disabled(!cookies.canImport).opacity(cookies.canImport ? 1 : 0.5)
            if !cookies.canImport {
                AppInlineNote(appString("miniAppCookiesUnsupported", "Cookies can be imported on macOS and Windows only."))
            } else if cookies.states.isEmpty {
                AppInlineNote(appString("miniAppCookiesEmpty", "No site imported yet."))
            } else {
                ForEach(cookies.states, id: \.cookieImport.site) { CookieImportRow(state: $0, cookies: cookies, dateFormat: dateFormat) }
            }
        }
        .task { await cookies.refresh() }
        .appDialog(isPresented: $importing) { CookieImportDialog(cookies: cookies) { importing = false } }
    }
}

/// One imported site: its name and whether it is still valid, where it came from, and "import again" / "forget".
private struct CookieImportRow: View {
    @Environment(\.appTheme) private var theme
    @Environment(\.toasts) private var toasts
    let state: CookieImportState
    let cookies: CookieImportModel
    let dateFormat: String
    @State private var busy = false

    var body: some View {
        let item = state.cookieImport
        HStack(spacing: theme.spacing.s12) {
            VStack(alignment: .leading, spacing: theme.spacing.s2) {
                HStack(spacing: theme.spacing.s8) {
                    Text(item.site).font(theme.typography.bodyStrong).foregroundStyle(theme.colors.tx).lineLimit(1)
                    TintedPill(state.expired ? appString("miniAppCookiesExpired", "Expired") : appString("miniAppCookiesActive", "Valid"),
                               tint: state.expired ? theme.colors.amber : theme.colors.green)
                        .help(state.expired ? appString("miniAppCookiesExpiredHint", "Its sign-in cookies are gone from the mini apps. Import them again from the browser.") : "")
                }
                Text(appFormat("miniAppCookiesFrom", "%1$@ · %2$@ · %3$@", item.source.browser.displayName, item.source.profileName,
                               formatWhen(item.importedAt, format: dateFormat)))
                    .font(theme.typography.meta).foregroundStyle(theme.colors.tx3).lineLimit(1)
            }
            Spacer(minLength: 0)
            if busy { ProgressView().controlSize(.small) }
            else if state.expired {
                AppButton(appString("miniAppCookiesReimport", "Import again"), systemImage: "arrow.clockwise", kind: .primary) { Task { await reimport() } }
            } else {
                AppIconButton("arrow.clockwise", help: appString("miniAppCookiesReimport", "Import again")) { Task { await reimport() } }
            }
            AppIconButton("xmark", help: appString("miniAppCookiesForget", "Forget this site")) { Task { _ = await cookies.forget(site: item.site) } }
                .disabled(busy)
        }
    }

    private func reimport() async {
        busy = true
        let result = await cookies.reimport(state)
        busy = false
        CookieImportFeedback.report(result, source: state.cookieImport.source, toasts: toasts)
    }
}
