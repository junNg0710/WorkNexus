import CoreDomain
import CoreUI
import Foundation
import Observation

/// One entry of the rail's mini-app section.
public struct MiniAppRailItem: Identifiable, Equatable, Sendable {
    public var id: String
    public var name: String
    public var iconPath: String?
    /// Its page is running (kept alive), so the rail can offer to close it.
    public var running: Bool
    public var selected: Bool
}

/// Ported from: lib/features/mini_apps/presentation/widgets/mini_apps_host.dart (+ providers/mini_app_providers.dart)
/// The rail's data source and the keeper of the running pages: holds the mini apps used most recently (up to
/// `MiniAppsSettings.liveLimit`), past which the one left longest ago is closed and reopens on the page it was on. Also the
/// bridge to the rest of the app: it brings a mini app forward when its notification is tapped, and takes over a tapped
/// link to one of its sites instead of the browser.
@MainActor @Observable
public final class MiniAppsModel: LinkHandler {
    public private(set) var apps: [MiniApp] = []
    /// Ids kept running, least recently shown first.
    public private(set) var liveIds: [String] = []
    public private(set) var currentId: String?
    /// Whether the mini-app area is the one on screen (a mini app is selected on the rail).
    public private(set) var onScreen = false
    /// Sites with a mini app, for the rest of the app to route links.
    public private(set) var linkTargets: [MiniAppLinkTarget] = []

    /// Asks the shell to show mini app `id` (the composition root maps it to `AppNavController`).
    @ObservationIgnored public var requestShow: ((String) -> Void)?
    /// Brings the app window forward (a tapped notification).
    @ObservationIgnored public var bringToFront: (() -> Void)?
    /// Told when a mini app's page shows a notification the user is not looking at: the app, its title and text.
    @ObservationIgnored public var onNotified: ((MiniApp, String, String) -> Void)?

    let services: MiniAppsServices
    private let router: LinkRouter
    /// Keeps the sites' session cookies between runs; set by the feature.
    @ObservationIgnored var sessionCookies: SessionCookieKeeper?
    @ObservationIgnored private var started = false
    @ObservationIgnored private var tasks: [Task<Void, Never>] = []
    @ObservationIgnored private var seq = 0
    @ObservationIgnored private var pending: MiniAppNavigation?
    @ObservationIgnored private var tabSets: [String: MiniAppTabsModel] = [:]
    @ObservationIgnored private var shownWaiters: [String: [CheckedContinuation<Void, Never>]] = [:]

    init(services: MiniAppsServices, router: LinkRouter) { self.services = services; self.router = router }

    /// Starts watching the database, the notification taps and the link router. Idempotent.
    public func start() {
        guard !started else { return }
        started = true
        router.register(.miniApp, self)
        let repo = services.apps
        tasks.append(Task { [weak self] in
            for await list in repo.watchAll() { self?.apply(list) }
        })
        let taps = services.notifier.taps
        tasks.append(Task { [weak self] in
            for await payload in taps { self?.onNotificationTap(payload) }
        })
    }

    public func stop() {
        tasks.forEach { $0.cancel() }; tasks = []
        router.unregister(.miniApp, self)
        started = false
    }

    // MARK: Rail

    public var railItems: [MiniAppRailItem] {
        apps.map { MiniAppRailItem(id: $0.id, name: $0.name, iconPath: $0.iconPath, running: liveIds.contains($0.id),
                                   selected: onScreen && $0.id == currentId) }
    }

    /// The mini app the shell shows (nil: none selected). Keeps it running, evicting the longest-unused page past the limit.
    public func show(_ id: String?) {
        currentId = id
        onScreen = id != nil
        recomputeLive()
        if let id { resolveWaiters(id) }
    }

    /// Closes `id`'s page; it opens again, reloaded, when shown on the rail.
    public func close(_ id: String) {
        liveIds.removeAll { $0 == id }
        tabSets.removeValue(forKey: id)?.teardown()
        if currentId == id { currentId = nil; onScreen = false }
    }

    /// Reloads the running pages (every tab) of the sites whose cookies were just imported, so they show the sign-in at once.
    func reloadRunningApps(ofSites sites: Set<String>) {
        for app in apps {
            guard let host = URL(string: app.url)?.host, !host.isEmpty, sites.contains(cookieSite(of: host)) else { continue }
            tabSets[app.id]?.reloadAll()
        }
    }

    /// Reloads the running pages of the apps `ids`, once what they kept was cleared, so none holds a sign-in it no longer has.
    func reloadRunningApps(ids: [String]) {
        for id in ids { tabSets[id]?.reloadAll() }
    }

    public func move(from: Int, to: Int) async {
        if case .success(let moved) = await services.moveMiniApp(apps, from: from, to: to) { apps = moved }
    }

    /// Drops the app `id` where `target` is on the rail (a drag and drop): it takes `target`'s place and the rest shift.
    public func move(id: String, onto target: String) async {
        guard let from = apps.firstIndex(where: { $0.id == id }), let to = apps.firstIndex(where: { $0.id == target }) else { return }
        await move(from: from, to: to)
    }

    public func remove(_ id: String) async {
        close(id)
        _ = await services.apps.delete(id: id)
        // Its site is no longer one whose session cookies are kept.
        await sessionCookies?.snapshotNow()
    }

    // MARK: Pages

