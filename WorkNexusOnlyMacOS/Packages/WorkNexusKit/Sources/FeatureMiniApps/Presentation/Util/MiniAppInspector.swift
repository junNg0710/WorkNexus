import WebKit

/// Opens the web inspector of a page (⇧⌘I, F12). WebKit has no public call for it — `isInspectable` only adds "Inspect Element"
/// to the context menu — so this asks the web view's private inspector object, and does nothing when it is not there.
enum MiniAppInspector {
    @MainActor @discardableResult
    static func show(_ web: WKWebView?) -> Bool {
        let getter = NSSelectorFromString("_inspector"), show = NSSelectorFromString("show")
        guard let web, web.isInspectable, web.responds(to: getter), let inspector = web.value(forKey: "_inspector") as? NSObject,
              inspector.responds(to: show) else { return false }
        inspector.perform(show)
        return true
    }
}
