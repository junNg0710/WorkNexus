import Foundation

/// Ported from: lib/features/mini_apps/domain/entities/browser_cookie.dart
/// A cookie as a browser keeps it. `domain` keeps its leading dot when the cookie goes to subdomains too, as browsers write it.
public struct BrowserCookie: Sendable, Equatable, Hashable {
    public var name: String
    public var value: String
    public var domain: String
    public var path: String
    /// When it expires; nil for one that lasts the session.
    public var expires: Date?
    public var secure: Bool
    public var httpOnly: Bool
    public var sameSite: CookieSameSite

    public init(name: String, value: String, domain: String, path: String = "/", expires: Date? = nil, secure: Bool = false,
                httpOnly: Bool = false, sameSite: CookieSameSite = .unspecified) {
        self.name = name; self.value = value; self.domain = domain; self.path = path; self.expires = expires
        self.secure = secure; self.httpOnly = httpOnly; self.sameSite = sameSite
    }

    /// The host it is sent to, without the leading dot.
    public var host: String { domain.hasPrefix(".") ? String(domain.dropFirst()) : domain }
    /// Whether it goes to subdomains of `host` too.
    public var includesSubdomains: Bool { domain.hasPrefix(".") }
    public var key: CookieKey { CookieKey(host: host, path: path, name: name) }
    public func isExpired(at now: Date) -> Bool { expires.map { $0 < now } ?? false }
}
