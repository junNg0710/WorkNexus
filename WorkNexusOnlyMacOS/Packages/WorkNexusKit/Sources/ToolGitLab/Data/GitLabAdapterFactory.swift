import CoreDomain
import Foundation

/// Ported from: lib/app/di/provider_adapter_registry_impl.dart (`ProviderType.gitlab` branch of `buildProviderAdapter`)
/// Public factory the composition root's `ProviderAdapterRegistry` calls: account + secret (the PAT) → adapter.
public enum GitLabAdapterFactory {
    /// A `ProviderAdapter` for `account`, or nil when the account is not a GitLab account.
    public static func make(account: Account, secret: String) -> ProviderAdapter? {
        makeMergeRequestAdapter(account: account, secret: secret)
    }

    /// The same adapter, typed with the GitLab-specific MR/project operations.
    public static func makeMergeRequestAdapter(account: Account, secret: String) -> GitLabMrAdapter? {
        guard account.providerType == .gitlab else { return nil }
        return GitLabProviderAdapter(accountId: account.id, client: GitLabClient(baseUrl: account.baseUrl ?? "", token: secret))
    }

    /// Variant with an injected `URLSession` (UI tests / previews with stubbed networking). Certificates are then
    /// validated by the session as usual.
    public static func make(accountId: String, baseUrl: String, token: String, session: URLSession) -> GitLabMrAdapter {
        GitLabProviderAdapter(accountId: accountId, client: GitLabClient(baseUrl: baseUrl, token: token, session: session))
    }
}
