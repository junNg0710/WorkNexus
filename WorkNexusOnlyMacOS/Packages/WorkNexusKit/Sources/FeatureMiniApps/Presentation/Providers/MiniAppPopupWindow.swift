import Foundation
import Observation
import WebKit

/// Ported from: lib/features/mini_apps/presentation/widgets/mini_app_popup.dart (state)
/// The window a page asked for (`window.open`, a `target="_blank"` link, a sign-in pop-up), shown over the mini app, inside
/// the app. It is the page's own window, so the page can talk back to its opener and close it — what a pop-up sign-in
/// needs to finish.
@MainActor @Observable
final class MiniAppPopupWindow: Identifiable {
    let id = UUID()
    let web: WKWebView
    var title = ""
    var url: URL?
    var canGoBack = false
    var canGoForward = false
    @ObservationIgnored var delegate: AnyObject?
    @ObservationIgnored var observers: [NSKeyValueObservation] = []

    init(web: WKWebView) { self.web = web }

    /// Whether `url` is a page the browser can be given: a web address, not the blank page a pop-up starts on.
    static func isWebAddress(_ url: URL?) -> Bool { url?.scheme == "http" || url?.scheme == "https" }
}
