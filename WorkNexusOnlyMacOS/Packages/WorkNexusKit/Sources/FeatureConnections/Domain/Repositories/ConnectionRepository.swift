import CoreDomain

/// Ported from: lib/features/connections/domain/repositories/connection_repository.dart
/// Persists provider connections (accounts) and workspaces. Secrets are handled separately by the credential
/// store; only the account metadata (incl. `credentialsRef`) lives here.
public protocol ConnectionRepository: Sendable {
    func addAccount(_ account: Account) async -> Outcome<Void>
    /// Removes the account with its projects, tickets and their comments / activity.
    func removeAccount(id: String) async -> Outcome<Void>
    /// Creates (or updates) a workspace, e.g. when connecting into a new one.
    func addWorkspace(_ workspace: Workspace) async -> Outcome<Void>
    func updateWorkspace(_ workspace: Workspace) async -> Outcome<Void>
    /// Deletes a workspace and everything synced into it; returns the credential refs to wipe from the keychain.
    func deleteWorkspace(id: String) async -> Outcome<[String]>
}
