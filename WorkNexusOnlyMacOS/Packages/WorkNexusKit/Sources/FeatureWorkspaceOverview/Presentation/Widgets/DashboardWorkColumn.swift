/// Ported from: lib/features/workspace_overview/presentation/widgets/dashboard_work_column.dart
import CoreDomain
import CoreUI
import SwiftUI

/// Every task or every bug assigned to the user, in status sections (in progress first, finished last), scrolling on
/// its own. `showTitle` names the list above it - needed when tasks and bugs sit side by side.
struct DashboardWorkColumn: View {
    @Environment(\.appTheme) private var theme
    let model: OverviewModel
    let account: Account
    let kind: DashboardItemKind
    var showTitle = false

    var body: some View {
        let sync = model.workSyncState[account.id] ?? .idle
        let tickets = model.myWork(account, kind, openOnly: model.openOnly)
        let groups = GroupMyWork()(tickets)
        VStack(alignment: .leading, spacing: theme.spacing.s16) {
            if showTitle { WorkColumnTitle(kind: kind, count: tickets.count) }
            if !groups.isEmpty {
                ScrollView {
                    LazyVStack(spacing: theme.spacing.s24) {
                        ForEach(groups) { WorkStatusSection(model: model, group: $0, bug: kind == .bug) }
                    }
                }
            } else if sync.isLoading {
                AppStateView(.loading)
            } else if sync.hasFailed {
                AppStateView(.error(OL.dashboardWorkSyncFailed)) { Task { await model.syncMyWork(account.id, force: true) } }
            } else {
                WorkColumnEmpty(text: model.openOnly ? OL.dashboardFocusEmpty : OL.dashboardWorkEmptyAll)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }
}

/// "Tasks 2" / "Bugs 1" over a column.
private struct WorkColumnTitle: View {
    @Environment(\.appTheme) private var theme
    let kind: DashboardItemKind
    let count: Int

    var body: some View {
        HStack(spacing: theme.spacing.s8) {
            ZenTaoKindIcon(kind.rawValue)
            Text(kind == .bug ? OL.dashboardBugsTab : OL.dashboardTasksTab).font(theme.typography.titleSm).foregroundStyle(theme.colors.tx)
            AppCountBadge(count)
        }
    }
}

private struct WorkColumnEmpty: View {
    @Environment(\.appTheme) private var theme
    let text: String

    var body: some View {
        VStack(spacing: theme.spacing.s8) {
            Image(systemName: "checkmark.circle").font(.system(size: theme.sizes.icon24)).foregroundStyle(theme.colors.tx3)
            Text(text).font(theme.typography.meta).foregroundStyle(theme.colors.tx3)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

/// One status section: its dot, name and count over a card of rows.
private struct WorkStatusSection: View {
    @Environment(\.appTheme) private var theme
    let model: OverviewModel
    let group: MyWorkGroup
    let bug: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: theme.spacing.s8) {
            DotSectionTitle(title: myWorkStatusLabel(group.status, bug: bug), color: theme.colors.statusColor(group.status),
                            count: group.tickets.count)
                .padding(.horizontal, theme.spacing.s4)
            CardSurface(fill: \.panel, padding: theme.spacing.s4) {
                VStack(spacing: 0) {
                    ForEach(Array(group.tickets.enumerated()), id: \.element.id) { i, ticket in
                        if i > 0 { Divider().overlay(theme.colors.line).padding(.leading, theme.spacing.s40) }
                        MyWorkRow(model: model, ticket: ticket, showStatus: false)
                    }
                }
            }
        }
    }
}
