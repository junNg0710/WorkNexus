import CoreDomain
import CoreTools
import CoreUI
import SwiftUI

/// Ported from: app/shell/tool_pane_host (300pt nav pane) + collapsible_pane.dart. Workspace → its own sections; account →
/// the tool's pane; chat → the account list (several ZenTao accounts only, the chat view has its own conversation list);
/// settings → sections.
///
/// Kept alive per place like the viewport's sections: the last 5 panes stay mounted, so going to Bugs and back to Docs finds
/// the column as it was left (scroll, filter, open branches). A tool whose pane is collapsible (`paneCollapsible`, ZenTao
/// docs) can fold it into a rail-wide strip with the collapse button of `ToolPaneScaffold`; it stays mounted while folded.
struct ToolPaneHost: View {
    @Environment(\.appTheme) private var theme
    let model: ShellModel

    /// Whether the pane takes any room: a mini app replaces it, and a lone chat account has nothing to pick.
    static func isVisible(_ model: ShellModel) -> Bool {
        if model.miniAppOnScreen { return false }
        if model.nav.state.rail == .chat { return model.chatAccounts.count > 1 }
        return true
    }

    private struct Place {
        var key: String
        var view: AnyView
        var collapse: CollapseInfo?
    }
    private struct CollapseInfo { var key: String; var icon: String; var label: String }

    var body: some View {
        let place = self.place
        let shown = Self.isVisible(model)
        let folded = shown && (place.collapse.map { model.nav.isPaneCollapsed($0.key) } ?? false)
        KeepAliveStack(activeKey: place.key, visible: shown && !folded, limit: Viewport.keepAliveLimit,
                       generation: model.activeWorkspaceId.hashValue, content: place.view)
            .frame(width: theme.sizes.toolPane)
            .frame(width: !shown ? 0 : (folded ? theme.sizes.rail : theme.sizes.toolPane), alignment: .leading)
            .clipped()
            .overlay(alignment: .top) {
                if folded, let info = place.collapse {
                    CollapsedPaneStrip(icon: info.icon, label: info.label) { model.nav.setPane(info.key, collapsed: false) }
                }
            }
    }

    private var place: Place {
        switch model.nav.state.rail {
        case .workspace: foldable("workspace", icon: "square.grid.2x2", label: appString("workspace", "Workspace"), WorkspacePane(model: model))
        case .settings: foldable("settings", icon: "gearshape", label: appString("settings", "Settings"), SettingsPane(model: model))
        case .chat: foldable("chat", icon: "bubble.left.and.bubble.right", label: appString("chat", "Chat"), ChatAccountsPane(model: model))
        case .account(let id): accountPlace(id)
        }
    }

    /// A pane every place can fold into the strip beside the rail, with a collapse button in its header.
    private func foldable<V: View>(_ key: String, icon: String, label: String, _ pane: V) -> Place {
        Place(key: key, view: AnyView(pane.paneCollapse { model.nav.setPane(key, collapsed: true) }),
              collapse: CollapseInfo(key: key, icon: icon, label: label))
    }

    private func accountPlace(_ id: String) -> Place {
        guard let a = model.account(id), let tool = model.registry.module(for: a.providerType) else {
            return Place(key: "account:\(id):none", view: AnyView(ToolPaneScaffold(title: appString("accounts", "Accounts")) {
                AppStateView(.empty(appString("noToolForAccount", "No tool for this account")))
            }))
        }
        let location = model.nav.location(for: id)
        let key = AppNavController.paneKey(id, location.section)
        let pane = tool.buildNavPane(account: a, location: location)
        guard tool.paneCollapsible(location: location), let section = tool.sections.first(where: { $0.id == location.section }) else {
            return Place(key: key, view: pane)
        }
        let view = pane.paneCollapse { model.nav.setPane(key, collapsed: true) }
        return Place(key: key, view: AnyView(view),
                     collapse: CollapseInfo(key: key, icon: section.systemImage, label: appString(section.label, section.label.capitalized)))
    }
}

/// What a folded pane leaves beside the rail: a strip as wide as the rail that names the place and opens the pane on a click.
private struct CollapsedPaneStrip: View {
    @Environment(\.appTheme) private var theme
    let icon: String
    let label: String
    let onExpand: () -> Void

    var body: some View {
        HoverSurface(onTap: onExpand, cornerRadius: theme.radii.sm) {
            VStack(spacing: theme.spacing.s4) {
                Image(systemName: icon).font(.system(size: theme.sizes.icon20)).foregroundStyle(theme.colors.tx2)
                Text(label).font(theme.typography.caption).foregroundStyle(theme.colors.tx2).lineLimit(2).multilineTextAlignment(.center)
                Image(systemName: AppPanelIcon.expand(.leading)).font(.system(size: theme.sizes.icon14)).foregroundStyle(theme.colors.tx3)
                    .padding(.top, theme.spacing.s4)
            }
            .frame(maxWidth: .infinity).padding(.vertical, theme.spacing.s8)
        }
        .help(appString("paneExpand", "Expand sidebar"))
        .padding(.horizontal, theme.spacing.s4).padding(.top, theme.sizes.titleBar - theme.spacing.s8)
        .frame(width: theme.sizes.rail)
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
                ForEach(ShellSections.settings, id: \.id) { r in
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
