/// New (no Dart counterpart): a sign-in the user chose to keep for a site opened in a mini app.
/// `origin` is the site it belongs to and the only place it is ever filled in: scheme, host and port (see `webOrigin(of:)`).
public struct WebLogin: Sendable, Equatable, Hashable {
    public var origin: String
    public var username: String
    public var password: String

    public init(origin: String, username: String, password: String) {
        self.origin = origin; self.username = username; self.password = password
    }

    /// The same sign-in without its password: what lists and choosers show.
    public var summary: WebLoginSummary { WebLoginSummary(origin: origin, username: username) }
}

/// A sign-in never prints its password: not in a log line, a failed assertion, a `dump` or a debugger summary.
extension WebLogin: CustomStringConvertible, CustomDebugStringConvertible, CustomReflectable {
    public var description: String { "WebLogin(origin: \(origin), username: \(username), password: <hidden>)" }
    public var debugDescription: String { description }
    public var customMirror: Mirror { Mirror(self, children: ["origin": origin, "username": username, "password": "<hidden>"]) }
}

/// A saved sign-in as it is listed: which site and which user, never the password.
public struct WebLoginSummary: Sendable, Equatable, Hashable, Identifiable {
    public var origin: String
    public var username: String

    public init(origin: String, username: String) { self.origin = origin; self.username = username }

    public var id: String { origin + "\u{0}" + username }
    /// The site's name without the scheme, as the user knows it (`intranet.corp.com`, `nas.local:5001`).
    public var host: String { webOriginHost(origin) }
}

/// What to ask the user once a page's sign-in form was sent.
public enum WebLoginOffer: Sendable, Equatable {
    /// Nothing: already saved as it is, or the user said never for this site.
    case none
    /// "Save password?": the site has no sign-in for this user yet.
    case save
    /// "Update password?": this user is saved with another password.
    case update
}
