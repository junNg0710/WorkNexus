import CoreDomain
import Foundation

/// Ported from: lib/features/mini_apps/domain/usecases/find_saved_web_login.dart
/// The sign-in a saved ZenTao account holds, for the page of its own server.
public struct SavedWebLogin: Sendable, Equatable {
    public var account: String
    public var password: String
    public init(account: String, password: String) { self.account = account; self.password = password }
}

/// The saved sign-in for `page`, when `page` is the login page of a ZenTao account the app holds a password for: the
/// account's server (same scheme, host and port, so a lookalike or another port gets nothing) and a stored password.
/// `.success(nil)` otherwise. What a mini app's login form is filled with. Only the login page itself: any other page of
/// the server (one asking to confirm the password before a change, say) is not handed the password.
public struct FindSavedWebLogin: Sendable {
    private let accounts: @Sendable () async -> [Account]
    /// The secret kept under a credentials ref, or nil.
    private let secret: @Sendable (String) async -> String?

    public init(accounts: @escaping @Sendable () async -> [Account], secret: @escaping @Sendable (String) async -> String?) {
        self.accounts = accounts; self.secret = secret
    }

    public func callAsFunction(_ page: URL?) async -> Outcome<SavedWebLogin?> {
        guard let page, let pageHost = page.host, !pageHost.isEmpty, Self.isLoginPage(page) else { return .success(nil) }
        for account in await accounts() {
            guard account.providerType == .zentao, let ref = account.credentialsRef, let server = account.baseUrl.flatMap(URL.init(string:)),
                  let serverHost = server.host, !serverHost.isEmpty,
                  server.scheme?.lowercased() == page.scheme?.lowercased(), serverHost.lowercased() == pageHost.lowercased(),
                  Self.port(server) == Self.port(page) else { continue }
            guard let password = await secret(ref), !password.isEmpty else { continue }
            return .success(SavedWebLogin(account: account.handle, password: password))
        }
        return .success(nil)
    }

    /// ZenTao's login page, in either URL style: `user-login[-<referer>].html` or `index.php?m=user&f=login`.
    static func isLoginPage(_ page: URL) -> Bool {
        if page.lastPathComponent.hasPrefix("user-login") { return true }
        let q = Dictionary(URLComponents(url: page, resolvingAgainstBaseURL: false)?.queryItems?.map { ($0.name, $0.value ?? "") } ?? [],
                           uniquingKeysWith: { a, _ in a })
        return q["m"] == "user" && q["f"] == "login"
    }

    static func port(_ url: URL) -> Int { url.port ?? (url.scheme?.lowercased() == "https" ? 443 : 80) }
}
