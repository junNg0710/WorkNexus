/// Ported from: lib/shared/sync/data/sync_coordinator.dart (rawClientFor / adapterFor, as the ZenTao services use them)
import CoreDomain
import Foundation

/// Finds accounts by id or ZenTao host (the Dart code read the accounts table directly).
public protocol ZenTaoAccountLookup: Sendable {
    func account(id: String) async -> Account?
    func zentaoAccounts() async -> [Account]
}

/// `ZenTaoAccountLookup` over the core `WorkspaceRepository` (its first `watchAccounts` value).
public struct WorkspaceZenTaoAccountLookup: ZenTaoAccountLookup {
    private let workspaces: WorkspaceRepository
    public init(_ workspaces: WorkspaceRepository) { self.workspaces = workspaces }

    private func all() async -> [Account] {
        var it = workspaces.watchAccounts().makeAsyncIterator()
        return await it.next() ?? []
    }
    public func account(id: String) async -> Account? { await all().first { $0.id == id } }
    public func zentaoAccounts() async -> [Account] { await all().filter { $0.providerType == .zentao } }
}

/// The pooled ZenTao client of an account (the Dart `SyncCoordinator.rawClientFor`): ZenTao invalidates the
/// previous session on every login, so services must share the sync's client instead of logging in on their own.
public protocol ZenTaoClientProvider: Sendable {
    func zenTaoClient(accountId: String) async -> ZenTaoClient?
}

/// The pooled adapter of an account, or nil when it has no stored credentials.
public protocol ZenTaoAdapterProvider: Sendable {
    func adapter(accountId: String) async -> ProviderAdapter?
}

/// Both providers over the core `AccountSyncService`'s adapter pool.
public struct PooledZenTaoAdapters: ZenTaoClientProvider, ZenTaoAdapterProvider {
    private let sync: AccountSyncService
    private let accounts: ZenTaoAccountLookup
    public init(sync: AccountSyncService, accounts: ZenTaoAccountLookup) { self.sync = sync; self.accounts = accounts }

    public func adapter(accountId: String) async -> ProviderAdapter? {
        guard let account = await accounts.account(id: accountId) else { return nil }
        return await sync.adapter(for: account)
    }

    public func zenTaoClient(accountId: String) async -> ZenTaoClient? {
        (await adapter(accountId: accountId) as? ZenTaoProviderAdapter)?.client
    }
}

extension ZenTaoError {
    /// `ZenTaoWorkflowActions._failureOf`: auth for 401/403, a validation failure when ZenTao answered but
    /// refused the action, else a network failure.
    var workflowFailure: Failure {
        switch self {
        case .http(let status, let message, let hasResponse):
            let code = status ?? 0
            if code == 401 || code == 403 { return .auth(message) }
            if hasResponse && code < 400 { return .validation(message) }
            return .network(message)
        case .cancelled: return .network("ZenTao request failed")
        case .connection(let m), .format(let m): return .network(m)
        }
    }
}
