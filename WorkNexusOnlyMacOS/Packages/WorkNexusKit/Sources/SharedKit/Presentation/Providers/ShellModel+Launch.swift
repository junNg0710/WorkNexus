import CoreDomain
import CoreTools
import Foundation

/// What the shell does once its data has loaded: the default app, the chat at launch, and cleaning up after accounts that
/// went away (Flutter: `selectDefaultAppIfApplicable` in `AppShell`, `chat_at_launch.dart`, `onAccountRemoved`).
extension ShellModel {
    /// Called on every workspace / account list change; does nothing until both lists have loaded once.
    func reconcile() {
        guard loadedWorkspaces, loadedAccounts else { return }
        let ids = Set(accounts.map(\.id))
        if let before = knownAccountIds { for gone in before.subtracting(ids) { nav.onAccountRemoved(gone) } }
        knownAccountIds = ids
        nav.selectDefaultAppIfApplicable(accounts: workspaceAccounts)
        launchChatIfNeeded()
    }

    /// Opens the chat once at launch, as soon as a chat account is known — unless the user already went somewhere of their
    /// own: only the place the app picked by itself (the dashboard, or the first account the default selection opened) gives
    /// way.
    private func launchChatIfNeeded() {
        guard chatLaunchPending, chatAccount != nil else { return }
        chatLaunchPending = false
        guard opensChatAtLaunch, nav.editor == nil, nav.miniAppId == nil else { return }
        let first = Account.sort(workspaceAccounts).first
        let pickedByApp: Bool
        switch nav.rail {
        case .workspace: pickedByApp = !nav.userSelectedWorkspace
        case .account(let id): pickedByApp = id == first?.id
        case .chat, .settings: pickedByApp = false
        }
        if pickedByApp { nav.select(.chat) }
    }
}
