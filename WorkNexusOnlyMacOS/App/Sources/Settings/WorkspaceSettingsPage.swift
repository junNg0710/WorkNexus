import CoreDomain
import CoreUI
import FeatureConnections
import SharedKit
import SwiftUI

/// Ported from: lib/app/shell/workspace_settings_page.dart — the active workspace's name, badge letters, colour and icon.
/// Saves through `ConnectionsModel`; the badge preview follows what is picked.
struct WorkspaceSettingsPage: View {
    @Environment(\.appTheme) private var theme
    @Environment(\.toasts) private var toasts
    let shell: ShellModel
    let connections: ConnectionsFeature
    @State private var name = ""
    @State private var code = ""
    @State private var colorValue = 0
    @State private var iconKey = "briefcase"
    @State private var loadedId: String?

    var body: some View {
        SettingsPage(title: appString("workspaceSettings", "Workspace settings")) {
            if let ws = shell.workspace {
                SettingsCard(title: appString("workspaceDetails", "Details")) {
                    HStack(spacing: theme.spacing.s12) {
                        WorkspaceBadge(Color(argb: UInt32(truncatingIfNeeded: colorValue)), code.isEmpty ? ws.shortCode : code, big: true, iconKey: iconKey)
                        Text(ws.isPersonal ? appString("personalWorkspace", "Personal workspace") : ws.name).font(theme.typography.bodyStrong)
                    }
                    if !ws.isPersonal { SettingsTextField(label: appString("workspaceName", "Name"), text: $name, prompt: ws.name) }
                    SettingsTextField(label: appString("workspaceBadge", "Badge letters"), text: $code, prompt: ws.shortCode)
                    VStack(alignment: .leading, spacing: theme.spacing.s6) {
                        Text(appString("connectionsColor", "Color")).font(theme.typography.label).foregroundStyle(theme.colors.tx2)
                        HStack(spacing: theme.spacing.s6) {
                            ForEach(WorkspaceIcons.colorChoices, id: \.self) { v in
                                AppSwatchButton(size: theme.sizes.control32, color: Color(argb: v), selected: Int(v) == colorValue) { colorValue = Int(v) }
                            }
                        }
                    }
                    VStack(alignment: .leading, spacing: theme.spacing.s6) {
                        Text(appString("connectionsIcon", "Icon")).font(theme.typography.label).foregroundStyle(theme.colors.tx2)
                        HStack(spacing: theme.spacing.s6) {
                            ForEach(WorkspaceIcons.keys, id: \.self) { key in iconChip(key) }
                        }
                    }
                    AppButton(appString("save", "Save"), kind: .primary) { Task { await save(ws) } }
                }
            } else {
                AppStateView(.empty(appString("noWorkspace", "No workspace yet")))
            }
        }
        .task(id: shell.workspace?.id) {
            guard let ws = shell.workspace, loadedId != ws.id else { return }
            loadedId = ws.id; name = ws.name; code = ws.shortCode; colorValue = ws.colorValue; iconKey = ws.iconKey
        }
    }

    /// One built-in icon, outlined when it is the pick (a picked image icon is edited in the switcher's editor).
    private func iconChip(_ key: String) -> some View {
        let selected = key == iconKey
        return Button { iconKey = key } label: {
            Image(systemName: WorkspaceIcons.symbol(key) ?? "briefcase").font(.system(size: theme.sizes.icon16))
                .foregroundStyle(selected ? theme.colors.accent : theme.colors.tx2)
                .frame(width: theme.sizes.control32 + theme.spacing.s8, height: theme.sizes.control32)
                .background(selected ? theme.colors.sel : theme.colors.panel2, in: RoundedRectangle(cornerRadius: theme.radii.sm))
                .overlay(RoundedRectangle(cornerRadius: theme.radii.sm).stroke(selected ? theme.colors.accent : theme.colors.line, lineWidth: theme.borders.hairline))
        }
        .buttonStyle(.plain)
    }

    private func save(_ ws: Workspace) async {
        var edited = ws
        edited.colorValue = colorValue; edited.iconKey = iconKey
        switch RenameWorkspace()(WorkspaceRename(workspace: edited, name: name, shortCode: code)) {
        case .failure(let f): toasts?.show(f.message, kind: .error)
        case .success(let updated):
            if case .failure(let f) = await connections.model.save(updated) { toasts?.show(f.message, kind: .error) }
            else { toasts?.show(appString("saved", "Saved")) }
        }
    }
}
