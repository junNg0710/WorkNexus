/// Ported from: lib/features/workspace_overview/presentation/widgets/zentao_overview_section.dart
import CoreDomain
import CoreUI
import SwiftUI

/// A ZenTao account's dashboard on the Overview, as one inset panel: a heading (logo, "ZenTao · account", sync
/// status) over My tasks / My bugs, then executions / recent activity. The account-wide numbers and the "Open ZenTao →"
/// button stay on its compact card in the row above. Shows what is stored at once; the assigned work syncs once per
/// session in the background and the dashboard refetches only when stale.
struct ZenTaoOverviewSection: View {
    @Environment(\.appTheme) private var theme
    let model: OverviewModel
    let account: Account

    var body: some View {
        if model.registry.module(for: account.providerType) != nil {
            CardSurface(fill: \.panel, padding: theme.spacing.s16) {
                VStack(alignment: .leading, spacing: theme.spacing.s16) {
                    ZenTaoSectionHeading(model: model, account: account)
                    DashboardBody(model: model, account: account)
                }
            }
            .task(id: account.id) { await model.prepare(account) }
        }
    }
}

/// Logo and "ZenTao · account" leading, sync status at the trailing edge.
private struct ZenTaoSectionHeading: View {
    @Environment(\.appTheme) private var theme
    let model: OverviewModel
    let account: Account

    var body: some View {
        HStack(spacing: theme.spacing.s10) {
            BrandLogoBadge(account.providerType, size: theme.sizes.control32)
            Text("\(account.providerType.displayName) · \(account.handle)")
                .font(theme.typography.titleSm).foregroundStyle(theme.colors.tx).lineLimit(1)
            Spacer(minLength: theme.spacing.s12)
            DashboardSyncStatus(model: model, account: account, fetchedAt: model.dashboard(account.id)?.fetchedAt)
        }
    }
}
