import CoreDomain
import Foundation

/// New (no Dart counterpart): the sign-ins the user saved for the sites opened in mini apps, kept in the system keychain.
/// Passwords never leave it except through `logins(origin:)`, asked for one site at the moment its form is filled.
public protocol WebLoginRepository: Sendable {
    /// The sign-ins saved for exactly `origin`, passwords included.
    func logins(origin: String) async -> Outcome<[WebLogin]>
    /// Every saved sign-in without its password (settings, choosers), by site then user.
    func summaries() async -> Outcome<[WebLoginSummary]>
    /// Keeps `login`, replacing the one with the same origin and username.
    func save(_ login: WebLogin) async -> Outcome<Void>
    func delete(origin: String, username: String) async -> Outcome<Void>
    func deleteAll() async -> Outcome<Void>
    /// The origins the user never wants to be asked to save a password for.
    func neverSaveOrigins() async -> Outcome<[String]>
    /// Puts `origin` on (or takes it off) the never-save list.
    func setNeverSave(origin: String, _ never: Bool) async -> Outcome<Void>
}

/// The passwords a browser on this device saved (Chromium browsers only), read for the import the user asked for.
public protocol BrowserLoginRepository: Sendable {
    /// Whether `browser`'s saved passwords can be read at all.
    func supports(_ browser: CookieBrowser) -> Bool
    /// Every sign-in `source` keeps. `.auth` means the system refused, as for cookies (`CookieReadRefusal`).
    func read(_ source: CookieSource) async -> Outcome<[WebLogin]>
}

/// The session cookies (the ones without an expiry, which the web view forgets when the app quits) kept between runs:
/// one keychain item.
public protocol SessionCookieStore: Sendable {
    func load() async -> Outcome<[BrowserCookie]>
    /// Replaces what is kept with `cookies`; none removes the item.
    func save(_ cookies: [BrowserCookie]) async -> Outcome<Void>
}

/// The live cookies of the web profile the mini apps share, and when they change.
public protocol WebViewCookieSource: Sendable {
    /// Every cookie the web view holds now.
    func all() async -> Outcome<[BrowserCookie]>
    /// One event per change of the web view's cookies (ends when the consumer stops listening).
    func changes() -> AsyncStream<Void>
}
