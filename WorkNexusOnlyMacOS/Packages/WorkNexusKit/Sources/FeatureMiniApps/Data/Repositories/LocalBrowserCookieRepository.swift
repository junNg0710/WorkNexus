import CoreDomain
import Foundation

/// Ported from: lib/features/mini_apps/data/repositories/local_browser_cookie_repository.dart
/// The browsers' cookies on this device: Chromium browsers, Firefox and Safari on macOS.
public final class LocalBrowserCookieRepository: BrowserCookieRepository, @unchecked Sendable {
    private let chromium: ChromiumCookieReader
    private let firefox: FirefoxCookieReader
    private let safari: SafariCookieReader

    public convenience init(home: String? = nil) {
        self.init(chromium: ChromiumCookieReader(home: home), firefox: home.map { FirefoxCookieReader(root: "\($0)/Library/Application Support/Firefox") } ?? FirefoxCookieReader(),
                  safari: SafariCookieReader(home: home))
    }

    init(chromium: ChromiumCookieReader, firefox: FirefoxCookieReader, safari: SafariCookieReader) {
        self.chromium = chromium; self.firefox = firefox; self.safari = safari
    }

    public func sources() async -> Outcome<[CookieSource]> {
        var found: [CookieSource] = []
        for browser in CookieBrowser.allCases where browser.isChromium {
            found += chromium.profiles(browser).map { CookieSource(browser: browser, profileId: $0.path, profileName: $0.name) }
        }
        found += firefox.profiles().map { CookieSource(browser: .firefox, profileId: $0.path, profileName: $0.name) }
        if safari.installed { found.append(CookieSource(browser: .safari, profileId: "safari", profileName: "Safari")) }
        return .success(found)
    }

    public func read(_ source: CookieSource) async -> Outcome<[BrowserCookie]> {
        do {
            switch source.browser {
            case .firefox: return .success(try await firefox.read(profilePath: source.profileId))
            case .safari: return .success(try await safari.read())
            default: return .success(try await chromium.read(source.browser, profilePath: source.profileId))
            }
        } catch is KeychainDeniedError {
            return .failure(.auth("The keychain refused the password"))
        } catch let e as NSError where Self.isRefused(e) {
            return .failure(.auth("The system refused access"))
        } catch {
            return .failure(.storage("Could not read the cookies"))
        }
    }

    /// A permission the system refused (EPERM, EACCES; Cocoa's no-permission codes).
    static func isRefused(_ e: NSError) -> Bool {
        if e.domain == NSPOSIXErrorDomain { return e.code == 1 || e.code == 13 }
        if e.domain == NSCocoaErrorDomain, e.code == NSFileReadNoPermissionError || e.code == NSFileWriteNoPermissionError { return true }
        if let underlying = e.userInfo[NSUnderlyingErrorKey] as? NSError { return isRefused(underlying) }
        return false
    }
}
