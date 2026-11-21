import CoreDomain
import CorePersistence
import CoreUI
import Foundation
import SwiftUI

/// Public entry point of FeatureMiniApps. The composition root:
/// 1. passes `MiniAppsFeature.migrationRegistrar` (`miniapps_v1` + `miniapps_v2`) to `AppDatabase.open(registrars:)`,
/// 2. builds one `MiniAppsFeature.make(...)` and calls `model.start()`,
/// 3. installs it with `.miniApps(feature)` on the shell, so `MiniAppHostView(miniApp:)` can find it,
/// 4. wires `model.requestShow` / `model.bringToFront` to the navigation and the window, and calls `model.show(id)` when the
///    rail selection (`AppNavState.miniAppId`) changes,
/// 5. calls `startSessionCookies()` right after building it (before any page exists) and `stopSessionCookies()` as the app
///    quits, so the sites' session cookies last from one run to the next.
public final class MiniAppsFeature: @unchecked Sendable {
    public static let name = "FeatureMiniApps"
    public static var migrationRegistrar: MigrationRegistrar { MiniAppsMigrations.registrar }

    /// The rail's data source and keeper of the running pages.
    @MainActor public let model: MiniAppsModel
    public let apps: MiniAppRepository
    public let permissions: MiniAppPermissionRepository
    public let trustedCertificates: TrustedCertificateRepository
    public let cookieImports: CookieImportRepository
    public let browserCookies: BrowserCookieRepository
    public let webViewCookies: WebViewCookieRepository
    public let browsingData: MiniAppBrowsingDataRepository
    /// The Mac apps on the rail (new, no Dart counterpart): list, launch, running state, installed apps.
    @MainActor public let nativeApps: NativeAppsModel
    public let addMiniApp: AddMiniApp
    public let updateMiniApp: UpdateMiniApp
    public let importBrowserCookies: ImportBrowserCookies
    public let checkCookieImports: CheckCookieImports
    /// The imported sites and the commands behind the import dialog, one for the toolbar buttons and settings alike.
    @MainActor public let cookies: CookieImportModel
    @MainActor let trustedModel: TrustedCertificatesModel
    @MainActor let browsingDataModel: MiniAppBrowsingDataModel
    /// The passwords saved for the sites the mini apps open (new, no Dart counterpart): the keychain's.
    public let webLogins: WebLoginRepository
    public let importBrowserLogins: ImportBrowserLogins
    @MainActor let webLoginsModel: WebLoginsSettingsModel
    /// Keeps the sites' session cookies from one run to the next (new, no Dart counterpart).
    @MainActor let sessionCookies: SessionCookieKeeper

    @MainActor init(model: MiniAppsModel, nativeApps: NativeAppsModel, apps: MiniAppRepository, permissions: MiniAppPermissionRepository,
                    trusted: TrustedCertificateRepository, cookieImports: CookieImportRepository, browserCookies: BrowserCookieRepository,
                    webViewCookies: WebViewCookieRepository, browsingData: MiniAppBrowsingDataRepository, add: AddMiniApp, update: UpdateMiniApp,
                    webLogins: WebLoginRepository, browserLogins: BrowserLoginRepository, sessionCookies: SessionCookieKeeper) {
        self.model = model; self.nativeApps = nativeApps; self.apps = apps; self.permissions = permissions; trustedCertificates = trusted
        self.cookieImports = cookieImports; self.browserCookies = browserCookies; self.webViewCookies = webViewCookies
        self.browsingData = browsingData; addMiniApp = add; updateMiniApp = update
        self.webLogins = webLogins; self.sessionCookies = sessionCookies
        importBrowserCookies = ImportBrowserCookies(browserCookies, webViewCookies, cookieImports)
        checkCookieImports = CheckCookieImports(cookieImports, webViewCookies)
        importBrowserLogins = ImportBrowserLogins(browserLogins, webLogins)
        cookies = CookieImportModel(browsers: browserCookies, webView: webViewCookies, imports: cookieImports, importCookies: importBrowserCookies,
                                    check: checkCookieImports, importLogins: importBrowserLogins, model: model)
        trustedModel = TrustedCertificatesModel(repository: trusted)
        browsingDataModel = MiniAppBrowsingDataModel(data: browsingData, model: model)
        webLoginsModel = WebLoginsSettingsModel(services: model.services.webLogins)
        model.sessionCookies = sessionCookies
    }

    /// A fresh model behind the "Import cookies" dialog; the views use the shared `cookies`.
    @MainActor
    public func makeCookieImportModel() -> CookieImportModel {
        CookieImportModel(browsers: browserCookies, webView: webViewCookies, imports: cookieImports, importCookies: importBrowserCookies,
                          check: checkCookieImports, importLogins: importBrowserLogins, model: model)
    }

    /// At launch, before any mini app's page exists: puts the session cookies kept from the last run back into the web view
    /// (a page waits for it) and then keeps them up to date. Not called by tests, which must not touch the keychain.
    @MainActor
    public func startSessionCookies() { sessionCookies.start() }

    /// As the app quits: a last copy of the session cookies. Returns once it is kept.
    @MainActor
    public func stopSessionCookies() async { await sessionCookies.stop() }

