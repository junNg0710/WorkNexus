import CoreDomain
import Foundation

/// Ported from: lib/shared/sync/data/provider_adapter_pool.dart
/// One live `ProviderAdapter` per account, so every path for an account shares ONE provider client — ZenTao drops
/// the previous session on every login. Owned by `SyncCoordinator` (an actor), which serializes access.
final class ProviderAdapterPool {
    private let accountLookup: @Sendable (String) async -> Account?
    private let credentials: CredentialStore
    private let registry: ProviderAdapterRegistry
    private var adapters: [String: (fingerprint: String, adapter: ProviderAdapter)] = [:]

    init(accountLookup: @escaping @Sendable (String) async -> Account?, credentials: CredentialStore, registry: ProviderAdapterRegistry) {
        self.accountLookup = accountLookup; self.credentials = credentials; self.registry = registry
    }

    /// The pooled adapter for `account`, rebuilt when its secret or connection details changed (re-authentication).
    func build(_ account: Account, secret: String) -> ProviderAdapter? {
        let fingerprint = "\(account.baseUrl ?? "")|\(account.handle)|\(secret)"
        if let c = adapters[account.id], c.fingerprint == fingerprint { return c.adapter }
        guard let adapter = registry.createAdapter(account: account, secret: secret) else {
            adapters[account.id] = nil
            return nil
        }
        adapters[account.id] = (fingerprint, adapter)
        return adapter
    }

    /// Reads the account and secret on every call so a removed account or rewritten secret never gets a stale adapter.
    func forAccount(_ accountId: String) async -> ProviderAdapter? {
        guard let account = await accountLookup(accountId), let ref = account.credentialsRef,
              let secret = await credentials.read(ref) else {
            adapters[accountId] = nil
            return nil
        }
        return build(account, secret: secret)
    }
}
