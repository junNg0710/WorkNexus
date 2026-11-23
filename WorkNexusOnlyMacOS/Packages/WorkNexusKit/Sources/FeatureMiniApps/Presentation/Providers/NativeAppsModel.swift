import AppKit
import CoreDomain
import CoreUI
import Foundation
import Observation

/// Which Dock badges went up between two reads: a badge where there was none, or a bigger number. A badge that is not a
/// number (a dot) counts as 1.
public enum RisenBadges {
    public static func ids(old: [String: String], new: [String: String]) -> [String] {
        new.keys.sorted().filter { id in
            guard let now = new[id], !now.isEmpty else { return false }
            guard let before = old[id], !before.isEmpty else { return true }
            return count(now) > count(before)
        }
    }

    static func count(_ badge: String) -> Int { Int(badge.filter(\.isNumber)) ?? 1 }
}

/// A Mac app on the rail.
public struct NativeAppRailItem: Identifiable, Equatable, Sendable {
    public var id: String
    /// The app's label (the user's name for it, else its own).
    public var name: String
    public var path: String
    /// The user's icon for it, if any.
    public var iconPath: String? = nil
    /// The app is running now, so the rail shows a dot on it.
    public var running: Bool
    /// The `.app` is no longer where it was (moved or uninstalled).
    public var missing: Bool
    /// What the Dock shows on the app's icon (an unread count, usually); nil when it shows nothing or cannot be read.
    public var badge: String?

    /// The badge as a count for the rail: the number it shows, or 1 for a badge that is not a number (a dot).
    public var badgeCount: Int {
        guard let badge, !badge.isEmpty else { return 0 }
        return Int(badge.filter(\.isNumber)) ?? 1
    }
}

/// New feature, no Dart counterpart. The rail's Mac apps: the list, adding / removing, opening one (or bringing it
/// forward when it already runs), which of them run now (from the workspace's launch / quit notifications) and which went
/// missing, and the installed-apps list behind the "Add Mac app" dialog. Icons come from the system and are kept per path.
@MainActor @Observable
public final class NativeAppsModel {
    public private(set) var apps: [NativeApp] = []
    /// Bundle identifiers of every app running now (the Mac apps' dots read it).
    public private(set) var runningBundleIds: Set<String> = []
    /// Ids of the Mac apps whose `.app` is gone.
    public private(set) var missingIds: Set<String> = []
    /// The installed apps, by name; empty until `loadInstalled()` is done.
    public private(set) var installed: [AppBundleInfo] = []
    public private(set) var loadingInstalled = false
    /// The Dock's badge of each app that has one, by app id.
    public private(set) var badges: [String: String] = [:]
    /// Whether macOS lets the app read the Dock's badges (Privacy & Security → Accessibility).
    public private(set) var badgesAllowed = false
    /// The offer to turn the badges on, when one is due (see `BadgeOffer`); nil once answered or while they work.
    public private(set) var badgeOffer: BadgeOffer?
    /// Told when an app's Dock badge goes up (more unread, or a badge where there was none), with the app and its badge.
    /// Not for the badges found on the first read: those were there before.
    @ObservationIgnored public var onBadgeRose: ((NativeApp, String) -> Void)?
    @ObservationIgnored private var badgesRead = false
    /// Whether the badges are read while the window cannot be seen too: the pet floats over the other apps and says
    /// what comes in (`onBadgeRose`).
    @ObservationIgnored public var readsBadgesInBackground: () -> Bool = { false }

    /// How often the Dock is read for badges.
    static let badgeInterval: Duration = .seconds(4)

    private let repository: NativeAppRepository
    private let addApp: AddNativeApp
    private let removeApp: RemoveNativeApp
    private let editApp: EditNativeApp
    private let installedSource: InstalledAppsSource
    private let launcher: AppLauncher
    private let dock: DockBadgeSource?
    private let offerMemory: BadgeOfferMemory
    @ObservationIgnored private var started = false
    @ObservationIgnored private var tasks: [Task<Void, Never>] = []
    @ObservationIgnored private var icons: [String: NSImage] = [:]

