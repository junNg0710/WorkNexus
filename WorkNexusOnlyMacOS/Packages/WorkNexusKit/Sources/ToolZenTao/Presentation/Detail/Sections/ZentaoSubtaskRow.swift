/// Ported from: lib/tools/zentao/presentation/detail/subtask_row.dart
import CoreDomain
import CoreUI
import SwiftUI

/// One row of `ZentaoSubtaskList`: id, name, assignee and status, indented `depth` levels. With `showToggle`, a leading
/// slot holds the expand chevron when the subtask has its own subtasks (`expanded` non-nil), so rows at one depth line up
/// whether or not they have children.
struct ZentaoSubtaskRow: View {
    @Environment(\.appTheme) private var theme
    let task: TicketSubtask
    var depth = 0
    var showToggle = false
    var expanded: Bool?
    var onToggle: () -> Void = {}
    let opening: Bool
    let onTap: () -> Void

    var body: some View {
        let c = theme.colors
        // A level sits one chevron slot further in, so a child's chevron lines up under its parent's id.
        let toggleSlot = theme.sizes.icon12 + theme.spacing.s2 * 2
        HoverSurface(onTap: onTap, cornerRadius: 0) {
            HStack(spacing: theme.spacing.s12) {
                if showToggle {
                    HStack(spacing: theme.spacing.s8) {
                        Color.clear.frame(width: CGFloat(depth) * (toggleSlot + theme.spacing.s8), height: 0)
                        if let expanded { SubtaskToggle(expanded: expanded, onTap: onToggle) }
                        else { Color.clear.frame(width: toggleSlot, height: 0) }
                    }
                }
                Text(verbatim: "#\(task.id)").font(theme.typography.mono).foregroundStyle(c.tx2)
                Text(task.title).font(theme.typography.metaStrong).foregroundStyle(c.accent).lineLimit(1).frame(maxWidth: .infinity, alignment: .leading)
                if let a = task.assignee { Text(a).font(theme.typography.caption).foregroundStyle(c.tx2) }
                TintedPill(statusLabel(task.status), tint: c.statusColor(task.status))
                if opening { ProgressView().controlSize(.mini) }
                else { Image(systemName: "chevron.right").font(.system(size: theme.sizes.icon12)).foregroundStyle(c.tx3) }
            }
            .padding(.horizontal, theme.spacing.s12).padding(.vertical, theme.spacing.s10)
        }
    }
}

/// Shows or hides a subtask's own subtasks; clicking it never opens the row.
private struct SubtaskToggle: View {
    @Environment(\.appTheme) private var theme
    @State private var hovering = false
    let expanded: Bool; let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            Image(systemName: expanded ? "chevron.down" : "chevron.right")
                .font(.system(size: theme.sizes.icon12)).foregroundStyle(hovering ? theme.colors.tx : theme.colors.tx3)
                .frame(width: theme.sizes.icon12, height: theme.sizes.icon12)
                .padding(theme.spacing.s2)
                .background(hovering ? theme.colors.tx.opacity(0.08) : .clear, in: Circle())
                .contentShape(Circle())
        }
        .buttonStyle(.plain).onHover { hovering = $0 }
        .help(expanded ? appString("subtaskCollapse", "Hide subtasks") : appString("subtaskExpand", "Show subtasks"))
        .accessibilityLabel(expanded ? appString("subtaskCollapse", "Hide subtasks") : appString("subtaskExpand", "Show subtasks"))
    }
}
