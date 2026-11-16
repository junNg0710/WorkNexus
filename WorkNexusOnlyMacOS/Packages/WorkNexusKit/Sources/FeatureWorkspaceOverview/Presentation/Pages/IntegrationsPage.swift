/// Ported from: lib/features/workspace_overview/presentation/pages/integrations_page.dart
import CoreUI
import SwiftUI

/// The Integrations page for the active workspace: its connected accounts, managed in place (sync, edit, remove), a
/// Connect Tool button, and a text-only permission info box.
///
/// The account list belongs to the connections feature, so the shell hands it in as the `accounts` slot.
struct IntegrationsPage<Accounts: View>: View {
    let workspaceName: String
    var onConnect: (() -> Void)?
    @ViewBuilder let accounts: Accounts

    var body: some View {
        PageFrame(title: OL.integrations, subtitle: OL.connectionsSettingsSubtitle) {
            AppButton(OL.connectATool, systemImage: "plus", kind: .primary) { onConnect?() }
        } content: {
            accounts
            WhoCanConnectInfoBox(workspaceName: workspaceName)
        }
    }
}

private struct WhoCanConnectInfoBox: View {
    @Environment(\.appTheme) private var theme
    let workspaceName: String

    var body: some View {
        CardSurface(fill: \.panel, padding: theme.spacing.s16) {
            VStack(alignment: .leading, spacing: theme.spacing.s8) {
                HStack(spacing: theme.spacing.s8) {
                    Image(systemName: "info.circle").font(.system(size: theme.sizes.icon16)).foregroundStyle(theme.colors.tx2)
                    Text(OL.whoCanConnectTools).font(theme.typography.bodyStrong).foregroundStyle(theme.colors.tx)
                }
                Text(OL.connectionsSharedByEveryone(workspaceName)).font(theme.typography.meta).foregroundStyle(theme.colors.tx2)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}
