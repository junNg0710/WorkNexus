import CoreDomain
import Foundation
@testable import FeatureConnections

/// In-memory stand-ins for the repositories the connections model watches.
final class FakeWorkspaces: WorkspaceRepository, @unchecked Sendable {
    var workspaces: [Workspace]
    var accounts: [Account]
    init(workspaces: [Workspace] = [], accounts: [Account] = []) { self.workspaces = workspaces; self.accounts = accounts }
    func watchWorkspaces() -> AsyncStream<[Workspace]> { let w = workspaces; return AsyncStream { $0.yield(w) } }
    func watchAccounts() -> AsyncStream<[Account]> { let a = accounts; return AsyncStream { $0.yield(a) } }
    func watchProjects() -> AsyncStream<[Project]> { AsyncStream { $0.yield([]) } }
    func createWorkspace(_ workspace: Workspace) async -> Outcome<Void> { .success(()) }
    func updateWorkspace(_ workspace: Workspace) async -> Outcome<Void> { .success(()) }
    func upsertAccount(_ account: Account) async -> Outcome<Void> { .success(()) }
    func deleteAccount(id: String) async -> Outcome<Void> { .success(()) }
    func upsertProjects(_ projects: [Project]) async -> Outcome<Void> { .success(()) }
}

final class FakeTickets: TicketRepository, @unchecked Sendable {
    var tickets: [Ticket] = []
    func watchTickets() -> AsyncStream<[Ticket]> { let t = tickets; return AsyncStream { $0.yield(t) } }
    func ticket(id: String) async -> Outcome<Ticket?> { .success(nil) }
    func upsertTickets(_ tickets: [Ticket]) async -> Outcome<Void> { .success(()) }
    func moveTicket(id: String, to status: UnifiedStatus) async -> Outcome<Void> { .success(()) }
}

final class FakeCredentials: CredentialStore, @unchecked Sendable {
    var store: [String: String] = [:]
    func read(_ key: String) async -> String? { store[key] }
    func write(_ key: String, value: String) async -> Outcome<Void> { store[key] = value; return .success(()) }
    func delete(_ key: String) async -> Outcome<Void> { store[key] = nil; return .success(()) }
}

final class FakeSync: AccountSyncService, @unchecked Sendable {
    var result: Outcome<Void> = .success(())
    func sync(accountId: String) async -> Outcome<Void> { result }
    func adapter(for account: Account) async -> ProviderAdapter? { nil }
}

struct NoAdapters: ProviderAdapterRegistry {
    func createAdapter(account: Account, secret: String) -> ProviderAdapter? { nil }
}

final class RecordingConnections: ConnectionRepository, @unchecked Sendable {
    var removed: [String] = [], updated: [Workspace] = [], deleted: [String] = []
    var refsOnDelete: [String] = []
    func addAccount(_ account: Account) async -> Outcome<Void> { .success(()) }
    func removeAccount(id: String) async -> Outcome<Void> { removed.append(id); return .success(()) }
    func addWorkspace(_ workspace: Workspace) async -> Outcome<Void> { .success(()) }
    func updateWorkspace(_ workspace: Workspace) async -> Outcome<Void> { updated.append(workspace); return .success(()) }
    func deleteWorkspace(id: String) async -> Outcome<[String]> { deleted.append(id); return .success(refsOnDelete) }
}

final class RecordingCache: LocalCacheRepository, @unchecked Sendable {
    var cleared: [Set<CacheSection>] = []
    var failure: Failure?
    func clear(_ sections: Set<CacheSection>) async -> Outcome<Void> {
        if let failure { return .failure(failure) }
        cleared.append(sections); return .success(())
    }
}
