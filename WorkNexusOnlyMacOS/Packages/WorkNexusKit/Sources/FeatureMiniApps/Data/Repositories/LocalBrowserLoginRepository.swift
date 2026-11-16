import CoreDomain
import Foundation

/// New (no Dart counterpart): the passwords saved by the Chromium browsers on this device. Firefox (its own NSS store) and
/// Safari (the system's Passwords, closed to other apps) are not supported. A refused read is reported like a refused
/// cookie read (`CookieReadRefusal`: the keychain, or Privacy's Full Disk Access).
public final class LocalBrowserLoginRepository: BrowserLoginRepository, @unchecked Sendable {
    private let reader: ChromiumLoginReader

    init(reader: ChromiumLoginReader) { self.reader = reader }

    public func supports(_ browser: CookieBrowser) -> Bool { browser.isChromium }

    public func read(_ source: CookieSource) async -> Outcome<[WebLogin]> {
        guard supports(source.browser) else { return .success([]) }
        do {
            return .success(try await reader.read(source.browser, profilePath: source.profileId))
        } catch is KeychainDeniedError {
            return .failure(.auth(CookieReadRefusal.keychain))
        } catch let e as NSError where LocalBrowserCookieRepository.isRefused(e) {
            return .failure(.auth(CookieReadRefusal.system))
        } catch {
            return .failure(.storage("Could not read the saved passwords"))
        }
    }
}
