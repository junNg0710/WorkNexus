import Foundation

/// Ported from: lib/core/util/link_url.dart
/// The link typed into the editor's link dialog, made whole: a bare `example.com/x` gains `https://`.
/// Nil when it is not a usable link (no host, spaces, or an unknown scheme).
public func normalizeLinkUrl(_ input: String) -> String? {
    let raw = input.trimmingCharacters(in: .whitespacesAndNewlines)
    if raw.isEmpty || raw.rangeOfCharacter(from: .whitespacesAndNewlines) != nil { return nil }
    if raw.hasPrefix("mailto:") { return raw.count > 7 ? raw : nil }
    let withScheme = raw.contains("://") ? raw : "https://\(raw)"
    guard let comps = URLComponents(string: withScheme),
          let scheme = comps.scheme, scheme == "http" || scheme == "https" else { return nil }
    // A host needs a dot (or is localhost) to be a real address.
    guard let host = comps.host, !host.isEmpty, host.contains(".") || host == "localhost" else { return nil }
    return withScheme
}
