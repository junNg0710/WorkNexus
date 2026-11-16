import CoreDomain
import CoreUI
import Foundation

/// Ported from: lib/l10n/app_{en,vi}.arb (the keys the connections feature uses). Resolved through `appString`
/// (main-bundle `Localizable.xcstrings`), English text as fallback so tests and previews read correctly.
enum L {
    static var integrations: String { appString("integrations", "Integrations") }
    static var integrationsSubtitle: String {
        appString("connectionsSettingsSubtitle", "The same provider can be connected multiple times — one per company. Tasks assigned to you are pulled from every account below.")
    }
    static var connectATool: String { appString("connectATool", "Connect a tool") }
    static var whoCanConnect: String { appString("whoCanConnectTools", "Who can connect tools") }
    static func sharedByEveryone(_ workspace: String) -> String {
        String(format: appString("connectionsSharedByEveryone", "Connections are shared by everyone in %@."), workspace)
    }
    static var connectAndSync: String { appString("connectAndSync", "Connect & sync") }
    static var cancel: String { appString("cancel", "Cancel") }
    static var save: String { appString("save", "Save") }
    static var workspace: String { appString("workspace", "Workspace") }
    static var personal: String { appString("personal", "Personal") }
    static var newWorkspaceEntry: String { appString("newWorkspaceEntry", "New workspace…") }
    static var newWorkspaceName: String { appString("newWorkspaceName", "New workspace name") }
    static var newWorkspaceHint: String { appString("newWorkspaceHint", "e.g. Company C") }
    static var defaultWorkspaceName: String { appString("defaultWorkspaceName", "MyWorkspace") }
    static var serverUrl: String { appString("serverUrl", "Server URL") }
    static var username: String { appString("connectionsUsername", "Account (username)") }
    static var usernameHint: String { appString("connectionsUsernameHint", "your-username") }
    static var password: String { appString("connectionsPassword", "Password") }
    static var personalAccessToken: String { appString("personalAccessToken", "Personal Access Token") }
    static var generateToken: String { appString("generateToken", "Generate token") }

    static func connectTitle(_ p: ProviderType) -> String {
        switch p {
        case .zentao: appString("connectZenTao", "Connect ZenTao")
        case .github: appString("connectGitHub", "Connect GitHub")
        case .gitlab, .jira: appString("connectGitLab", "Connect GitLab")
        }
    }
    static func subtitle(_ p: ProviderType) -> String {
        switch p {
        case .zentao: appString("zentaoConnectionSubtitle", "Enter your ZenTao server URL and login. Your password is stored in the macOS Keychain — never in the local database.")
        case .github: appString("githubConnectionSubtitle", "Enter your GitHub server URL and a Personal Access Token. Your token is stored in the macOS Keychain — never in the local database.")
        case .gitlab, .jira: appString("gitlabConnectionSubtitle", "Enter your GitLab server URL and a Personal Access Token (scope: api). Your token is stored in the macOS Keychain — never in the local database.")
        }
    }
    static func serverHint(_ p: ProviderType) -> String {
        switch p {
        case .zentao: appString("zentaoServerHint", "https://host:port/zentao (include the subpath)")
        case .github: appString("githubServerHint", "https://github.com or your GitHub Enterprise URL")
        case .gitlab, .jira: appString("gitlabServerHint", "https://gitlab.com or your self-hosted URL")
        }
    }
    static func tokenHint(_ p: ProviderType) -> String {
        p == .github ? appString("githubTokenHint", "ghp_… (scopes: repo, read:org)") : appString("gitlabTokenHint", "glpat-… (scope: api)")
    }
    static func comingSoon(_ provider: String) -> String {
        String(format: appString("connectionsProviderComingSoon", "%@ support is coming soon"), provider)
    }

    // Errors of the connect flow (hardcoded English in the Flutter controller; keyed here).
    static var allFieldsRequired: String { appString("connectionsAllFieldsRequired", "All fields are required") }
    static var chooseWorkspace: String { appString("connectionsChooseWorkspace", "Choose or create a workspace") }
    static var connectionFailed: String { appString("connectionsConnectionFailed", "Connection failed") }
    static func connectedButSyncFailed(_ message: String) -> String {
        String(format: appString("connectionsConnectedSyncFailed", "Connected, but sync failed: %@"), message)
    }

