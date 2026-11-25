import CoreDomain
import Foundation

/// Ported from: lib/shared/sync/data/provider_adapter_pool.dart
/// One live `ProviderAdapter` per account, so every path for an account shares ONE provider client — ZenTao drops
/// the previous session on every login. Owned by `SyncCoordinator`.
///
/// Its table is locked: `forAccount` is async, so although the coordinator is an actor the calls do not run on it -
/// several at once (each account's first sync, a board's metrics) wrote the dictionary together at launch, which now and
/// then ended the app there ("unrecognized selector sent to instance" inside `Dictionary.setValue`).
final class ProviderAdapterPool: @unchecked Sendable {
    private let accountLookup: @Sendable (String) async -> Account?
    private let credentials: CredentialStore
    private let registry: ProviderAdapterRegistry
    private let lock = NSLock()
    private var adapters: [String: (fingerprint: String, adapter: ProviderAdapter)] = [:]

    init(accountLookup: @escaping @Sendable (String) async -> Account?, credentials: CredentialStore, registry: ProviderAdapterRegistry) {
        self.accountLookup = accountLookup; self.credentials = credentials; self.registry = registry
    }

    /// The pooled adapter for `account`, rebuilt when its secret or connection details changed (re-authentication).
    func build(_ account: Account, secret: String) -> ProviderAdapter? {
        let fingerprint = "\(account.baseUrl ?? "")|\(account.handle)|\(secret)"
        lock.lock(); defer { lock.unlock() }
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
            forget(accountId)
            return nil
        }
        return build(account, secret: secret)
    }

    private func forget(_ accountId: String) {
        lock.lock(); defer { lock.unlock() }
        adapters[accountId] = nil
    }
}
