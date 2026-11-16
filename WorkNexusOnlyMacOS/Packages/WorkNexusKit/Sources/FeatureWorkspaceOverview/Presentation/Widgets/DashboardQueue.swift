/// Ported from: lib/features/workspace_overview/presentation/widgets/dashboard_queue.dart
import CoreDomain
import CoreUI
import SwiftUI

/// The user's open tasks or open bugs of one account - in progress, then not started, the most urgent on top - with
/// "Show all" opening the full list in place of the Overview.
struct DashboardQueue: View {
    @Environment(\.appTheme) private var theme
    let model: OverviewModel
    let account: Account
    let kind: DashboardItemKind

    var body: some View {
        let bug = kind == .bug
        let queue = model.queue(account, kind)
        let sync = model.workSyncState[account.id] ?? .idle
        let s = theme.spacing
        DashboardCard(title: bug ? OL.dashboardMyBugs : OL.dashboardMyTasks, systemImage: bug ? "ladybug" : "checklist",
                      count: queue.count, padding: EdgeInsets(top: s.s8, leading: s.s6, bottom: s.s8, trailing: s.s6)) {
            CardHeaderAction(title: OL.dashboardShowAll) { model.myWorkTarget = MyWorkTarget(account: account, kind: kind) }
        } content: {
            VStack(alignment: .leading, spacing: 0) {
                if queue.isEmpty { QueueEmpty(model: model, account: account, sync: sync) }
                if !queue.inProgress.isEmpty {
                    QueueGroup(model: model, title: OL.dashboardInProgress, color: theme.colors.orange, tickets: queue.inProgress)
                }
                if !queue.notStarted.isEmpty {
                    QueueGroup(model: model, title: OL.dashboardNotStarted, color: theme.colors.accent, tickets: queue.notStarted)
                }
            }
        }
    }
}

private struct QueueEmpty: View {
    @Environment(\.appTheme) private var theme
    let model: OverviewModel
    let account: Account
    let sync: FetchState

    var body: some View {
        switch sync {
        case .loading:
            VStack(spacing: theme.spacing.s8) { ForEach(0..<3, id: \.self) { _ in SkeletonBox(height: theme.sizes.control32) } }
                .padding(theme.spacing.s8)
        case .failed:
            VStack(spacing: theme.spacing.s8) {
                Text(OL.dashboardWorkSyncFailed).font(theme.typography.meta).foregroundStyle(theme.colors.red)
                AppButton(OL.retry, systemImage: "arrow.clockwise") { Task { await model.syncMyWork(account.id, force: true) } }
            }
            .frame(maxWidth: .infinity).padding(theme.spacing.s12)
        case .idle:
            VStack(spacing: theme.spacing.s8) {
                Image(systemName: "checkmark.circle").font(.system(size: theme.sizes.icon24)).foregroundStyle(theme.colors.tx3)
                Text(OL.dashboardFocusEmpty).font(theme.typography.meta).foregroundStyle(theme.colors.tx3)
            }
            .frame(maxWidth: .infinity).padding(theme.spacing.s16)
        }
    }
}

private struct QueueGroup: View {
    @Environment(\.appTheme) private var theme
    let model: OverviewModel
    let title: String
    let color: Color
    let tickets: [Ticket]

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            DotSectionTitle(title: title, color: color, count: tickets.count)
                .padding(EdgeInsets(top: theme.spacing.s8, leading: theme.spacing.s8, bottom: theme.spacing.s4, trailing: theme.spacing.s8))
            ForEach(tickets.prefix(OverviewLayout.rowsPerGroup)) { MyWorkRow(model: model, ticket: $0, showStatus: false) }
        }
    }
}
