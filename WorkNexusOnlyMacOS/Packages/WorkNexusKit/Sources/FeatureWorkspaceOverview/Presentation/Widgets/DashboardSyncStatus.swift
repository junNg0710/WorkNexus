/// Ported from: lib/features/workspace_overview/presentation/widgets/dashboard_sync_status.dart
import CoreDomain
import CoreUI
import SwiftUI

/// When the account's dashboard was last fetched, and refresh - which fetches the dashboard and the assigned work
/// again.
struct DashboardSyncStatus: View {
    @Environment(\.appTheme) private var theme
    let model: OverviewModel
    let account: Account
    let fetchedAt: Date?

    var body: some View {
        let refreshing = (model.dashboardState[account.id]?.isLoading ?? false) || (model.workSyncState[account.id]?.isLoading ?? false)
        HStack(spacing: theme.spacing.s4) {
            if let fetchedAt {
                Text(OL.dashboardUpdated(formatWhen(fetchedAt, format: model.dateFormat)))
                    .font(theme.typography.caption).foregroundStyle(theme.colors.tx3).lineLimit(1)
            }
            if refreshing {
                ProgressView().controlSize(.small).frame(width: theme.sizes.control32, height: theme.sizes.control32)
            } else {
                AppIconButton("arrow.clockwise", help: OL.refresh) { Task { await model.refresh(account) } }
            }
        }
    }
}
