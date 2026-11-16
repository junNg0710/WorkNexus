import CoreDomain
import Foundation
import Observation

/// Ported from: lib/features/connections/presentation/widgets/{account_list,account_row}.dart (the actions) +
/// lib/core/di/providers.dart `lookupsProvider` (workspaces / accounts, local-first).
/// The connections state the views read: workspaces and accounts straight from the database streams, and the
/// commands on them (sync, remove, edit / delete workspace, clear cache). Built once by `ConnectionsFeature`.
@MainActor @Observable
public final class ConnectionsModel {
    public private(set) var workspaces: [Workspace] = []
    public private(set) var accounts: [Account] = []

    @ObservationIgnored private let workspaceRepo: WorkspaceRepository
    @ObservationIgnored private let tickets: TicketRepository
    @ObservationIgnored private let credentials: CredentialStore
    @ObservationIgnored private let sync: AccountSyncService
    @ObservationIgnored private let connections: ConnectionRepository
    @ObservationIgnored private let adapters: ProviderAdapterRegistry
    @ObservationIgnored private let clearCache: ClearLocalCache
    @ObservationIgnored private let connectAccount: ConnectAccount
    @ObservationIgnored private var tasks: [Task<Void, Never>] = []

    public init(workspaces: WorkspaceRepository, tickets: TicketRepository, credentials: CredentialStore, sync: AccountSyncService,
                adapters: ProviderAdapterRegistry, connections: ConnectionRepository, cache: LocalCacheRepository,
                afterAccountAdded: (@Sendable (Account) async -> Void)? = nil) {
        workspaceRepo = workspaces; self.tickets = tickets; self.credentials = credentials; self.sync = sync
        self.adapters = adapters; self.connections = connections
        clearCache = ClearLocalCache(cache)
        connectAccount = ConnectAccount(adapters: adapters, credentials: credentials, connections: connections,
                                        sync: sync, afterAdd: afterAccountAdded)
    }

    /// Starts following the workspaces and accounts; idempotent.
    public func start() {
        guard tasks.isEmpty else { return }
        let repo = workspaceRepo
        tasks.append(Task { [weak self] in for await v in repo.watchWorkspaces() { self?.workspaces = v } })
        tasks.append(Task { [weak self] in for await v in repo.watchAccounts() { self?.accounts = v } })
    }

    public func stop() { tasks.forEach { $0.cancel() }; tasks = [] }

    public func accounts(in workspaceId: String) -> [Account] { accounts.filter { $0.workspaceId == workspaceId } }
    public func workspace(id: String?) -> Workspace? { workspaces.first { $0.id == id } }

    // MARK: connect

    /// Runs the connect flow for the add-connection dialog.
    public func connect(_ request: ConnectRequest) async -> ConnectResult { await connectAccount(request) }

    // MARK: account actions

    public enum SyncReport: Equatable, Sendable { case synced(count: Int), failed(String) }

    /// Syncs one account now and says how many of its tickets are in the store afterwards.
    public func sync(_ account: Account) async -> SyncReport {
        switch await sync.sync(accountId: account.id) {
        case .failure(let f): return .failed(f.message)
        case .success:
            var count = 0
            for await all in tickets.watchTickets() { count = all.filter { $0.accountId == account.id }.count; break }
            return .synced(count: count)
        }
    }

    /// Removes the account and its saved credentials.
    public func remove(_ account: Account) async {
        _ = await connections.removeAccount(id: account.id)
        if let ref = account.credentialsRef { _ = await credentials.delete(ref) }
    }

    /// The server's version (GitLab shows it on the row), once the provider tells; nil for others / when unknown.
    public func serverVersion(of account: Account) async -> String? {
        guard account.providerType == .gitlab, let adapter = await sync.adapter(for: account) else { return nil }
        return await adapter.testConnection().value?.serverVersion
    }

    // MARK: workspace actions

    public func save(_ workspace: Workspace) async -> Outcome<Void> { await connections.updateWorkspace(workspace) }

    /// Creates `workspace` (it goes last in the list).
    public func create(_ workspace: Workspace) async -> Outcome<Void> { await connections.addWorkspace(workspace) }

    /// Deletes the workspace with everything synced into it and wipes its accounts' secrets.
    public func deleteWorkspace(id: String) async {
        guard case .success(let refs) = await connections.deleteWorkspace(id: id) else { return }
        for ref in refs { _ = await credentials.delete(ref) }
    }

    // MARK: local cache

    public func clear(_ sections: Set<CacheSection>) async -> Outcome<Void> { await clearCache(sections) }
}
