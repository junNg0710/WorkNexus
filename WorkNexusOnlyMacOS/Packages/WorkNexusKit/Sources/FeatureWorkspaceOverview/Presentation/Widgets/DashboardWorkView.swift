/// Ported from: lib/features/workspace_overview/presentation/widgets/dashboard_work_view.dart
import CoreDomain
import CoreUI
import SwiftUI

/// Everything assigned to the user - the full lists behind the overview, under `DashboardWorkHeader`: tasks and bugs
/// side by side when there is room (`both`), else the one `kind` picked in the header. Reads the shared ticket store
/// (synced from ZenTao on open), so rows open straight in the detail panel. Open items by default.
struct DashboardWorkView: View {
    @Environment(\.appTheme) private var theme
    let model: OverviewModel
    let account: Account
    /// The list shown when only one fits.
    let kind: DashboardItemKind
    let both: Bool

    var body: some View {
        let failed = model.workSyncState[account.id]?.hasFailed ?? false
        VStack(alignment: .leading, spacing: theme.spacing.s16) {
            // The lists keep the last synced rows; the failure is said once above.
            if failed { AppInlineNote(OL.dashboardWorkSyncFailed, isError: true) }
            if both {
                HStack(alignment: .top, spacing: theme.spacing.s24) {
                    DashboardWorkColumn(model: model, account: account, kind: .task, showTitle: true)
                    DashboardWorkColumn(model: model, account: account, kind: .bug, showTitle: true)
                }
            } else {
                DashboardWorkColumn(model: model, account: account, kind: kind)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }
}
