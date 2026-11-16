/// Ported from: lib/app/di/provider_adapter_registry_impl.dart (ZenTao branch)
import CoreDomain
import Foundation

/// Builds ZenTao adapters for the composition root (`account + secret -> ProviderAdapter`), the ZenTao half of
/// the Dart `ProviderAdapterRegistryImpl` in `app/di/`.
///
/// ```swift
/// // in the registry's `createAdapter(account:secret:)`:
/// case .zentao: return ZentaoAdapterFactory.makeAdapter(account: account, secret: secret)
/// ```
/// The adapter owns one `ZenTaoClient`, i.e. one ZenTao session. ZenTao rotates the session on every login, so
/// the composition root should keep ONE adapter per account (the sync's pool) and hand that out to every service
/// (`ZenTaoClientProvider`) - exactly what the Dart `SyncCoordinator` does.
public enum ZentaoAdapterFactory {
    /// The adapter of `account` (its `baseUrl`, login `handle`) with the password `secret`. Nil for a non-ZenTao
    /// account or one without a server URL.
    public static func makeAdapter(account: Account, secret: String, session: URLSession? = nil) -> ProviderAdapter? {
        makeZenTaoAdapter(account: account, secret: secret, session: session)
    }

    /// As `makeAdapter`, typed as the ZenTao adapter (which also speaks the message / user-info extras).
    public static func makeZenTaoAdapter(account: Account, secret: String, session: URLSession? = nil) -> ZenTaoProviderAdapter? {
        guard account.providerType == .zentao, let base = account.baseUrl, !base.trimmingCharacters(in: .whitespaces).isEmpty else { return nil }
        return ZenTaoProviderAdapter(accountId: account.id,
                                     client: ZenTaoClient(baseUrl: base, account: account.handle, password: secret, session: session))
    }
}
