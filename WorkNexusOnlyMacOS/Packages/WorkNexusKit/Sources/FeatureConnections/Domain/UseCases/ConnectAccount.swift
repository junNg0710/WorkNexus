import CoreDomain
import Foundation

/// Ported from: lib/features/connections/presentation/connection_controllers.dart (`AddConnectionController.connectZenTao /
/// connectGitLab / connectGitHub`, one flow for the three providers).
///
/// Probes the connection through `ProviderAdapterRegistry` (the check resolves the real web root for ZenTao, the
/// authenticated handle for GitHub / GitLab), stores the secret in the credential store under
/// `secret:{accountId}`, persists the account and runs the first sync. A failed first sync keeps the account.
/// `afterAdd` is the composition root's hook for provider extras (e.g. refreshing the ZenTao profile).
public struct ConnectAccount: Sendable {
    private let adapters: ProviderAdapterRegistry
    private let credentials: CredentialStore
    private let connections: ConnectionRepository
    private let sync: AccountSyncService
    private let afterAdd: (@Sendable (Account) async -> Void)?

    public init(adapters: ProviderAdapterRegistry, credentials: CredentialStore, connections: ConnectionRepository,
                sync: AccountSyncService, afterAdd: (@Sendable (Account) async -> Void)? = nil) {
        self.adapters = adapters; self.credentials = credentials; self.connections = connections
        self.sync = sync; self.afterAdd = afterAdd
    }

    public func callAsFunction(_ r: ConnectRequest) async -> ConnectResult {
        guard r.provider != .jira else { return .failed(.connectionFailed) }
        let isZenTao = r.provider == .zentao
        let missingFields = r.baseUrl.trimmed.isEmpty
            || (isZenTao ? (r.username.trimmed.isEmpty || r.secret.isEmpty) : r.secret.trimmed.isEmpty)
        if missingFields { return .failed(.allFieldsRequired) }

        guard let workspaceId = await resolveWorkspaceId(r.workspaceId, r.newWorkspaceName) else {
            return .failed(.noWorkspace)
        }

        // Probe first. The probe's own id is irrelevant.
        let probe = Account(id: "\(r.provider.rawValue)-probe", workspaceId: workspaceId, providerType: r.provider,
                            handle: isZenTao ? r.username.trimmed : "", baseUrl: r.baseUrl.trimmed)
        guard let adapter = adapters.createAdapter(account: probe, secret: r.secret) else {
            return .failed(.rejected("\(r.provider.displayName) is not supported"))
        }
        let check: ConnectionCheck
        switch await adapter.testConnection() {
        case .failure(let f): return .failed(.rejected(f.message))
        case .success(let v):
            if !v.ok { return .failed(v.error.map(ConnectIssue.rejected) ?? .connectionFailed) }
            check = v
        }

        let handle: String, baseUrl: String, idUrl: String
        if isZenTao {
            // Users may omit the `/zentao` suffix: the resolved web root is what gets stored and hashed.
            handle = r.username.trimmed
            baseUrl = check.baseUrl ?? r.baseUrl.trimmed
            idUrl = baseUrl
        } else {
            let fallback = r.provider == .gitlab ? "gitlab" : "github"
            handle = (check.account ?? "").isEmpty ? fallback : check.account!
            baseUrl = r.baseUrl.trimmed
            idUrl = r.baseUrl   // GitHub / GitLab hash the URL as typed (untrimmed), as the Flutter app does.
        }
        let accountId = ConnectionIdentity.accountId(provider: r.provider, username: handle, baseUrl: idUrl)
        let credRef = CredentialKey.accountSecret(accountId)
        let account = Account(id: accountId, workspaceId: workspaceId, providerType: r.provider, handle: handle,
                              baseUrl: baseUrl, credentialsRef: credRef)

        if case .failure(let f) = await credentials.write(credRef, value: r.secret) { return .failed(.rejected(f.message)) }
        if case .failure(let f) = await connections.addAccount(account) { return .failed(.rejected(f.message)) }
        await afterAdd?(account)
        switch await sync.sync(accountId: account.id) {
        case .failure(let f): return .addedButSyncFailed(account, f.message)
        case .success: return .added(account)
        }
    }

    /// The target workspace id, creating a new workspace when `newName` is given; nil when neither an existing id
    /// nor a new name was provided.
    private func resolveWorkspaceId(_ workspaceId: String?, _ newName: String?) async -> String? {
        let name = (newName ?? "").trimmed
        if !name.isEmpty {
            let id = ConnectionIdentity.workspaceId(name: name)
            _ = await connections.addWorkspace(Workspace(id: id, name: name, shortCode: ConnectionIdentity.initials(name),
                                                         colorValue: ConnectionIdentity.pickColor(name)))
            return id
        }
        if let workspaceId, !workspaceId.isEmpty { return workspaceId }
        return nil
    }
}

extension String {
    var trimmed: String { trimmingCharacters(in: .whitespacesAndNewlines) }
}
