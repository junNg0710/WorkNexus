import Foundation

/// Ported from: lib/features/mini_apps/domain/usecases/is_sign_in_window.dart
/// A window a page opens, as far as the app can tell: where it goes and how big the page asked it to be (`width`/`height`
/// nil or 0 when it gave none, as a `target="_blank"` link does).
public struct OpenedWindow: Sendable, Equatable {
    public var url: String
    public var width: Double?
    public var height: Double?
    public init(url: String, width: Double? = nil, height: Double? = nil) { self.url = url; self.width = width; self.height = height }
}

/// Whether a window a page opens is a sign-in: one the page waits on for an answer ("Sign in with Google", a company
/// login), which has to stay a window of its own so it can hand the answer back, and not be carried off to another mini
/// app or the browser. It is one when the page gave it a size, or when its address shows it: a login word in its path, a
/// host that is an identity provider's, or the parameters of an OAuth request.
public struct IsSignInWindow: Sendable {
    public init() {}

    private static let pathWords: Set<String> = ["oauth", "oauth2", "authorize", "authorise", "authorization", "authenticate", "auth",
                                                 "login", "signin", "sso", "saml", "saml2", "openid"]
    private static let hostLabels: Set<String> = ["accounts", "login", "signin", "auth", "sso", "idp", "oauth", "identity"]
    private static let queryKeys: Set<String> = ["client_id", "redirect_uri", "response_type", "code_challenge", "oauth_token"]

    public func callAsFunction(_ window: OpenedWindow) -> Bool {
        if (window.width ?? 0) > 0 && (window.height ?? 0) > 0 { return true }
        guard let comps = URLComponents(string: window.url.trimmingCharacters(in: .whitespacesAndNewlines)) else { return false }
        if (comps.queryItems ?? []).contains(where: { Self.queryKeys.contains($0.name) }) { return true }
        let labels = (comps.host ?? "").lowercased().split(separator: ".", omittingEmptySubsequences: false).map(String.init)
        if labels.count > 2, Self.hostLabels.contains(labels[0]) { return true }
        // `sign-in`, `log_in` and `user-login.html` all say it in their words.
        let words = comps.path.lowercased().split(whereSeparator: { !($0.isASCII && ($0.isLetter || $0.isNumber)) }).map(String.init)
        if words.contains(where: Self.pathWords.contains) { return true }
        // Neighbouring words run together, so `sign-in` and `log-in` read as `signin` and `login`.
        return zip(words, words.dropFirst()).contains { Self.pathWords.contains($0 + $1) }
    }
}