    // Accounts list
    static func accountCount(_ n: Int) -> String {
        n == 1 ? appString("connectionsAccountCount.one", "1 account") : String(format: appString("connectionsAccountCount.other", "%d accounts"), n)
    }
    static var editWorkspace: String { appString("connectionsEditWorkspace", "Edit workspace") }
    static var deleteWorkspace: String { appString("connectionsDeleteWorkspace", "Delete workspace") }
    static var deleteWorkspaceTitle: String { appString("connectionsDeleteWorkspaceTitle", "Delete workspace?") }
    static func deleteWorkspaceMessage(_ n: Int) -> String {
        n == 1 ? appString("connectionsDeleteWorkspaceMessage.one", "This removes 1 account and the local synced data in this workspace.")
            : String(format: appString("connectionsDeleteWorkspaceMessage.other", "This removes %d accounts and the local synced data in this workspace."), n)
    }
    static var connected: String { appString("connected", "Connected") }
    static var syncNow: String { appString("connectionsSyncNow", "Sync now") }
    static var removeAccount: String { appString("connectionsRemoveAccount", "Remove account") }
    static func syncing(_ handle: String) -> String { String(format: appString("connectionsSyncing", "Syncing %@…"), handle) }
    static func synced(_ n: Int, _ handle: String) -> String {
        n == 1 ? String(format: appString("connectionsSynced.one", "Synced 1 ticket from %@"), handle)
            : String(format: appString("connectionsSynced.other", "Synced %d tickets from %@"), n, handle)
    }
    static func syncFailed(_ handle: String, _ message: String) -> String {
        String(format: appString("connectionsSyncFailed", "Couldn't sync %@: %@"), handle, message)
    }
    static func removeAccountTitle(_ handle: String) -> String { String(format: appString("connectionsRemoveAccountTitle", "Remove %@?"), handle) }
    static var removeAccountMessage: String {
        appString("connectionsRemoveAccountMessage", "This disconnects the account and deletes its saved credentials from this device.")
    }
    static var removeConfirm: String { appString("connectionsRemoveConfirm", "Remove") }

    // Workspace editor
    static var editTitle: String { appString("workspaceEditTitle", "Edit workspace") }
    static var createTitle: String { appString("createWorkspace", "Create workspace") }
    static var createAndJoin: String { appString("createAndJoinWorkspace", "Create & join") }
    static func createFailed(_ message: String) -> String {
        String(format: appString("workspaceCreateFailed", "Couldn't create the workspace: %1$@"), message)
    }
    static var workspaceSaveFailed: String { appString("workspaceSaveFailed", "Couldn't save the workspace.") }
    static var nameLabel: String { appString("workspaceNameLabel", "Name") }
    static var nameRequired: String { appString("workspaceNameRequired", "Enter a name") }
    static func nameTooLong(_ max: Int) -> String { String(format: appString("workspaceNameTooLong", "Use at most %d characters"), max) }
    static var codeLabel: String { appString("workspaceCodeLabel", "Badge letters") }
    static func codeTooLong(_ max: Int) -> String { String(format: appString("workspaceCodeTooLong", "Use at most %d badge letters"), max) }
    static var color: String { appString("connectionsColor", "Color") }
    static var icon: String { appString("connectionsIcon", "Icon") }
    static var customIconSelected: String { appString("connectionsCustomIconSelected", "Custom icon selected") }
    static var noFileSelected: String { appString("connectionsNoFileSelected", "No file selected") }
    static var chooseFile: String { appString("connectionsChooseFile", "Choose file") }
    static var removeCustomIcon: String { appString("connectionsRemoveCustomIcon", "Remove custom icon") }
    static var iconTooLarge: String { appString("connectionsIconTooLarge", "Icon file must be 256 KB or smaller.") }

    // Local cache
    static var cacheDbHint: String {
        appString("localCacheDbHint", "Copies of what your accounts sync, kept in this device's local database so the app opens fast and works offline. Clearing a part deletes only the local copy; it downloads again from your accounts.")
    }
    static var cacheKept: String { appString("clearCacheKept", "Accounts, workspaces, settings and saved filters are kept.") }
    static var clearConfirm: String { appString("clearCacheConfirm", "Clear") }
    static var cacheCleared: String { appString("cacheCleared", "Cache cleared, downloading again…") }
    static func cacheClearFailed(_ message: String) -> String {
        String(format: appString("connectionsCacheClearFailed", "Couldn't clear the local data: %@"), message)
    }
    static func cacheTitle(_ s: CacheSection) -> String {
        switch s {
        case .tickets: appString("cacheSectionTickets", "Tickets & board")
        case .dashboard: appString("cacheSectionDashboard", "Dashboard & notifications")
        case .chat: appString("cacheSectionChat", "Chat")
        case .translations: appString("cacheSectionTranslations", "Translations")
        }
    }
    static func cacheHint(_ s: CacheSection) -> String {
        switch s {
        case .tickets: appString("cacheSectionTicketsHint", "Tickets, comments, activity and projects")
        case .dashboard: appString("cacheSectionDashboardHint", "The dashboard, ZenTao notifications and profiles")
        case .chat: appString("cacheSectionChatHint", "Conversations, messages and contacts")
        case .translations: appString("cacheSectionTranslationsHint", "Saved translations; translating again calls the API")
        }
    }
}
