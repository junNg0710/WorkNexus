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
                else if !model.sources.isEmpty {
                    CookieBrowserPicker(model: model)
                    if let source = model.source {
                        switch model.sites {
                        case .idle: EmptyView()
                        case .loading:
                            if source.browser.isChromium {
                                AppInlineNote(appFormat("miniAppCookiesKeychainHint", "macOS will ask to let WorkNexus read %1$@'s cookie key: choose Allow.",
                                                        source.browser.displayName))
                            }
                            AppInlineSpinner()
                        case .failed(let failure): CookieReadError(source: source, failure: failure) { Task { await model.retry() } }
                        case .loaded(let sites):
                            CookieSitePicker(model: model, sites: sites)
                            if model.passwordsSupported && !sites.isEmpty { CookiePasswordsOption(model: model) }
                        }
                    } else {
                        AppInlineNote(appString("miniAppCookiesPickBrowser", "Choose the browser you are signed in with. Nothing is read until you do."))
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
        CookieImportFeedback.report(done.result, passwords: done.passwords, source: done.source, toasts: toasts)
        if case .success = done.result { onClose() }
    }
}

/// "Browser": one button per browser found (Chrome, Edge, Brave, Arc, Firefox, Safari), then a profile dropdown when the
/// chosen browser has several.
private struct CookieBrowserPicker: View {
    @Environment(\.appTheme) private var theme
    let model: CookieImportDialogModel

    var body: some View {
        VStack(alignment: .leading, spacing: theme.spacing.s8) {
            Text(appString("miniAppCookiesBrowserLabel", "Browser")).font(theme.typography.metaStrong).foregroundStyle(theme.colors.tx2)
            HStack(spacing: theme.spacing.s6) {
                ForEach(model.browsers, id: \.self) { browser in
                    BrowserChip(browser: browser, selected: model.source?.browser == browser) { Task { await model.chooseBrowser(browser) } }
                }
            }
            if let source = model.source, model.profiles(of: source.browser).count > 1 {
                Text(appString("miniAppCookiesProfileLabel", "Profile")).font(theme.typography.metaStrong).foregroundStyle(theme.colors.tx2)
                    .padding(.top, theme.spacing.s4)
                AppDropdown(value: source, values: model.profiles(of: source.browser), labelOf: { $0.profileName }) { next in
                    Task { await model.choose(next) }
                }
            }
        }
    }
}

private struct BrowserChip: View {
    @Environment(\.appTheme) private var theme
    let browser: CookieBrowser; let selected: Bool; let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(browser.displayName).font(theme.typography.label)
                .padding(.horizontal, theme.spacing.s12).frame(height: theme.sizes.control32)
                .foregroundStyle(selected ? theme.colors.accentTx : theme.colors.tx)
                .background(selected ? theme.colors.accent : theme.colors.panel2, in: Capsule())
                .overlay(Capsule().stroke(selected ? Color.clear : theme.colors.line, lineWidth: theme.borders.hairline))
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
    }
}

/// "Also import the saved passwords for these sites": off to begin with, and only there for a browser whose passwords can be
/// read (Chrome, Edge, Brave, Arc). The passwords of the picked sites alone go into the keychain, as the mini apps' own.
private struct CookiePasswordsOption: View {
    @Environment(\.appTheme) private var theme
    let model: CookieImportDialogModel

    var body: some View {
        let on = model.includePasswords
        HStack(alignment: .top, spacing: theme.spacing.s10) {
            Image(systemName: on ? "checkmark.square.fill" : "square").font(.system(size: theme.sizes.icon16))
                .foregroundStyle(on ? theme.colors.accent : theme.colors.tx3)
            VStack(alignment: .leading, spacing: theme.spacing.s2) {
                Text(appString("miniAppPasswordsImportOption", "Also import the saved passwords for these sites"))
                    .font(theme.typography.body).foregroundStyle(theme.colors.tx)
                Text(appString("miniAppPasswordsImportHint", "Only the picked sites' passwords are copied, into your Mac's keychain, to fill sign-in forms in mini apps."))
                    .font(theme.typography.meta).foregroundStyle(theme.colors.tx3).fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, theme.spacing.s4)
        .contentShape(Rectangle()).onTapGesture { model.includePasswords.toggle() }
        .accessibilityElement(children: .combine).accessibilityAddTraits(on ? [.isButton, .isSelected] : .isButton)
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
