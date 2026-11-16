/// Ported from: lib/features/workspace_overview/presentation/widgets/dashboard_work_header.dart
import CoreDomain
import CoreUI
import SwiftUI

/// The full lists' header: back to the Overview, open-only or everything, and refresh - plus, when only one list
/// fits (`both` is false), whether it shows tasks or bugs.
struct DashboardWorkHeader: View {
    @Environment(\.appTheme) private var theme
    let model: OverviewModel
    let account: Account
    let kind: DashboardItemKind
    let both: Bool

    var body: some View {
        let s = theme.spacing
        let syncing = model.workSyncState[account.id]?.isLoading ?? false
        FlowLayout(spacing: s.s20, lineSpacing: s.s10) {
            HStack(spacing: s.s8) {
                AppIconButton("arrow.left", help: OL.dashboardMyWork) { model.myWorkTarget = nil }
                Image(systemName: "tray").font(.system(size: theme.sizes.icon20)).foregroundStyle(theme.colors.tx2)
                Text(OL.dashboardMyWork).font(theme.typography.display).foregroundStyle(theme.colors.tx)
            }
            if !both {
                AppSegmentedTabs([
                    AppSegmentedTab(label: OL.dashboardTasksTab, active: kind == .task, count: count(.task, open: true)) { show(.task) },
                    AppSegmentedTab(label: OL.dashboardBugsTab, active: kind == .bug, count: count(.bug, open: true)) { show(.bug) },
                ])
            }
            AppSegmentedTabs([
                AppSegmentedTab(label: OL.dashboardOpenOnly, active: model.openOnly, count: total(open: true)) { model.openOnly = true },
                AppSegmentedTab(label: OL.dashboardAllItems, active: !model.openOnly, count: total(open: false)) { model.openOnly = false },
            ])
            if syncing {
                ProgressView().controlSize(.small).frame(width: theme.sizes.control32, height: theme.sizes.control32)
            } else {
                AppIconButton("arrow.clockwise", help: OL.refresh) { Task { await model.syncMyWork(account.id, force: true) } }
            }
        }
    }

    private func count(_ k: DashboardItemKind, open: Bool) -> Int { model.myWork(account, k, openOnly: open).count }

    /// Side by side, the open / all counts cover both lists.
    private func total(open: Bool) -> Int {
        both ? count(.task, open: open) + count(.bug, open: open) : count(kind, open: open)
    }

    private func show(_ k: DashboardItemKind) { model.myWorkTarget = MyWorkTarget(account: account, kind: k) }
}
