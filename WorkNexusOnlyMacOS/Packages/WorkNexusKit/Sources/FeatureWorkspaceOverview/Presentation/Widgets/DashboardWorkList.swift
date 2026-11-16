/// Ported from: lib/features/workspace_overview/presentation/widgets/dashboard_work_list.dart
import CoreDomain
import CoreUI
import SwiftUI

/// The rows of a "my work" card. Tickets open in the detail panel.
struct DashboardWorkList: View {
    @Environment(\.appTheme) private var theme
    @Environment(\.toasts) private var toasts
    let model: OverviewModel
    let account: Account
    let items: [ZenTaoDashboardWorkItem]

    var body: some View {
        let c = theme.colors
        VStack(spacing: 0) {
            ForEach(items) { item in
                DashboardRow(title: item.title, subtitle: item.context, onTap: item.kind.isTicket ? { open(item) } : nil) {
                    ZenTaoKindIcon(item.kind.rawValue)
                } trailing: {
                    if let due = item.deadline { MyWorkDueFact(due: due) }
                    if let pri = item.priority, pri > 0 { PriorityTag(.zentao, Priority.fromLevel(pri - 1)) }
                    if let status = item.status {
                        TintedPill(item.statusLabel ?? zentaoStatusWord(status, execution: false),
                                   tint: dashboardStatusColor(c, status, bug: item.kind == .bug))
                    }
                }
            }
        }
    }

    private func open(_ item: ZenTaoDashboardWorkItem) {
        Task { await model.open(account, kind: item.kind, id: item.id, toasts: toasts) }
    }
}
