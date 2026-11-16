/// Ported from: lib/features/mini_apps/domain/entities/cookie_source.dart
/// One browser profile whose cookies can be read: `profileId` is how the data layer finds it again, `profileName` what the user calls it.
public struct CookieSource: Sendable, Equatable, Hashable {
    public var browser: CookieBrowser
    public var profileId: String
    public var profileName: String
    public init(browser: CookieBrowser, profileId: String, profileName: String) {
        self.browser = browser; self.profileId = profileId; self.profileName = profileName
    }
}
