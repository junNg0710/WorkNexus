import CoreDomain
import CoreUI
import SwiftUI

/// Ported from: lib/features/workspace_overview/presentation/pages/integrations_page.dart (the page body, with the
/// account list of lib/features/connections/.../active_workspace_accounts.dart)
/// The Integrations page of a workspace (design §5): its connected accounts, managed in place (sync, edit,
/// remove), a "Connect a tool" button opening the connect dialog, and a text-only info box on who can connect.
/// The page chrome (scroll, padding) belongs to the host; this is title row + content.
public struct IntegrationsContentView: View {
    @Environment(\.appTheme) private var theme
    @Environment(\.toasts) private var toasts
    @State private var connecting = false
    let model: ConnectionsModel
    let workspaceId: String?

    init(model: ConnectionsModel, workspaceId: String?) { self.model = model; self.workspaceId = workspaceId }

    public var body: some View {
        let c = theme.colors, s = theme.spacing
        let workspace = model.workspace(id: workspaceId) ?? (workspaceId == nil ? model.workspaces.first : nil)
        VStack(alignment: .leading, spacing: s.s24) {
            HStack(alignment: .top, spacing: s.s16) {
                VStack(alignment: .leading, spacing: s.s4) {
                    Text(L.integrations).font(theme.typography.title).foregroundStyle(c.tx)
                    Text(L.integrationsSubtitle).font(theme.typography.paragraph).foregroundStyle(c.tx2)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
                AppButton(L.connectATool, systemImage: "plus", kind: .primary) { connecting = true }
            }
            if let workspace { WorkspaceAccountsView(workspace: workspace, model: model) }
            WhoCanConnectInfoBox(workspaceName: workspace.map { $0.isPersonal ? L.personal : $0.name } ?? "")
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .task { model.start() }
        .appDialog(isPresented: $connecting) {
            ConnectAccountDialog(model: model, onClose: { connecting = false },
                                 onSyncWarning: { toasts?.show($0, kind: .warning) })
        }
    }
}

/// A text-only permission info box (no checkbox).
private struct WhoCanConnectInfoBox: View {
    @Environment(\.appTheme) private var theme
    let workspaceName: String

    var body: some View {
        let c = theme.colors
        VStack(alignment: .leading, spacing: theme.spacing.s8) {
            HStack(spacing: theme.spacing.s8) {
                Image(systemName: "info.circle").font(.system(size: theme.sizes.icon14)).foregroundStyle(c.tx2)
                Text(L.whoCanConnect).font(theme.typography.bodyStrong).foregroundStyle(c.tx)
            }
            Text(L.sharedByEveryone(workspaceName)).font(theme.typography.paragraph).foregroundStyle(c.tx2)
        }
        .padding(theme.spacing.s20).frame(maxWidth: .infinity, alignment: .leading)
        .background(c.panel, in: RoundedRectangle(cornerRadius: theme.radii.lg))
        .overlay(RoundedRectangle(cornerRadius: theme.radii.lg).stroke(c.line, lineWidth: theme.borders.hairline))
    }
}
