import CoreDomain
import CoreTools
import CoreUI
import Foundation

/// The active workspace (Flutter: `activeWorkspaceProvider`, `sortedActiveAccountsProvider`, the switcher's `_selectWorkspace`)
/// and everything that follows it: the rail's accounts, the tool sections on the rail, the overview, sync scope.
extension ShellModel {
    /// The workspace in effect: the joined one, else the first (also when the joined one was deleted).
    public var workspace: Workspace? {
        workspaces.first { $0.id == activeWorkspaceId } ?? workspaces.first
    }

    /// The accounts of the active workspace, in provider order (all of them while no workspace has loaded).
    public var workspaceAccounts: [Account] {
        guard let ws = workspace else { return accounts }
        return accounts.filter { $0.workspaceId == ws.id }
    }

    /// Accounts that get their own rail button: those of the active workspace whose tool does *not* put its sections on the rail.
    public var railAccounts: [Account] {
        workspaceAccounts.filter { registry.module(for: $0.providerType)?.sectionsOnRail != true }
    }

    /// Tools whose sections sit on the rail and that have at least one account in the active workspace, in provider order.
    public var railSectionTools: [(module: any ToolModule, accounts: [Account])] {
        [ProviderType.zentao, .github, .gitlab, .jira].compactMap { p in
            guard let m = registry.module(for: p), m.sectionsOnRail else { return nil }
            let ofTool = workspaceAccounts.filter { $0.providerType == p }
            return ofTool.isEmpty ? nil : (m, ofTool)
        }
    }

    /// Opens `section` of a rail-section tool on the remembered (else first) account.
    /// The key of the nav pane of the place on screen (`AppNavController.collapsedPanes`): each place folds on its own.
    public var currentPaneKey: String {
        switch nav.state.rail {
        case .workspace: "workspace"
        case .settings: "settings"
        case .chat: "chat"
        case .account(let id): AppNavController.paneKey(id, nav.location(for: id).section)
        }
    }

    public var currentPaneFolded: Bool { nav.isPaneCollapsed(currentPaneKey) }

    /// Folds the nav pane of the place on screen away, or brings it back: what a second click on the place's rail button does.
    public func toggleCurrentPane() {
        let key = currentPaneKey
        nav.setPane(key, collapsed: !nav.isPaneCollapsed(key))
    }

    /// A click on a rail button: it goes to its place, or - when that place is the one on screen - folds / unfolds its pane.
    /// A click that also brought the app back from another app only shows the place: coming back to Chat must not fold its list.
    ///
    /// Clicked through faster than the places can be shown, only the last one is built: a place whose click has another
    /// rail click waiting behind it is skipped (`CatchUpGate`). The app used to build every one in turn, each for
    /// nothing, and stood still for seconds meanwhile.
    public func railTap(isCurrent: Bool, now: Date = Date(), go: @escaping () -> Void) {
        let bringsAppBack = now.timeIntervalSince(activatedAt) < Self.activationGrace
        if isCurrent && !miniAppOnScreen && !bringsAppBack {
            // Back on the place still on screen before the one asked for was built: that is where the user is; nothing folds.
            if railGate.hasPending { railGate.cancel() } else { toggleCurrentPane() }
        } else {
            railGate.run(go)
        }
    }

    /// How soon after the app came to the front a click still counts as the one that brought it back.
    public static let activationGrace: TimeInterval = 0.6

    public func openRailSection(_ section: SectionID, tool: any ToolModule, accounts ofTool: [Account]) {
        let id = railAccountMemory[tool.providerType].flatMap { r in ofTool.contains { $0.id == r } ? r : nil } ?? ofTool[0].id
        nav.select(.account(id))
        nav.setSection(section, accountId: id)
    }

    /// Remembers the open account for its provider and, when it belongs to another workspace (a chat notification, a chat
    /// picked from the list), joins that workspace: otherwise the default selection finds the account missing from the rail
    /// and jumps away (Dart `AppShell`'s rail listener). Called on every rail change.
    public func noteRail(_ rail: RailTarget) {
        guard case .account(let id) = rail, let a = account(id) else { return }
        railAccountMemory[a.providerType] = id
        if loadedWorkspaces, a.workspaceId != workspace?.id, workspaces.contains(where: { $0.id == a.workspaceId }) {
            setActiveWorkspace(a.workspaceId)
        }
    }

    /// The user picked a workspace in the switcher: it becomes the active one, every open ticket closes, and its first app opens
    /// (its dashboard when it has no account yet).
    public func switchWorkspace(_ id: String) {
        guard workspaces.contains(where: { $0.id == id }) else { return }
        setActiveWorkspace(id)
        nav.onWorkspaceSwitched(newAccounts: workspaceAccounts)
    }

    /// A workspace was just created: join it. It has no accounts yet, so the old workspace's tool gives way to its overview.
    public func workspaceCreated(_ workspace: Workspace) {
        setActiveWorkspace(workspace.id)
        nav.onWorkspaceSwitched(newAccounts: [])
    }

    func setActiveWorkspace(_ id: String?) {
        guard activeWorkspaceId != id else { return }
        activeWorkspaceId = id
        workspaceStore.save(id)
    }

    /// Keeps the per-account status streams in step with the account list.
    func accountsChanged() {
        let ids = Set(accounts.map(\.id))
        for id in statusTasks.keys where !ids.contains(id) { statusTasks[id]?.cancel(); statusTasks[id] = nil; syncStatuses[id] = nil }
        for id in ids where statusTasks[id] == nil {
            statusTasks[id] = Task { [weak self] in
                guard let s = self?.services.syncStatus.watch(accountId: id) else { return }
                for await v in s { self?.syncStatuses[id] = v }
            }
        }
    }

    /// The sync status of the account on screen's place (nil off an account).
    public func syncStatus(of accountId: String) -> AccountSyncStatus? { syncStatuses[accountId] }
}
