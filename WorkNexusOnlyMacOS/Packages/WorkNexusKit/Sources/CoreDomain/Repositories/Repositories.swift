import Foundation

/// Ported from: lib/core/domain/repositories/*.dart. `watch*` return `AsyncStream`s fed by DB observation (local-first).
public protocol TicketRepository: Sendable {
    func watchTickets() -> AsyncStream<[Ticket]>
    func ticket(id: String) async -> Outcome<Ticket?>
    func upsertTickets(_ tickets: [Ticket]) async -> Outcome<Void>
    func moveTicket(id: String, to status: UnifiedStatus) async -> Outcome<Void>
}

public protocol WorkspaceRepository: Sendable {
    func watchWorkspaces() -> AsyncStream<[Workspace]>
    func watchAccounts() -> AsyncStream<[Account]>
    func watchProjects() -> AsyncStream<[Project]>
    func createWorkspace(_ workspace: Workspace) async -> Outcome<Void>
    func updateWorkspace(_ workspace: Workspace) async -> Outcome<Void>
    func upsertAccount(_ account: Account) async -> Outcome<Void>
    func deleteAccount(id: String) async -> Outcome<Void>
    func upsertProjects(_ projects: [Project]) async -> Outcome<Void>
}

public protocol CommentRepository: Sendable {
    func watchComments(ticketId: String) -> AsyncStream<[Comment]>
    func upsertComments(_ comments: [Comment]) async -> Outcome<Void>
}

public protocol ActivityRepository: Sendable {
    func watchActivity(ticketId: String) -> AsyncStream<[ActivityEvent]>
    func upsertActivity(_ events: [ActivityEvent]) async -> Outcome<Void>
}

public protocol SyncStatusRepository: Sendable {
    func watch(accountId: String) -> AsyncStream<AccountSyncStatus>
    func status(accountId: String) async -> AccountSyncStatus
    func report(accountId: String, status: AccountSyncStatus)
}

/// Secret storage (lib/core/platform/credential_store.dart). Implemented over the Keychain in CorePersistence.
public protocol CredentialStore: Sendable {
    func read(_ key: String) async -> String?
    func write(_ key: String, value: String) async -> Outcome<Void>
    func delete(_ key: String) async -> Outcome<Void>
}

public enum CredentialKey {
    public static func accountSecret(_ accountId: String) -> String { "secret:\(accountId)" }
    public static let translationApi = "translation:api"
}
