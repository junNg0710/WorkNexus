import CoreDomain
import Foundation

/// `appString` for keys with `%1$@`-style placeholders (the `.arb` placeholders become printf positionals).
/// The catalog's placeholders are objects (`%@`): a number given for one would be read as an object pointer and crash, so
/// with such a template every argument goes in as its text.
public func appFormat(_ key: String, _ fallback: String, _ args: CVarArg...) -> String {
    let template = appString(key, fallback)
    let safe: [CVarArg] = template.contains("@") ? args.map { $0 is NSString || $0 is String ? $0 : "\($0)" as NSString } : args
    return String(format: template, arguments: safe)
}

/// Ported from: lib/core/util/relative_time.dart (`formatWhen`)
/// "just now", "12m ago", else the app-wide date with time. nil date gives "".
public func formatWhen(_ t: Date?, now: Date = Date(), format: String = "iso") -> String {
    guard let t else { return "" }
    let minutes = Int(now.timeIntervalSince(t) / 60)
    if minutes < 1 { return appString("justNow", "just now") }
    if minutes < 60 { return appFormat("minutesAgo", "%1$@m ago", "\(minutes)") }
    return AppDateFormat.format(t, style: format, withTime: true)
}

/// Ported from: lib/core/util/image_urls.dart
/// The web URL of an image a ticket body refers to (relative upload paths resolved against the account's base URL),
/// so it can be copied or opened in a browser when the authenticated fetch failed.
public func providerImageWebUrl(providerType: ProviderType, baseUrl: String?, projectPath: String?, rawUrl: String) -> String? {
    if let u = URL(string: rawUrl), u.scheme != nil { return rawUrl }
    guard let base = baseUrl?.trimmingCharacters(in: .whitespaces), !base.isEmpty else { return nil }
    let root = base.hasSuffix("/") ? String(base.dropLast()) : base
    if providerType == .gitlab, let p = projectPath, !p.isEmpty, rawUrl.hasPrefix("/uploads/") { return "\(root)/\(p)\(rawUrl)" }
    return rawUrl.hasPrefix("/") ? "\(root)\(rawUrl)" : "\(root)/\(rawUrl)"
}
