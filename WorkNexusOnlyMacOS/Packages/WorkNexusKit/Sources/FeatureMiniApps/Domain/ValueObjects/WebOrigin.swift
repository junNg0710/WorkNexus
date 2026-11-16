import Foundation

/// New (no Dart counterpart): the origin of a web page — `https://host`, or `https://host:8443` when the port is not the
/// scheme's own — lower-cased, the way `location.origin` spells it. nil for anything but an `http` / `https` address with a
/// host, so a `file:`, `about:` or `data:` page never has saved sign-ins.
public func webOrigin(of url: URL?) -> String? {
    guard let url, let scheme = url.scheme?.lowercased(), let host = url.host?.lowercased(), !host.isEmpty else { return nil }
    return webOrigin(scheme: scheme, host: host, port: url.port)
}

/// The origin made of its parts (a port of 0, or the scheme's own, is left out).
public func webOrigin(scheme: String, host: String, port: Int?) -> String? {
    let scheme = scheme.lowercased(), host = host.lowercased()
    guard scheme == "http" || scheme == "https", !host.isEmpty else { return nil }
    let standard = scheme == "https" ? 443 : 80
    // An IPv6 address is written in brackets.
    let name = host.contains(":") && !host.hasPrefix("[") ? "[\(host)]" : host
    guard let port, port != 0, port != standard else { return "\(scheme)://\(name)" }
    return "\(scheme)://\(name):\(port)"
}

/// The origin an address typed or stored as text belongs to (`https://example.com/login?next=…` → `https://example.com`).
public func webOrigin(ofAddress text: String) -> String? {
    webOrigin(of: URL(string: text.trimmingCharacters(in: .whitespacesAndNewlines)))
}

/// `origin` without its scheme: `intranet.corp.com`, `nas.local:5001`.
public func webOriginHost(_ origin: String) -> String {
    guard let at = origin.range(of: "://") else { return origin }
    return String(origin[at.upperBound...])
}

/// The bare host of `origin` (no scheme, no port), for grouping by site.
public func webOriginHostName(_ origin: String) -> String {
    URL(string: origin)?.host?.lowercased() ?? webOriginHost(origin)
}

/// Whether `origin` is an encrypted one. A sign-in is offered and filled on `http` too (tools on the local network), but
/// only ever on the very origin it was saved on.
public func webOriginIsSecure(_ origin: String) -> Bool { origin.hasPrefix("https://") }
