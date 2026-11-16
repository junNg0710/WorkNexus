/// Ported from: lib/features/workspace_overview/presentation/widgets/dashboard_body.dart
import CoreDomain
import CoreUI
import SwiftUI

/// A ZenTao account's dashboard on the Overview: My tasks beside My bugs (read from the ticket store), then
/// executions beside recent activity (from the stored dashboard, refreshed in the background when stale). Cards side
/// by side share a height; below `OverviewLayout.dashboardTwoColumnWidth` they stack.
struct DashboardBody: View {
    @Environment(\.appTheme) private var theme
    @State private var width: CGFloat = 0
    let model: OverviewModel
    let account: Account

    var body: some View {
        let dashboard = model.dashboard(account.id)
        let state = model.dashboardState[account.id] ?? .idle
        let failed = state.hasFailed
        let wide = width >= OverviewLayout.dashboardTwoColumnWidth
        VStack(alignment: .leading, spacing: theme.spacing.s16) {
            DashboardGrid(wide: wide, cells: [
                DashboardCell("tasks", DashboardQueue(model: model, account: account, kind: .task)),
                DashboardCell("bugs", DashboardQueue(model: model, account: account, kind: .bug)),
            ])
            if let dashboard {
                if failed { AppInlineNote(OL.dashboardRefreshFailed, isError: true) }
                DashboardGrid(wide: wide, cells: snapshotCells(dashboard))
            } else if failed {
                DashboardLoadError(model: model, account: account)
            } else {
                ProgressView().controlSize(.small).frame(maxWidth: .infinity).padding(theme.spacing.s16)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { width = $0 }
    }

    private func snapshotCells(_ d: ZenTaoDashboard) -> [DashboardCell] {
        var cells: [DashboardCell] = []
        if !d.executions.isEmpty { cells.append(DashboardCell("executions", DashboardExecutionsCard(model: model, account: account, dashboard: d))) }
        if !d.activities.isEmpty { cells.append(DashboardCell("activity", DashboardActivityCard(model: model, account: account, dashboard: d))) }
        if !d.todos.isEmpty { cells.append(DashboardCell("todos", DashboardTodosCard(model: model, account: account, dashboard: d))) }
        return cells
    }
}

/// The compact error shown when the dashboard has never loaded and the fetch failed.
private struct DashboardLoadError: View {
    @Environment(\.appTheme) private var theme
    let model: OverviewModel
    let account: Account

    var body: some View {
        VStack(spacing: theme.spacing.s8) {
            Text(OL.dashboardLoadFailed).font(theme.typography.meta).foregroundStyle(theme.colors.red)
            AppButton(OL.retry, systemImage: "arrow.clockwise") { Task { await model.loadDashboard(account.id, force: true) } }
        }
        .frame(maxWidth: .infinity).padding(theme.spacing.s16)
    }
}