    init(repository: NativeAppRepository, add: AddNativeApp, remove: RemoveNativeApp, edit: EditNativeApp? = nil,
         installed: InstalledAppsSource, launcher: AppLauncher, dock: DockBadgeSource? = nil,
         offerMemory: BadgeOfferMemory? = nil) {
        self.repository = repository; addApp = add; removeApp = remove; editApp = edit ?? EditNativeApp(repository)
        installedSource = installed; self.launcher = launcher; self.dock = dock
        self.offerMemory = offerMemory ?? InMemoryBadgeOfferMemory()
    }

    /// Starts watching the database and the running apps. Idempotent.
    public func start() {
        guard !started else { return }
        started = true
        runningBundleIds = launcher.runningBundleIds()
        let repo = repository, events = launcher.events()
        tasks.append(Task { [weak self] in
            for await list in repo.watchAll() { self?.apply(list) }
        })
        tasks.append(Task { [weak self] in
            for await event in events { self?.apply(event) }
        })
        // The Dock has no "badge changed" event to listen to: it is read every few seconds, and only while there is an app to show it on.
        tasks.append(Task { [weak self] in
            while !Task.isCancelled {
                // Not while the window cannot be seen (hidden to the tray, minimised, covered) - unless the pet floats.
                if AppVisibility.isOnScreen || self?.readsBadgesInBackground() == true { await self?.refreshBadgesOffMain() }
                try? await Task.sleep(for: Self.badgeInterval)
            }
        })
    }

    /// Reads the Dock's badges of the rail's apps now.
    public func refreshBadges() {
        guard let dock, readsBadges(dock) else { return }
        show(dock.badges())
    }

    /// The same without keeping the main thread while the Dock answers: every few seconds, and as a view comes in.
    public func refreshBadgesOffMain() async {
        guard let dock, readsBadges(dock) else { return }
        show(await dock.readBadges())
    }

    /// Keeps the offer to turn badges on up to date; false when there is nothing to read (not allowed, or no app).
    private func readsBadges(_ dock: DockBadgeSource) -> Bool {
        let allowed = dock.isAllowed
        if allowed != badgesAllowed { badgesAllowed = allowed }
        if allowed, !offerMemory.wasAllowed { offerMemory.wasAllowed = true }
        // Offered only once there is an app to show a badge on: asked once, and again whenever access that worked is lost.
        let offer: BadgeOffer? = allowed || apps.isEmpty ? nil : offerMemory.wasAllowed ? .lost : offerMemory.declined ? nil : .first
        if offer != badgeOffer { badgeOffer = offer }
        guard allowed, !apps.isEmpty else { if !badges.isEmpty { badges = [:] }; return false }
        return true
    }

    private func show(_ byPath: [String: String]) {
        var next: [String: String] = [:]
        for app in apps {
            if let label = byPath[DockBadgeReader.normalized(app.path)] ?? byPath[DockBadgeKey.bundle(app.bundleId)] { next[app.id] = label }
        }
        if next != badges {
            if badgesRead, let onBadgeRose {
                for id in RisenBadges.ids(old: badges, new: next) {
                    if let app = apps.first(where: { $0.id == id }), let label = next[id] { onBadgeRose(app, label) }
                }
            }
            badges = next
        }
        badgesRead = true
    }

    /// Asks macOS to let the app read the Dock and opens the page of System Settings where the user ticks it; badges
    /// appear once it is allowed (the Dock is read again every few seconds). Answers the offer.
    public func requestBadgeAccess() {
        dock?.requestAccess(); dock?.openSettings()
        declineBadgeOffer()
    }
    /// "Not now": the offer is not made again (the settings card still has the switch), until access that worked is lost.
    public func declineBadgeOffer() {
        offerMemory.declined = true; offerMemory.wasAllowed = false
        badgeOffer = nil
    }
    /// Whether badges can be offered at all (a Dock reader is wired).
    public var canShowBadges: Bool { dock != nil }

    public func stop() {
        tasks.forEach { $0.cancel() }; tasks = []
        started = false
    }

    // MARK: Rail

