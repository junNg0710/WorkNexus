/// Ported from: lib/features/workspace_overview/presentation/pages/overview_page.dart
import CoreDomain
import CoreUI
import SwiftUI

/// The Workspace Overview page. Displays the connected tools as compact cards filling one row, then a dashboard
/// section per ZenTao account, then the open assigned work. "Show all" of a ZenTao section opens the account's full
/// lists in the Overview's place, until their back button (or a workspace without that account) brings it back.
struct OverviewPage: View {
    @Environment(\.appTheme) private var theme
    let model: OverviewModel
    var onConnect: (() -> Void)?

    var body: some View {
        if model.accounts.isEmpty {
            OverviewEmptyState(onConnect: onConnect ?? model.openIntegrations)
        } else if let target = model.myWorkTarget, let account = model.accounts.first(where: { $0.id == target.account.id }) {
            DashboardWorkPage(model: model, account: account, kind: target.kind)
        } else {
            // Every tool has a compact card in the top row; a ZenTao account also gets its dashboard below the row.
            PageFrame(title: OL.overview, subtitle: OL.overviewSubtitle(model.accounts.count, model.workspace?.name ?? "")) {
                AppButton(OL.manageIntegrations, kind: .ghost, action: model.openIntegrations)
            } content: {
                ToolCardGrid(model: model, accounts: model.accounts)
                ForEach(model.accounts.filter { $0.providerType == .zentao }) { ZenTaoOverviewSection(model: model, account: $0) }
                AssignedWorkList(model: model)
            }
        }
    }
}

/// "No tools connected yet" with the Connect button, centred on the page.
private struct OverviewEmptyState: View {
    @Environment(\.appTheme) private var theme
    let onConnect: () -> Void

    var body: some View {
        let c = theme.colors
        VStack(spacing: theme.spacing.s12) {
            Image(systemName: "powerplug").font(.system(size: theme.sizes.icon24)).foregroundStyle(c.tx2)
                .frame(width: OverviewLayout.stateTile, height: OverviewLayout.stateTile)
                .background(c.panel2, in: RoundedRectangle(cornerRadius: theme.radii.md))
            Text(OL.noConnectedAccounts).font(theme.typography.title).foregroundStyle(c.tx).multilineTextAlignment(.center)
            Text(OL.noConnectedAccountsDesc).font(theme.typography.paragraph).foregroundStyle(c.tx2).multilineTextAlignment(.center)
            AppButton(OL.connectATool, kind: .primary, action: onConnect).padding(.top, theme.spacing.s4)
        }
        .frame(maxWidth: OverviewLayout.stateMessageMax)
        .padding(theme.spacing.s40)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(c.bg)
    }
}
