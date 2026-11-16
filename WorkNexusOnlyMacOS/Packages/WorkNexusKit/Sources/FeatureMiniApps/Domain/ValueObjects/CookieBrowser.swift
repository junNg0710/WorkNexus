/// Ported from: lib/features/mini_apps/domain/value_objects/cookie_browser.dart
/// A browser whose cookies can be brought into the mini apps. The Chromium ones share one way of keeping them; Firefox and
/// Safari each have their own. Raw values match the Dart enum names (stored in `cookie_imports.json`).
public enum CookieBrowser: String, Sendable, CaseIterable, Hashable {
    case chrome, edge, brave, arc, firefox, safari
    public var isChromium: Bool {
        switch self { case .chrome, .edge, .brave, .arc: true; case .firefox, .safari: false }
    }
}
