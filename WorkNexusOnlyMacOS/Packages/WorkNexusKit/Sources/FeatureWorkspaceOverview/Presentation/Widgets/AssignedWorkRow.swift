/// Ported from: lib/features/workspace_overview/presentation/widgets/assigned_work_row.dart
import CoreDomain
import CoreUI
import SwiftUI

/// A single open assigned work row on the Workspace Overview: provider badge, monospace key, title, status pill and
/// relative time / due. Clicking it opens the detail slide-over.
struct AssignedWorkRow: View {
    @Environment(\.appTheme) private var theme
    let model: OverviewModel
    let item: AssignedWorkItem
    var now = Date()

    var body: some View {
        let c = theme.colors, t = theme.typography
        HoverSurface(onTap: { model.openTicket(item.ticketId) }, cornerRadius: theme.radii.sm) {
            HStack(spacing: theme.spacing.s8) {
                BrandLogoBadge(item.provider)
                Text(item.displayKey).font(t.mono.weight(.semibold)).foregroundStyle(c.tx2).lineLimit(1)
                    .frame(width: OverviewLayout.keyColumn, alignment: .leading)
                Text(item.title).font(t.meta).foregroundStyle(c.tx).lineLimit(1).frame(maxWidth: .infinity, alignment: .leading)
                TintedPill(item.statusLabel, tint: c.statusColor(item.status))
                AssignedTimeLabel(item: item, now: now)
            }
            .padding(.horizontal, theme.spacing.s10).padding(.vertical, theme.spacing.s8)
        }
    }
}

/// "Overdue Oct 12" / "Due Oct 12" when the item has a deadline, else when it last changed.
private struct AssignedTimeLabel: View {
    @Environment(\.appTheme) private var theme
    let item: AssignedWorkItem
    let now: Date

    var body: some View {
        let c = theme.colors
        if let due = item.due {
            let overdue = due < now
            Text(overdue ? OL.overdueRelative(monthDay(due)) : OL.dueRelative(monthDay(due)))
                .font(theme.typography.caption.weight(overdue ? .semibold : .regular))
                .foregroundStyle(overdue ? c.red : c.tx3).lineLimit(1)
                .frame(width: OverviewLayout.timeColumn, alignment: .trailing)
        } else {
            Text(shortWhen(item.updatedAt, now: now)).font(theme.typography.caption).foregroundStyle(c.tx3).lineLimit(1)
                .frame(width: OverviewLayout.timeColumn, alignment: .trailing)
        }
    }
}
