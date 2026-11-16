import Foundation
import Observation

/// What a mini app's page lets the model drive; the WKWebView implementation lives in `Util/WKMiniAppPage.swift`.
@MainActor
protocol MiniAppPageDriver: AnyObject {
    func load(_ url: String)
    func reload()
    func hardReload()
    func stop()
    func goBack()
    func goForward()
}

/// Ported from: lib/features/mini_apps/presentation/providers/mini_app_browser_controller.dart (+ mini_app_browser_state.dart)
/// The browsing of one tab of a mini app: what the toolbar and the cover show, and the commands that drive the web view.
/// The view only draws it, and hands the page over once its web view exists (`attach`). The page to reopen next time is
/// kept after it settles (`saveDelay`) or when the tab closes: single-page sites move on every click. Only the app's
/// selected tab keeps it (`setPersists`), so the app reopens where the user last was.
@MainActor @Observable
final class MiniAppBrowserModel: Identifiable {
    /// Identifies the tab among its app's.
    let id = UUID()
    /// Loading progress, 0 to 1; 1 when idle.
    private(set) var progress = 1.0
    private(set) var canGoBack = false
    private(set) var canGoForward = false
    /// Why the page could not load; nil while it is fine.
    private(set) var loadError: String?
    /// The address the page opened on: the link that opened the app, else the page it was last on, else its own address.
    let initialUrl: String
    /// The page's current address.
    private(set) var address: String
    /// The page's title (the tab's label); empty until it has one.
    private(set) var title = ""
    /// A site's certificate was refused (`net::ERR_CERT_…`): the host view asks whether to trust it.
    private(set) var certificateError: (origin: String, error: String)?

    /// The windows the page opened (sign-in pop-ups), shown over it, last on top.
    private(set) var popups: [MiniAppPopupWindow] = []

    let appId: String
    var loading: Bool { progress < 1 }

    /// The web view and what has to live as long as it (delegate, page driver); built by the view, or handed in by the page's
    /// request for a window of its own.
    @ObservationIgnored var parts: MiniAppWebParts?
    /// The page itself asked for this tab (`window.open`, `target=_blank`), so the page may close it (`window.close()`).
    @ObservationIgnored var openedByPage = false
    @ObservationIgnored private weak var web: MiniAppPageDriver?
    @ObservationIgnored private let apps: MiniAppRepository
    @ObservationIgnored private var unsaved: String?
    @ObservationIgnored private var saveTask: Task<Void, Never>?
    @ObservationIgnored private(set) var persistsLastUrl = true
    static let saveDelay: Duration = .seconds(3)

    init(appId: String, initialUrl: String, apps: MiniAppRepository) {
        self.appId = appId; self.initialUrl = initialUrl; address = initialUrl; self.apps = apps
    }

    deinit { saveTask?.cancel() }

    func attach(_ web: MiniAppPageDriver) { self.web = web }

    func add(_ popup: MiniAppPopupWindow) { popups.append(popup) }
    func remove(_ popup: MiniAppPopupWindow) { popups.removeAll { $0.id == popup.id } }

    func load(_ url: String) { web?.load(url) }
    func reload() { web?.reload() }
    func hardReload() { web?.hardReload() }
    func stop() { web?.stop() }
    func goBack() { if canGoBack { web?.goBack() } }
    func goForward() { if canGoForward { web?.goForward() } }

    // MARK: What the web view reports

    func onLoadStart() { loadError = nil; certificateError = nil }
    func onProgress(_ value: Double) { progress = value }
    func onError(_ message: String) { loadError = message }
    func onTitle(_ value: String) { title = value }
    func onCertificateError(origin: String, error: String) { certificateError = (origin, error) }
    func clearCertificateError() { certificateError = nil }

    /// The page moved to `url`: show it, keep it to reopen next time (web pages only) and refresh what back / forward can do.
    func onVisited(_ url: URL, canGoBack back: Bool, canGoForward forward: Bool) {
        address = url.absoluteString
        canGoBack = back; canGoForward = forward
        if persistsLastUrl && Self.isWeb(url) { rememberLater(url.absoluteString) }
    }

    func onNavigationState(canGoBack back: Bool, canGoForward forward: Bool) { canGoBack = back; canGoForward = forward }

    /// Whether this tab is the one whose page the app reopens on. Becoming it keeps the page it is on now.
    func setPersists(_ on: Bool) {
        if on == persistsLastUrl { return }
        if on {
            persistsLastUrl = true
            if let url = URL(string: address), Self.isWeb(url) { rememberLater(address) }
        } else {
            flush()
            persistsLastUrl = false
        }
    }

    /// Writes the pending page now (the tab or the app is closing).
    func flush() {
        saveTask?.cancel()
        guard let url = unsaved else { return }
        unsaved = nil
        let id = appId, apps = apps
        Task { _ = await apps.saveLastUrl(id: id, url: url) }
    }

    /// Lets go of the web view: the page stops and its windows close. Nothing else uses the tab afterwards.
    func teardown() {
        popups.forEach { $0.web.stopLoading() }
        popups = []
        parts?.teardown()
        parts = nil
    }

    private static func isWeb(_ url: URL) -> Bool { url.scheme == "http" || url.scheme == "https" }

    private func rememberLater(_ url: String) {
        unsaved = url
        saveTask?.cancel()
        saveTask = Task { [weak self] in
            try? await Task.sleep(for: Self.saveDelay)
            if !Task.isCancelled { self?.flush() }
        }
    }
}
