import Foundation
import ObjectiveC

/// Resolves a UI string by its `lib/l10n/*.arb` key in the app's `Localizable.xcstrings`, in the language the user picked
/// (`AppSettings.localeCode`, see `AppLanguage`), with the English text as fallback so widgets still read correctly in tests
/// and previews.
/// A catalog value that is still an ICU plural (`{count, plural, ...}`; only Vietnamese is resolved at generation
/// time) is never shown raw: the caller's fallback, which already picked the right plural form, is used instead.
///
/// The catalog is generated from the `.arb` files, which turns a named placeholder (`{count}`) into a positional one
/// (`%1$@`). A caller that fills names (`.replacingOccurrences(of: "{count}", …)`, `shellString`) would then show `%1$@`
/// raw ("Show all %1$@ lines"), so the positions are named back after the fallback's placeholders, in their order.
public func appString(_ key: String, _ fallback: String) -> String {
    let text = AppLanguage.bundle.localizedString(forKey: key, value: fallback, table: nil)
    return text.contains("plural,") ? fallback : namingPlaceholders(text, like: fallback)
}

/// `text` with each `%n$@` written as the n-th `{name}` of `fallback`; unchanged when `fallback` names none.
func namingPlaceholders(_ text: String, like fallback: String) -> String {
    guard text.contains("$@"), fallback.contains("{") else { return text }
    var names: [String] = []
    var rest = Substring(fallback)
    while let open = rest.firstIndex(of: "{"), let close = rest[open...].firstIndex(of: "}") {
        let name = rest[rest.index(after: open)..<close]
        if !name.isEmpty, name.allSatisfy({ $0.isLetter || $0.isNumber || $0 == "_" }), !names.contains(String(name)) {
            names.append(String(name))
        }
        rest = rest[rest.index(after: close)...]
    }
    var out = text
    for (i, name) in names.enumerated() { out = out.replacingOccurrences(of: "%\(i + 1)$@", with: "{\(name)}") }
    return out
}

/// The language the UI shows. SwiftUI and `String(localized:)` follow the language the process started with; a picker that
/// must act at once needs more, so this does three things when the code changes:
/// - `appString` reads the picked language's `.lproj` (`bundle`);
/// - `Bundle.main` answers `localizedString(forKey:)` from that `.lproj` too, which covers `String(localized:)` and
///   `NSLocalizedString` calls of the feature modules;
/// - `AppleLanguages` is written to the app's own defaults, so the next launch starts in the same language.
/// Views read `locale` into `\.locale` for `LocalizedStringKey` text, and are rebuilt (`.id(code)`) by the host.
public enum AppLanguage {
    public static let supported = ["en", "vi"]
    private static let lock = NSLock()
    nonisolated(unsafe) private static var override: Bundle?
    nonisolated(unsafe) private static var code = "en"
    nonisolated(unsafe) private static var applied: String?

    /// The `.lproj` bundle of the picked language, else the main bundle.
    public static var bundle: Bundle { lock.withLock { override } ?? .main }
    public static var current: String { lock.withLock { code } }
    public static var locale: Locale { Locale(identifier: current) }

    /// Makes `code` ("en", "vi") the UI language. Idempotent and cheap: the host calls it from a view body.
    public static func apply(_ requested: String) {
        let new = supported.contains(requested) ? requested : "en"
        let changed: Bool = lock.withLock {
            guard applied != new else { return false }
            applied = new; code = new
            override = Bundle.main.path(forResource: new, ofType: "lproj").flatMap { Bundle(path: $0) }
            return true
        }
        guard changed else { return }
        installMainBundleOverride()
        UserDefaults.standard.set([new], forKey: "AppleLanguages")
    }

    private static func installMainBundleOverride() {
        if object_getClass(Bundle.main) != LanguageBundle.self { object_setClass(Bundle.main, LanguageBundle.self) }
    }
}

/// `Bundle.main` after `AppLanguage.apply`: strings come from the picked language's `.lproj`.
private final class LanguageBundle: Bundle, @unchecked Sendable {
    override func localizedString(forKey key: String, value: String?, table tableName: String?) -> String {
        guard let picked = AppLanguage.pickedBundle else { return super.localizedString(forKey: key, value: value, table: tableName) }
        return picked.localizedString(forKey: key, value: value, table: tableName)
    }
}

extension AppLanguage {
    /// The override bundle itself (nil while none was picked), for `LanguageBundle`.
    fileprivate static var pickedBundle: Bundle? { lock.withLock { override } }
}
