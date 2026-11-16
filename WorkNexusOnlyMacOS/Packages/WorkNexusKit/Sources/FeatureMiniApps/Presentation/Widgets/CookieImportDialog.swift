import CoreDomain
import CoreUI
import SwiftUI

/// Ported from: lib/features/mini_apps/presentation/widgets/cookie_import_dialog.dart
/// Imports cookies from a browser: pick the browser profile, then the sites (the mini apps' ones are picked to begin with).
/// Only those sites' cookies go into the mini apps. Opened from one mini app, it is about that app's `site`: picked alone and
/// listed first, from the `source` it was last imported from, if any. Present it with `.appDialog`.
public struct CookieImportDialog: View {
    @Environment(\.appTheme) private var theme
    @Environment(\.toasts) private var toasts
    @State private var model: CookieImportDialogModel
    private let cookies: CookieImportModel
    private let onClose: () -> Void

    public init(cookies: CookieImportModel, site: String? = nil, source: CookieSource? = nil, onClose: @escaping () -> Void) {
        self.cookies = cookies; self.onClose = onClose
        _model = State(initialValue: CookieImportDialogModel(cookies: cookies, site: site, source: source))
    }

    public var body: some View {
        AppDialogFrame(title: appString("miniAppCookiesDialogTitle", "Import cookies"), leadingIcon: "person.badge.key", onClose: onClose) {
            VStack(alignment: .leading, spacing: theme.spacing.s12) {
                if model.loadingSources { AppInlineSpinner() }
                else if let source = model.source {
                    CookieSourcePicker(sources: model.sources, value: source) { next in Task { await model.choose(next) } }
                    switch model.sites {
                    case .loading:
                        if source.browser.isChromium {
                            AppInlineNote(appFormat("miniAppCookiesKeychainHint", "macOS will ask to let WorkNexus read %1$@'s cookie key: choose Allow.",
                                                    source.browser.displayName))
                        }
                        AppInlineSpinner()
                    case .failed(let failure): CookieReadError(source: source, failure: failure) { Task { await model.retry() } }
                    case .loaded(let sites): CookieSitePicker(model: model, sites: sites)
                    }
                } else {
                    AppInlineNote(appString("miniAppCookiesNoBrowser", "No browser with cookies was found on this device."))
                }
            }
            .padding(.horizontal, theme.spacing.s24).padding(.bottom, theme.spacing.s24)
        } actions: {
            Spacer(minLength: 0)
            AppButton(appString("cancel", "Cancel"), kind: .ghost, action: onClose)
            AppButton(importLabel, kind: .primary) { Task { await run() } }
                .disabled(!model.canImport).opacity(model.canImport ? 1 : 0.5)
        }
        .task { await model.load() }
    }

    /// "Import 3 sites".
    private var importLabel: String {
        let count = model.picked.count
        let fallback = count == 0 ? "Import" : (count == 1 ? "Import 1 site" : "Import %1$@ sites")
        return appFormat("miniAppCookiesImportCount", fallback, "\(count)")
    }

    /// Imports, says how it went and closes — unless it failed, so the user can try another profile or site.
    private func run() async {
        guard let done = await model.importPicked() else { return }
        CookieImportFeedback.report(done.result, source: done.source, toasts: toasts)
        if case .success = done.result { onClose() }
    }
}

/// The "Browser" dropdown of the dialog.
private struct CookieSourcePicker: View {
    @Environment(\.appTheme) private var theme
    let sources: [CookieSource]
    let value: CookieSource
    let onChange: (CookieSource) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: theme.spacing.s6) {
            Text(appString("miniAppCookiesBrowserLabel", "Browser")).font(theme.typography.metaStrong).foregroundStyle(theme.colors.tx2)
            AppDropdown(value: value, values: sources, labelOf: CookieImportFeedback.label, onChanged: onChange)
        }
    }
}

/// Why the profile's cookies could not be read, and the way past it.
private struct CookieReadError: View {
    @Environment(\.appTheme) private var theme
    let source: CookieSource
    let failure: Failure
    let onRetry: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: theme.spacing.s8) {
            AppInlineNote(isAuth ? CookieImportFeedback.failureMessage(source, failure)
                                 : appString("miniAppCookiesReadFailed", "Could not read this browser's cookies."), isError: true)
            HStack(spacing: theme.spacing.s8) {
                if CookieImportFeedback.needsFullDiskAccess(source, failure) {
                    AppButton(appString("miniAppCookiesOpenPrivacy", "Open Privacy settings"), systemImage: "lock.shield") {
                        CookieImportFeedback.openFullDiskAccessSettings()
                    }
                }
                AppButton(appString("miniAppCookiesRetry", "Try again"), systemImage: "arrow.clockwise", action: onRetry)
            }
        }
    }

    private var isAuth: Bool { if case .auth = failure { true } else { false } }
}