    public var railItems: [NativeAppRailItem] {
        apps.map { NativeAppRailItem(id: $0.id, name: $0.label, path: $0.path, iconPath: $0.iconPath, running: runningBundleIds.contains($0.bundleId),
                                     missing: missingIds.contains($0.id), badge: badges[$0.id]) }
    }

    /// Checks again which apps are still installed (the window came forward: the user may have moved one meanwhile).
    public func refreshMissing() {
        let gone = Set(apps.filter { !launcher.exists(path: $0.path) }.map(\.id))
        if gone != missingIds { missingIds = gone }
    }

    /// The icon the rail shows for an app: the user's image when it has one that can be read, else the app's own.
    public func icon(forPath path: String, custom: String?) -> NSImage {
        if let custom {
            if let kept = icons[custom] { return kept }
            if let image = NSImage(contentsOfFile: custom) { icons[custom] = image; return image }
        }
        return icon(forPath: path)
    }

    /// The app's icon as the system draws it; kept per path.
    public func icon(forPath path: String) -> NSImage {
        if let kept = icons[path] { return kept }
        let image = NSWorkspace.shared.icon(forFile: path)
        icons[path] = image
        return image
    }

    // MARK: Commands

    /// Opens the app, or brings it forward and un-hides it when it already runs. A moved or uninstalled app fails with `.notFound`.
    @discardableResult
    public func launch(_ app: NativeApp) async -> Outcome<Void> {
        guard launcher.exists(path: app.path) else {
            refreshMissing()
            return .failure(.notFound("The app is not at \(app.path)"))
        }
        return await launcher.launch(path: app.path, bundleId: app.bundleId)
    }

    public func reveal(_ app: NativeApp) { launcher.reveal(path: app.path) }

    /// Opens the app `id` (the pet's line about it was clicked).
    public func open(id: String) async {
        guard let app = apps.first(where: { $0.id == id }) else { return }
        _ = await launch(app)
    }

    /// Adds the `.app` at `path`; an app already on the rail is kept once (and pointed at `path`, which is how a missing one is located).
    @discardableResult
    public func add(path: String) async -> Outcome<NativeApp> {
        let result = await addApp(path: path, existing: apps)
        if case .success(let app) = result, let i = apps.firstIndex(where: { $0.id == app.id }) { apps[i] = app; refreshMissing() }
        return result
    }

    /// Names app `app` on the rail and sets its icon (nil: its own); the app as kept.
    @discardableResult
    public func edit(_ app: NativeApp, name: String, iconPath: String?) async -> Outcome<NativeApp> {
        let result = await editApp(app, name: name, iconPath: iconPath)
        if case .success(let kept) = result, let i = apps.firstIndex(where: { $0.id == kept.id }) { apps[i] = kept }
        return result
    }

    /// Keeps a copy of the image at `path` as app `id`'s icon (saved with the next `edit`); the copy's path.
    public func importIcon(id: String, from path: String) async -> Outcome<String> {
        await repository.importIcon(id: id, sourcePath: path)
    }

    public func remove(_ id: String) async {
        if case .success = await removeApp(id: id) { apps.removeAll { $0.id == id } }
    }

    /// Shows the apps at the places they were just given on the rail (`RailAppsModel`), before the database says so.
    func reposition(_ position: (String) -> Int?) {
        apps = apps.map { app in var app = app; app.position = position(app.id) ?? app.position; return app }.sorted { $0.position < $1.position }
    }

    /// Whether a Mac app with this bundle identifier is on the rail already.
    public func isAdded(_ bundleId: String) -> Bool { apps.contains { $0.bundleId == bundleId } }

    /// Looks the installed apps up (once per call), for the add dialog.
    public func loadInstalled() async {
        loadingInstalled = true
        installed = await installedSource.installed()
        loadingInstalled = false
    }

    // MARK: Updates

    private func apply(_ list: [NativeApp]) {
        apps = list
        refreshMissing()
    }

    private func apply(_ event: RunningAppEvent) {
        switch event {
        case .launched(let id): runningBundleIds.insert(id)
        case .terminated(let id): runningBundleIds.remove(id)
        }
        // A launch can be the first sign that an app came back.
        refreshMissing()
    }
}