    /// The tabs of a running app; a first tab opens on the link that started it, else the page it was last on, else its address.
    func tabsModel(for app: MiniApp) -> MiniAppTabsModel {
        if let existing = tabSets[app.id] { return existing }
        let claimed = takeNavigation(for: app.id)
        let app = current(app)
        let kept = app.openTabs.filter { URL(string: $0).map { $0.scheme == "http" || $0.scheme == "https" } ?? false }
        let tabs: MiniAppTabsModel
        if kept.count > 1 {
            tabs = MiniAppTabsModel(appId: app.id, restoring: kept, selected: app.selectedTab, apps: services.apps)
            // A link that started the app opens in a tab of its own beside the ones it had.
            if let claimed { tabs.newTab(url: claimed) }
        } else {
            tabs = MiniAppTabsModel(appId: app.id, initialUrl: claimed ?? kept.first ?? app.lastUrl ?? app.url, apps: services.apps)
        }
        tabs.prompter = MiniAppPermissionPrompter(model: self)
        tabSets[app.id] = tabs
        return tabs
    }

    /// The tab of `app` on screen.
    func browserModel(for app: MiniApp) -> MiniAppBrowserModel { tabsModel(for: app).selected }

    /// Whether the page in `web` is the app's selected tab (a page in a background tab is not being looked at).
    func isSelectedTab(appId: String, web: AnyObject?) -> Bool {
        guard let web, let tabs = tabSets[appId] else { return true }
        return tabs.selected.parts?.web === web
    }

    /// The tab of app `appId` whose page is in `web`; nil for a window the page opened (or an app that is not running).
    func tab(appId: String, web: AnyObject?) -> MiniAppBrowserModel? {
        guard let web else { return nil }
        return tabSets[appId]?.tabs.first { $0.parts?.web === web }
    }

    /// The app as the database has it now — edited since it was handed over, say — or `app` itself when it is not there.
    func current(_ app: MiniApp) -> MiniApp { apps.first { $0.id == app.id } ?? app }

    func isShown(_ id: String) -> Bool { onScreen && currentId == id }

    /// Resolves once app `id` is the one on screen.
    func untilShown(_ id: String) async {
        if isShown(id) { return }
        await withCheckedContinuation { shownWaiters[id, default: []].append($0) }
    }

    private func resolveWaiters(_ id: String) {
        guard isShown(id) else { return }
        for w in shownWaiters.removeValue(forKey: id) ?? [] { w.resume() }
    }

    private func takeNavigation(for id: String) -> String? {
        guard let p = pending, p.id == id else { return nil }
        pending = nil
        return p.url
    }

    // MARK: Updates

    private func apply(_ list: [MiniApp]) {
        apps = list
        linkTargets = list.compactMap { app in
            guard let host = URL(string: app.url)?.host, !host.isEmpty else { return nil }
            return MiniAppLinkTarget(id: app.id, host: host)
        }
        recomputeLive()
    }

    private func recomputeLive() {
        liveIds = liveMiniApps(live: liveIds, current: currentId, existing: Set(apps.map(\.id)), max: services.settings.liveLimit())
        for (id, tabs) in tabSets where !liveIds.contains(id) { tabs.teardown(); tabSets[id] = nil }
    }

    private func onNotificationTap(_ payload: String) {
        guard let id = miniAppId(ofNotificationPayload: payload) else { return }
        bringToFront?()
        requestShow?(id)
    }

    // MARK: LinkHandler

    /// A tapped link to a site that has a mini app opens there: the page loads in a running one, else starts there.
    public func handle(_ url: String) -> Bool {
        guard let id = findMiniAppForLink(linkTargets, url) else { return false }
        seq += 1
        if let running = tabSets[id] { running.selected.load(url) } else { pending = MiniAppNavigation(id: id, url: url, seq: seq) }
        requestShow?(id)
        return true
    }

    /// Routes a link a page opened in a window of its own, the way a link tapped elsewhere in the app goes (never a sign-in,
    /// never back into `currentAppId` itself). False when nothing took it, so the window opens as a pop-up.
    func routeWindowLink(_ url: String, currentAppId: String, width: Double?, height: Double?) -> Bool {
        if IsSignInWindow()(OpenedWindow(url: url, width: width, height: height)) { return false }
        let skip: Set<LinkStage> = findMiniAppForLink(linkTargets, url) == currentAppId ? [.miniApp] : []
        return router.route(url, skip: skip)
    }

    /// Whether a window a page of app `appId` opened (and nothing took, see `routeWindowLink`) is a tab of that app: a link on
    /// the app's own site that is not a sign-in. Anything else is the pop-up.
    func opensAsTab(_ url: String, appId: String, width: Double?, height: Double?) -> Bool {
        guard let app = apps.first(where: { $0.id == appId }) else { return false }
        if IsSignInWindow()(OpenedWindow(url: url, width: width, height: height)) { return false }
        return IsMiniAppSite()(app.url, url)
    }
}

// MARK: Trusted certificates

extension MiniAppsModel {
    /// Whether the site at `origin` (`https://host:port`) is one the user chose to trust. Read afresh each time — it is asked
    /// only once the system has refused a certificate, so a change made in Settings applies at once. An unreadable list trusts nothing.
    func isTrusted(_ origin: String) async -> Bool {
        guard case .success(let list) = await services.trusted.all() else { return false }
        return list.contains { $0.origin == origin }
    }

    /// Asks whether to trust `origin`, which was refused with `error`; trusted (and remembered) only if the user says so.
    func askToTrust(origin: String, error: String) async -> Bool {
        guard await MiniAppCertificatePrompt.ask(origin: origin, error: error) else { return false }
        if case .success = await services.trusted.trust(origin: origin, error: error) { return true }
        return false
    }

    /// `https://host:port` of `url` (the port spelled out, 443 when the address has none), or nil for anything but a secure address.
    nonisolated static func origin(of url: URL?) -> String? {
        guard let url, url.scheme == "https", let host = url.host, !host.isEmpty else { return nil }
        return "https://\(host):\(url.port ?? 443)"
    }
}
