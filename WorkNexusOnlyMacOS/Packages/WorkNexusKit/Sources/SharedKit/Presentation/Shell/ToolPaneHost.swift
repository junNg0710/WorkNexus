import CoreDomain
import CoreTools
import CoreUI
import SwiftUI

/// Ported from: app/shell/tool_pane_host (300pt nav pane) + collapsible_pane.dart. Workspace → its own sections; account →
/// the tool's pane; chat → the account list (several ZenTao accounts only, the chat view has its own conversation list);
/// settings → sections.
///
/// Kept alive per place like the viewport's sections: the last 5 panes stay mounted, so going to Bugs and back to Docs finds
/// the column as it was left (scroll, filter, open branches). A second click on the place's rail button folds its pane away
/// (`ShellModel.toggleCurrentPane`) and the next brings it back; folded it takes no room at all and stays mounted.
struct ToolPaneHost: View {
    @Environment(\.appTheme) private var theme
    let model: ShellModel

    /// Whether the pane takes any room: a mini app replaces it, a lone chat account has nothing to pick, and a folded one is away.
    static func isVisible(_ model: ShellModel) -> Bool {
        if model.miniAppOnScreen { return false }
        if model.nav.state.rail == .chat, model.chatAccounts.count <= 1 { return false }
        return !model.currentPaneFolded
    }

    private struct Place {
        var key: String
        var view: AnyView
    }

    var body: some View {
        let place = self.place
        let shown = Self.isVisible(model)
        KeepAliveStack(activeKey: place.key, visible: shown, limit: Viewport.keepAliveLimit,
                       generation: model.activeWorkspaceId.hashValue, content: place.view)
            .frame(width: theme.sizes.toolPane)
            .frame(width: shown ? theme.sizes.toolPane : 0, alignment: .leading)
            .clipped()
    }

    private var place: Place {
        switch model.nav.state.rail {
        case .workspace: Place(key: "workspace", view: AnyView(WorkspacePane(model: model)))
        case .settings: Place(key: "settings", view: AnyView(SettingsPane(model: model)))
        case .chat: Place(key: "chat", view: AnyView(ChatAccountsPane(model: model)))
        case .account(let id): accountPlace(id)
        }
    }

    private func accountPlace(_ id: String) -> Place {
        guard let a = model.account(id), let tool = model.registry.module(for: a.providerType) else {
            return Place(key: "account:\(id):none", view: AnyView(ToolPaneScaffold(title: appString("accounts", "Accounts")) {
                AppStateView(.empty(appString("noToolForAccount", "No tool for this account")))
            }))
        }
        let location = model.nav.location(for: id)
        return Place(key: AppNavController.paneKey(id, location.section), view: tool.buildNavPane(account: a, location: location))
    }
}

private struct WorkspacePane: View {
    @Environment(\.appTheme) private var theme
    let model: ShellModel
    var body: some View {
        ToolPaneScaffold(title: appString("workspace", "Workspace"), subtitle: model.workspace?.name) {
            VStack(spacing: theme.spacing.s2) {
                ForEach(ShellSections.workspace, id: \.id) { r in
                    ScopeRow(title: appString(r.key, r.fallback), systemImage: r.icon,
                             selected: model.nav.state.workspaceSection == r.id,
                             trailing: r.id == "integrations" && !model.workspaceAccounts.isEmpty ? "\(model.workspaceAccounts.count)" : nil) {
                        model.nav.setWorkspaceSection(r.id)
                    }
                }
            }.padding(.top, theme.spacing.s8)
            Spacer()
        }
    }
}

private struct SettingsPane: View {
    @Environment(\.appTheme) private var theme
    let model: ShellModel
    var body: some View {
        ToolPaneScaffold(title: appString("settings", "Settings")) {
            VStack(spacing: theme.spacing.s2) {
                ForEach(ShellSections.settings.filter { model.host.settingsSectionVisible($0.id) }, id: \.id) { r in
                    ScopeRow(title: appString(r.key, r.fallback), systemImage: r.icon, selected: model.nav.state.settingsSection == r.id) {
                        model.nav.setSettingsSection(r.id)
                    }
                }
            }.padding(.top, theme.spacing.s8)
            Spacer()
        }
    }
}

private struct ChatAccountsPane: View {
    @Environment(\.appTheme) private var theme
    let model: ShellModel
    var body: some View {
        ToolPaneScaffold(title: appString("chat", "Chat")) {
            VStack(spacing: theme.spacing.s2) {
                ForEach(model.chatAccounts) { a in
                    ScopeRow(title: a.handle, systemImage: "bubble.left.and.bubble.right", selected: model.chatAccount?.id == a.id,
                             trailing: model.host.chatUnread(a.id) > 0 ? "\(model.host.chatUnread(a.id))" : nil) {
                        model.chatAccountId = a.id
                    }
                }
            }.padding(.top, theme.spacing.s8)
            Spacer()
        }
    }
}