    /// The production wiring.
    /// - Parameters:
    ///   - accounts: the saved accounts (the ZenTao ones sign a mini app's login form in).
    ///   - credentials: where the accounts' passwords are (`Account.credentialsRef`).
    ///   - notifier: OS notifications for a page's `Notification` (`CoreUI.DesktopNotifier`).
    ///   - pinnedCertificates: the certificates the chat pinned, so a page calling the same server gets through.
    ///   - launcher, installedApps, appBundleReader: how Mac apps are opened, found and read; the system's unless a test passes doubles.
    ///   - supportDirectory: where the icons, trusted certificates, cookie imports and the never-save list are kept.
    ///   - secrets: where the saved passwords and the kept session cookies go: the keychain, or memory only (tests, demo).
    @MainActor
    public static func make(database: AppDatabase, accounts: @escaping @Sendable () async -> [Account], credentials: CredentialStore,
                            notifier: DesktopNotifying, pinnedCertificates: PinnedCertificateSource? = nil,
                            settings: MiniAppsSettings = MiniAppsSettings(), launcher: AppLauncher? = nil,
                            installedApps: InstalledAppsSource? = nil, appBundleReader: AppBundleReader = PlistAppBundleReader(),
                            supportDirectory: URL = PlatformPaths.applicationSupport(), router: LinkRouter? = nil,
                            secrets: MiniAppsSecretStorage = .keychain) -> MiniAppsFeature {
        let apps = GRDBMiniAppRepository(database: database, icons: MiniAppIconStorage(folder: supportDirectory.appendingPathComponent("mini_app_icons", isDirectory: true)))
        let permissions = GRDBMiniAppPermissionRepository(database: database)
        let trusted = FileTrustedCertificateRepository(file: supportDirectory.appendingPathComponent("trusted_certificates.json"))
        let imports = FileCookieImportRepository(file: supportDirectory.appendingPathComponent("cookie_imports.json"))
        let refresh = RefreshMiniAppIcon(apps)
        let add = AddMiniApp(apps, refresh), update = UpdateMiniApp(apps, refresh)
        let webLogins = KeychainWebLoginRepository(items: secrets.logins, neverSaveFile: supportDirectory.appendingPathComponent("password_never_save.json"))
        // One Chromium reader for cookies and passwords: the browser's key is asked of the keychain once.
        let chromium = ChromiumCookieReader()
        let webViewCookies = WKWebViewCookieRepository()
        let kept = KeychainSessionCookieStore(items: secrets.sessionCookies)
        let keptSites = SessionCookieSites(apps, imports)
        let keeper = SessionCookieKeeper(restore: RestoreSessionCookies(kept, webViewCookies, keptSites),
                                         snapshot: SnapshotSessionCookies(webViewCookies, kept, keptSites), forget: ForgetSessionCookies(kept),
                                         changes: { webViewCookies.changes() })
        let services = MiniAppsServices(
            apps: apps, permissions: permissions, trusted: trusted, addMiniApp: add, updateMiniApp: update, moveMiniApp: MoveMiniApp(apps),
            resolvePermission: ResolveMiniAppPermission(permissions), isPinnedCertificate: IsPinnedCertificate(pinnedCertificates ?? NoPinnedCertificates()),
            findSavedWebLogin: FindSavedWebLogin(accounts: accounts, secret: { await credentials.read($0) }),
            webLogins: WebLoginServices(webLogins), notifier: notifier, settings: settings)
        let model = MiniAppsModel(services: services, router: router ?? .shared)
        let nativeRepo = GRDBNativeAppRepository(
            database: database, icons: MiniAppIconStorage(folder: supportDirectory.appendingPathComponent("native_app_icons", isDirectory: true)))
        let nativeApps = NativeAppsModel(repository: nativeRepo, add: AddNativeApp(nativeRepo, appBundleReader), remove: RemoveNativeApp(nativeRepo),
                                         edit: EditNativeApp(nativeRepo),
                                         move: MoveNativeApp(nativeRepo), installed: installedApps ?? InstalledAppsScanner(reader: appBundleReader),
                                         launcher: launcher ?? WorkspaceAppLauncher(), dock: DockBadgeReader(),
                                         offerMemory: UserDefaultsBadgeOfferMemory())
        return MiniAppsFeature(model: model, nativeApps: nativeApps, apps: apps, permissions: permissions, trusted: trusted, cookieImports: imports,
                               browserCookies: LocalBrowserCookieRepository(chromium: chromium, firefox: FirefoxCookieReader(), safari: SafariCookieReader()),
                               webViewCookies: webViewCookies, browsingData: WKMiniAppBrowsingDataRepository(), add: add, update: update,
                               webLogins: webLogins, browserLogins: LocalBrowserLoginRepository(reader: ChromiumLoginReader(keys: chromium)),
                               sessionCookies: keeper)
    }
}

private struct NoPinnedCertificates: PinnedCertificateSource {
    func fingerprints() async -> Outcome<Set<String>> { .success([]) }
}

private struct MiniAppsKey: EnvironmentKey { static let defaultValue: MiniAppsFeature? = nil }
public extension EnvironmentValues {
    /// The mini apps feature, for `MiniAppHostView` and `MiniAppsHostStack`.
    var miniApps: MiniAppsFeature? {
        get { self[MiniAppsKey.self] }
        set { self[MiniAppsKey.self] = newValue }
    }
}

public extension View {
    func miniApps(_ feature: MiniAppsFeature?) -> some View { environment(\.miniApps, feature) }
}
