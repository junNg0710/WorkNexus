import Foundation

/// Ported from: lib/features/mini_apps/domain/usecases/normalize_mini_app_url.dart
/// Turns what was typed into the address a mini app opens, or nil when it is not a web address. A bare `example.com` gets
/// `https://`; only `http` and `https` pass, so `file:` or `javascript:` never reach the web view.
public struct NormalizeMiniAppUrl: Sendable {
    public init() {}

    public func callAsFunction(_ input: String) -> URL? {
        let text = input.trimmingCharacters(in: .whitespacesAndNewlines)
        if text.isEmpty || text.rangeOfCharacter(from: .whitespacesAndNewlines) != nil { return nil }
        let hasScheme = text.range(of: #"^[a-zA-Z][a-zA-Z0-9+.-]*:"#, options: .regularExpression) != nil
        // `localhost:3000` parses as scheme `localhost`; treat a port as a host.
        let looksLikeHostPort = text.range(of: #"^[^/:]+:\d+"#, options: .regularExpression) != nil
        let withScheme = hasScheme && !looksLikeHostPort ? text : "https://\(text)"
        guard let url = URL(string: withScheme), let host = url.host, !host.isEmpty,
              url.scheme == "http" || url.scheme == "https" else { return nil }
        return url
    }

    /// What an app added without a name is called: its site's host.
    public func defaultName(_ url: URL) -> String {
        (url.host ?? "").replacingOccurrences(of: "^www\\.", with: "", options: .regularExpression)
    }
}
