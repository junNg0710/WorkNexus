import CoreDomain
import Foundation

/// Ported from: lib/app/di/provider_adapter_registry_impl.dart (`ProviderType.github` branch of `buildProviderAdapter`)
/// Public factory the composition root's `ProviderAdapterRegistry` calls: account + secret (the PAT) → adapter.
public enum GitHubAdapterFactory {
    /// A `ProviderAdapter` for `account`, or nil when the account is not a GitHub account.
    public static func make(account: Account, secret: String) -> ProviderAdapter? {
        makePullRequestAdapter(account: account, secret: secret)
    }

    /// The same adapter, typed with the GitHub-specific PR/repo operations.
    public static func makePullRequestAdapter(account: Account, secret: String) -> GitHubPrAdapter? {
        guard account.providerType == .github else { return nil }
        return GitHubProviderAdapter(accountId: account.id, client: GitHubClient(baseUrl: account.baseUrl ?? "", token: secret))
    }

    /// Variant with an injected `URLSession` (UI tests / previews with stubbed networking). Certificates are then
    /// validated by the session as usual.
    public static func make(accountId: String, baseUrl: String, token: String, session: URLSession) -> GitHubPrAdapter {
        GitHubProviderAdapter(accountId: accountId, client: GitHubClient(baseUrl: baseUrl, token: token, session: session))
    }
}
