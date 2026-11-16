import CoreDomain

/// Ported from: lib/features/connections/presentation/connection_controllers.dart (the arguments of
/// `connectZenTao` / `connectGitLab` / `connectGitHub`).
/// What the add-connection form submits. ZenTao signs in with `username` + password (`secret`); GitHub and GitLab
/// take a Personal Access Token as `secret` and learn the handle from the server. Provide EITHER `workspaceId`
/// (an existing workspace) OR `newWorkspaceName` (created on the way).
public struct ConnectRequest: Equatable, Sendable {
    public var provider: ProviderType
    public var baseUrl: String
    public var username: String
    public var secret: String
    public var workspaceId: String?
    public var newWorkspaceName: String?

    public init(provider: ProviderType, baseUrl: String, username: String = "", secret: String,
                workspaceId: String? = nil, newWorkspaceName: String? = nil) {
        self.provider = provider; self.baseUrl = baseUrl; self.username = username; self.secret = secret
        self.workspaceId = workspaceId; self.newWorkspaceName = newWorkspaceName
    }
}

/// Why a connect attempt did not go through; the UI words it in the user's language.
public enum ConnectIssue: Equatable, Sendable {
    case allFieldsRequired
    case noWorkspace
    case connectionFailed
    /// The provider said no (wrong password, unreachable server...), in its own words.
    case rejected(String)
}

public enum ConnectResult: Equatable, Sendable {
    /// Connected, saved and synced.
    case added(Account)
    /// Connected and saved, but the first sync failed (the account is kept; the error is surfaced).
    case addedButSyncFailed(Account, String)
    case failed(ConnectIssue)

    /// The account was saved (so the dialog can close), even if the first sync failed.
    public var accountAdded: Bool {
        switch self { case .added, .addedButSyncFailed: true; case .failed: false }
    }
}
