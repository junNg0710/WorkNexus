import Foundation

/// Ported from: lib/core/navigation/mini_app_links.dart
/// A mini app a tapped link can open in: its id and the site it shows.
public struct MiniAppLinkTarget: Sendable, Equatable {
    public var id: String
    public var host: String
    public init(id: String, host: String) { self.id = id; self.host = host }
}

/// The id of the mini app that shows `url`'s site, or nil. The site's own host wins over one of its parents, so
/// `a.example.com` prefers an app added for `a.example.com` to one added for `example.com`. Only web links match.
public func findMiniAppForLink(_ targets: [MiniAppLinkTarget], _ url: String) -> String? {
    guard let uri = URL(string: url.trimmingCharacters(in: .whitespacesAndNewlines)),
          let scheme = uri.scheme?.lowercased(), scheme == "http" || scheme == "https",
          let host = uri.host?.lowercased(), !host.isEmpty else { return nil }
    var best: MiniAppLinkTarget?
    for t in targets {
        let h = t.host.lowercased()
        guard host == h || host.hasSuffix(".\(h)") else { continue }
        if best == nil || h.count > best!.host.count { best = t }
    }
    return best?.id
}
