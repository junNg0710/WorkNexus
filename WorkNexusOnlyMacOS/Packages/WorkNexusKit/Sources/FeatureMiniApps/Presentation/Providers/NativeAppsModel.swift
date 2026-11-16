import AppKit
import CoreDomain
import CoreUI
import Foundation
import Observation

/// One entry of the rail's Mac app section.
public struct NativeAppRailItem: Identifiable, Equatable, Sendable {
    public var id: String
    public var name: String
    public var path: String
    /// The app is running now, so the rail shows a dot on it.
    public var running: Bool
    /// The `.app` is no longer where it was (moved or uninstalled).
    public var missing: Bool
}

/// New feature, no Dart counterpart. The rail's Mac apps: the list, adding / removing / reordering, opening one (or bringing it
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

    private let repository: NativeAppRepository
    private let addApp: AddNativeApp
    private let removeApp: RemoveNativeApp
    private let moveApp: MoveNativeApp
    private let installedSource: InstalledAppsSource
    private let launcher: AppLauncher
    @ObservationIgnored private var started = false
    @ObservationIgnored private var tasks: [Task<Void, Never>] = []
    @ObservationIgnored private var icons: [String: NSImage] = [:]

    init(repository: NativeAppRepository, add: AddNativeApp, remove: RemoveNativeApp, move: MoveNativeApp,
         installed: InstalledAppsSource, launcher: AppLauncher) {
        self.repository = repository; addApp = add; removeApp = remove; moveApp = move
        installedSource = installed; self.launcher = launcher
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
    }

    public func stop() {
        tasks.forEach { $0.cancel() }; tasks = []
        started = false
    }

    // MARK: Rail

    public var railItems: [NativeAppRailItem] {
        apps.map { NativeAppRailItem(id: $0.id, name: $0.name, path: $0.path, running: runningBundleIds.contains($0.bundleId),
                                     missing: missingIds.contains($0.id)) }
    }

    /// Checks again which apps are still installed (the window came forward: the user may have moved one meanwhile).
    public func refreshMissing() {
        let gone = Set(apps.filter { !launcher.exists(path: $0.path) }.map(\.id))
        if gone != missingIds { missingIds = gone }
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

    /// Adds the `.app` at `path`; an app already on the rail is kept once (and pointed at `path`, which is how a missing one is located).
    @discardableResult
    public func add(path: String) async -> Outcome<NativeApp> {
        let result = await addApp(path: path, existing: apps)
        if case .success(let app) = result, let i = apps.firstIndex(where: { $0.id == app.id }) { apps[i] = app; refreshMissing() }
        return result
    }

    public func remove(_ id: String) async {
        if case .success = await removeApp(id: id) { apps.removeAll { $0.id == id } }
    }

    public func move(from: Int, to: Int) async {
        if case .success(let moved) = await moveApp(apps, from: from, to: to) { apps = moved }
    }

    /// Drops the app `id` where `target` is on the rail (a drag and drop): it takes `target`'s place and the rest shift.
    public func move(id: String, onto target: String) async {
        guard let from = apps.firstIndex(where: { $0.id == id }), let to = apps.firstIndex(where: { $0.id == target }) else { return }
        await move(from: from, to: to)
    }

    /// One step towards the start (-1) or the end (+1) of the rail.
    public func move(id: String, by step: Int) async {
        guard let from = apps.firstIndex(where: { $0.id == id }) else { return }
        await move(from: from, to: from + step)
    }

    public func canMove(id: String, by step: Int) -> Bool {
        guard let i = apps.firstIndex(where: { $0.id == id }) else { return false }
        return apps.indices.contains(i + step)
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
