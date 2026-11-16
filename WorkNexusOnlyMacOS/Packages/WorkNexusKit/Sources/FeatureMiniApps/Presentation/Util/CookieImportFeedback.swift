import AppKit
import CoreDomain
import CoreUI
import Foundation

/// Ported from: lib/features/mini_apps/presentation/widgets/cookie_import_feedback.dart
/// How an import is reported: why a profile's cookies could not be read or imported in the user's words, whether the way
/// past it is the Privacy settings (Safari's Full Disk Access), and the toast for a finished import.
enum CookieImportFeedback {
    /// Why `source`'s cookies could not be read or imported.
    static func failureMessage(_ source: CookieSource, _ failure: Failure) -> String {
        switch failure {
        case .auth where source.browser == .safari || failure.message == CookieReadRefusal.system:
            appFormat("miniAppCookiesFilesAccess", "Reading %1$@'s cookies needs Full Disk Access: turn it on for WorkNexus Mac, quit and reopen the app, then try again.",
                      source.browser.displayName)
        case .auth:
            appFormat("miniAppCookiesKeychainDenied", "macOS did not give out %1$@'s cookie key. Try again and choose Allow.", source.browser.displayName)
        case .notFound: appString("miniAppCookiesNone", "The browser has no cookies for this site any more. Sign in there first.")
        default: appString("miniAppCookiesFailed", "Could not import the cookies.")
        }
    }

    /// Whether the way past `failure` is the Privacy settings.
    static func needsFullDiskAccess(_ source: CookieSource, _ failure: Failure) -> Bool {
        if case .auth = failure { return source.browser == .safari || failure.message == CookieReadRefusal.system }
        return false
    }

    /// The Full Disk Access list of the Privacy settings, where WorkNexus is switched on.
    static let fullDiskAccessUrl = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_AllFiles")!

    @MainActor static func openFullDiskAccessSettings() { NSWorkspace.shared.open(fullDiskAccessUrl) }

    /// "Imported 3 cookies."
    static func importedMessage(_ count: Int) -> String {
        appFormat("miniAppCookiesImported", count == 1 ? "Imported 1 cookie." : "Imported %1$@ cookies.", "\(count)")
    }

    /// "Imported 3 cookies and 2 passwords."
    static func importedMessage(cookies: Int, passwords: Int) -> String {
        let cookieCount = appFormat("miniAppCookiesSiteCount", cookies == 1 ? "1 cookie" : "%1$@ cookies", "\(cookies)")
        let passwordCount = passwords == 1 ? appString("miniAppPasswordsCountOne", "1 password")
                                           : appFormat("miniAppPasswordsCountOther", "%1$@ passwords", "\(passwords)")
        return appFormat("miniAppCookiesImportedWithPasswords", "Imported %1$@ and %2$@.", cookieCount, passwordCount)
    }

    /// The toast for an import that was asked for the passwords too: both counts, or the cookies' and why the passwords stayed.
    @MainActor static func report(_ result: Outcome<Int>, passwords: Outcome<Int>?, source: CookieSource, toasts: AppToastController?) {
        guard case .success(let count) = result, let passwords else { report(result, source: source, toasts: toasts); return }
        switch passwords {
        case .success(let saved): toasts?.show(importedMessage(cookies: count, passwords: saved))
        case .failure:
            toasts?.show(importedMessage(count) + " " + appString("miniAppPasswordsImportFailed", "The saved passwords could not be read."), kind: .error)
        }
    }

    /// The toast for an import's end: how many cookies went in, or why none did.
    @MainActor static func report(_ result: Outcome<Int>, source: CookieSource, toasts: AppToastController?) {
        switch result {
        case .success(let count): toasts?.show(importedMessage(count))
        case .failure(let failure): toasts?.show(failureMessage(source, failure), kind: .error)
        }
    }

    /// "Chrome", or "Chrome · Work" for a profile with a name of its own.
    static func label(_ source: CookieSource) -> String {
        let browser = source.browser.displayName
        return source.profileName == browser ? browser : "\(browser) · \(source.profileName)"
    }
}
