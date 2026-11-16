import Foundation
import Observation

/// The tabs of one mini app: each its own page (`MiniAppBrowserModel`, one web view and so one web process) in the web
/// profile every mini app shares, so a sign-in in one is in all. A new tab opens on the app's address, or on a link the page
/// opened in a window of its own on the app's site (see `MiniAppsModel.opensAsTab`). Tabs live as long as their app is
/// kept running: they are not saved, and an app closed to free memory reopens on a single tab.
@MainActor @Observable
final class MiniAppTabsModel {
    /// One web process each, so an app keeps this many at most; a page asking for more gets a pop-up.
    static let maxTabs = 10

    let appId: String
    private(set) var tabs: [MiniAppBrowserModel]
    private(set) var selectedId: MiniAppBrowserModel.ID
    /// Answers the permission requests of all the app's tabs, so two tabs asking at once get one dialog.
    @ObservationIgnored var prompter: MiniAppPermissionPrompter?
    @ObservationIgnored private let apps: MiniAppRepository

    init(appId: String, initialUrl: String, apps: MiniAppRepository) {
        self.appId = appId; self.apps = apps
        let first = MiniAppBrowserModel(appId: appId, initialUrl: initialUrl, apps: apps)
        tabs = [first]; selectedId = first.id
    }

    /// The tab on screen.
    var selected: MiniAppBrowserModel { tabs.first { $0.id == selectedId } ?? tabs[0] }
    var canOpenTab: Bool { tabs.count < Self.maxTabs }
    var canCloseTab: Bool { tabs.count > 1 }

    /// A tab for `url`, not yet among the tabs (add it with `add`); nil at the limit.
    func makeTab(url: String) -> MiniAppBrowserModel? {
        guard canOpenTab else { return nil }
        let tab = MiniAppBrowserModel(appId: appId, initialUrl: url, apps: apps)
        tab.setPersists(false)
        return tab
    }

    /// Puts `tab` last and, when `select`, in front.
    func add(_ tab: MiniAppBrowserModel, select shown: Bool) {
        tabs.append(tab)
        if shown { select(tab.id) }
    }

    /// Opens `url` in a tab of its own; nil at the limit.
    @discardableResult
    func newTab(url: String, select shown: Bool = true) -> MiniAppBrowserModel? {
        guard let tab = makeTab(url: url) else { return nil }
        add(tab, select: shown)
        return tab
    }

    func select(_ id: MiniAppBrowserModel.ID) {
        guard id != selectedId, let next = tabs.first(where: { $0.id == id }) else { return }
        selected.setPersists(false)
        selectedId = id
        next.setPersists(true)
    }

    func selectNext() { step(1) }
    func selectPrevious() { step(-1) }

    private func step(_ delta: Int) {
        guard tabs.count > 1, let at = tabs.firstIndex(where: { $0.id == selectedId }) else { return }
        select(tabs[(at + delta + tabs.count) % tabs.count].id)
    }

    /// Closes tab `id`, leaving its neighbour on screen. The last tab stays: a page is never closed this way, the app is.
    @discardableResult
    func close(_ id: MiniAppBrowserModel.ID) -> Bool {
        guard canCloseTab, let at = tabs.firstIndex(where: { $0.id == id }) else { return false }
        let gone = tabs.remove(at: at)
        if id == selectedId {
            selectedId = tabs[min(at, tabs.count - 1)].id
            selected.setPersists(true)
        }
        gone.flush()
        gone.teardown()
        return true
    }

    func reloadAll() { tabs.forEach { $0.reload() } }

    func flush() { tabs.forEach { $0.flush() } }

    /// The app closes: every tab's page is kept and its web view let go.
    func teardown() {
        flush()
        tabs.forEach { $0.teardown() }
    }
}
