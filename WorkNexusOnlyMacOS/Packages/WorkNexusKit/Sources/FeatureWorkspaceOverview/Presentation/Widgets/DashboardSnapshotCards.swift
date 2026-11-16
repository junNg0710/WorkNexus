/// Ported from: lib/features/workspace_overview/presentation/widgets/dashboard_snapshot_cards.dart
import CoreDomain
import CoreTools
import CoreUI
import SwiftUI

/// The cards built from the stored ZenTao dashboard. Each shows only the first few items, so cards side by side stay
/// close in height and the Overview stays short; the count badge keeps the full total.

/// The ZenTao tool's Executions tab, which "Show all" opens.
private let executionsSection: SectionID = "zentao.sprints"

/// The few executions worth a glance (running, ending soonest), with "Show all" opening the ZenTao Executions tab.
struct DashboardExecutionsCard: View {
    let model: OverviewModel
    let account: Account
    let dashboard: ZenTaoDashboard

    var body: some View {
        let opensTab = model.registry.module(for: account.providerType)?.sections.contains { $0.id == executionsSection } ?? false
        DashboardCard(title: OL.dashboardSprints, systemImage: "rectangle.split.3x1", count: dashboard.executionTotal) {
            if opensTab {
                CardHeaderAction(title: OL.dashboardShowAll) { model.select(account, section: executionsSection) }
            }
        } content: {
            DashboardExecutionList(executions: RankDashboardExecutions()(dashboard.executions))
        }
    }
}

/// The latest few events on the account's ZenTao.
struct DashboardActivityCard: View {
    @Environment(\.appTheme) private var theme
    let model: OverviewModel
    let account: Account
    let dashboard: ZenTaoDashboard

    var body: some View {
        let s = theme.spacing
        DashboardCard(title: OL.dashboardActivity, systemImage: "clock.arrow.circlepath",
                      padding: EdgeInsets(top: s.s20, leading: s.s10, bottom: s.s6, trailing: s.s10)) {
            DashboardActivityList(model: model, account: account, activities: Array(dashboard.activities.prefix(OverviewLayout.activityRows)))
        }
    }
}

/// The user's first few personal todos.
struct DashboardTodosCard: View {
    @Environment(\.appTheme) private var theme
    let model: OverviewModel
    let account: Account
    let dashboard: ZenTaoDashboard

    var body: some View {
        let s = theme.spacing
        DashboardCard(title: OL.dashboardTodos, systemImage: "checklist.checked", count: dashboard.todoTotal,
                      padding: EdgeInsets(top: s.s10, leading: s.s6, bottom: s.s10, trailing: s.s6)) {
            DashboardWorkList(model: model, account: account, items: Array(dashboard.todos.prefix(OverviewLayout.activityRows)))
        }
    }
}
