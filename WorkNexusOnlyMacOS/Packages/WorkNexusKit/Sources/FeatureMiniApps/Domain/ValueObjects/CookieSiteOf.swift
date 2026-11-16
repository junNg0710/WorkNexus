/// Ported from: lib/features/mini_apps/domain/value_objects/cookie_site_of.dart
/// Second-level labels under which a country domain hands out names (`example.com.vn`, `example.co.uk`).
private let secondLevels: Set<String> = ["com", "co", "net", "org", "gov", "edu", "ac", "or"]

/// The site a cookie `domain` belongs to, the name a user knows it by: `.mail.google.com` → `google.com`,
/// `shop.example.com.vn` → `example.com.vn`. An address or a single-label host is its own site. An approximation of the
/// public suffix list, close enough to group what a user picks from.
public func cookieSite(of domain: String) -> String {
    let host = domain.hasPrefix(".") ? String(domain.dropFirst()) : domain
    let labels = host.lowercased().split(separator: ".", omittingEmptySubsequences: false).map(String.init)
    if labels.count <= 2 || Int(labels.last ?? "") != nil { return host.lowercased() }
    let keep = labels.last!.count == 2 && secondLevels.contains(labels[labels.count - 2]) ? 3 : 2
    return labels.suffix(keep).joined(separator: ".")
}
