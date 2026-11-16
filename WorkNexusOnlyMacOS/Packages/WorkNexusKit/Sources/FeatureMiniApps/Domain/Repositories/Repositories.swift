import CoreDomain
import Foundation

/// Ported from: lib/features/mini_apps/domain/repositories/mini_app_repository.dart
/// The mini apps the user added, kept on this device.
public protocol MiniAppRepository: Sendable {
    /// Every mini app in rail order, live.
    func watchAll() -> AsyncStream<[MiniApp]>
    /// Keeps `app`, replacing the one with its id.
    func save(_ app: MiniApp) async -> Outcome<Void>
    /// Remembers `url` as the page app `id` was last on. Touches nothing else, so it cannot undo an edit made meanwhile.
    func saveLastUrl(id: String, url: String) async -> Outcome<Void>
    /// Remembers the pages of the tabs app `id` has open and which one is in front (`MiniApp.openTabs`). Touches nothing else.
    func saveTabs(id: String, urls: [String], selected: Int) async -> Outcome<Void>
    /// Puts the apps in the order of `ids` on the rail, first to last. Touches nothing but their positions.
    func saveOrder(_ ids: [String]) async -> Outcome<Void>
    /// Removes the app, its remembered permissions and its icon file.
    func delete(id: String) async -> Outcome<Void>
    /// Downloads the icon of the site at `pageUrl` for app `id` and keeps it on this device. The path, or nil when the site offers none.
    func fetchSiteIcon(id: String, pageUrl: String) async -> Outcome<String?>
    /// Copies the image at `sourcePath` in as app `id`'s icon; the kept file's path.
    func importIcon(id: String, sourcePath: String) async -> Outcome<String>
}

public extension MiniAppRepository {
    /// Where tabs are not kept, they are not remembered.
    func saveTabs(id: String, urls: [String], selected: Int) async -> Outcome<Void> { .success(()) }
}

/// Ported from: lib/features/mini_apps/domain/repositories/mini_app_permission_repository.dart
/// The permissions the user gave (or refused) each mini app, kept on this device.
public protocol MiniAppPermissionRepository: Sendable {
    func watch(miniAppId: String) -> AsyncStream<[MiniAppPermissionGrant]>
    /// The remembered answer for `kind`; nil when never asked (or cleared).
    func decision(miniAppId: String, kind: MiniAppPermissionKind) async -> Outcome<MiniAppPermissionDecision?>
    /// Remembers `grant`, replacing the earlier answer for its kind.
    func save(_ grant: MiniAppPermissionGrant) async -> Outcome<Void>
    /// Forgets the answer for `kind`, so the next request asks again.
    func clear(miniAppId: String, kind: MiniAppPermissionKind) async -> Outcome<Void>
}

/// Ported from: lib/features/mini_apps/domain/repositories/trusted_certificate_repository.dart
/// The sites whose invalid certificate the user chose to accept, one entry per site. Each change answers with the list as it now is.
public protocol TrustedCertificateRepository: Sendable {
    func all() async -> Outcome<[TrustedCertificate]>
    /// Trusts `origin`, which was refused with `error`; a site already trusted keeps one entry, with the latest error.
    func trust(origin: String, error: String) async -> Outcome<[TrustedCertificate]>
    func forget(_ certificate: TrustedCertificate) async -> Outcome<[TrustedCertificate]>
    func forgetAll() async -> Outcome<[TrustedCertificate]>
}

/// Ported from: lib/features/mini_apps/domain/repositories/browser_cookie_repository.dart
public protocol BrowserCookieRepository: Sendable {
    /// The browser profiles found here whose cookies can be read.
    func sources() async -> Outcome<[CookieSource]>
    /// Every cookie `source` keeps. `.auth` means the system refused access (Safari's needs Full Disk Access; Chromium's key asks the keychain).
    func read(_ source: CookieSource) async -> Outcome<[BrowserCookie]>
}

/// Ported from: lib/features/mini_apps/domain/repositories/cookie_import_repository.dart
/// The sites whose cookies were imported, one entry per site. Each change answers with the list as it now is.
public protocol CookieImportRepository: Sendable {
    func all() async -> Outcome<[CookieImport]>
    /// Keeps `imports`, replacing the entries of the same sites.
    func save(_ imports: [CookieImport]) async -> Outcome<[CookieImport]>
    func forget(site: String) async -> Outcome<[CookieImport]>
}

/// Ported from: lib/features/mini_apps/domain/repositories/web_view_cookie_repository.dart
/// The cookies of the web profile the mini apps share.
public protocol WebViewCookieRepository: Sendable {
    var canWrite: Bool { get }
    /// Sets `cookies`, replacing any with the same name, host and path (HttpOnly ones included).
    func write(_ cookies: [BrowserCookie]) async -> Outcome<Void>
    /// Which of `keys` the web view still has.
    func present(_ keys: [CookieKey]) async -> Outcome<Set<CookieKey>>
}

/// Ported from: lib/features/mini_apps/domain/repositories/mini_app_browsing_data_repository.dart
/// What the mini apps' pages left in the shared web profile on this device: cache, cookies (sign-ins) and site storage.
public protocol MiniAppBrowsingDataRepository: Sendable {
    var canClear: Bool { get }
    /// Clears the cache only: sign-ins stay, pages load afresh.
    func clearCache() async -> Outcome<Void>
    /// Clears what the site at `url` keeps: its cookies, storage and cached files. Signs the user out of it.
    func clearSite(url: String) async -> Outcome<Void>
    /// Clears every site's cookies, storage and the cache. Signs the user out of every mini app.
    func clearAll(urls: [String]) async -> Outcome<Void>
}

/// Ported from: lib/core/domain/repositories/pinned_certificate_repository.dart
/// Certificates the user accepted for servers the system does not trust, such as a ZenTao chat server's self-signed one:
/// each by its SHA-256 fingerprint, upper-case hex without separators. Owned by the chat; the composition root adapts it
/// here so a mini app's pages that call the same server get through.
public protocol PinnedCertificateSource: Sendable {
    func fingerprints() async -> Outcome<Set<String>>
}
