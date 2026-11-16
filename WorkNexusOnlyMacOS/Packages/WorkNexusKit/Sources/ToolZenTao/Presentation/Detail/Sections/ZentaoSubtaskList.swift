/// Ported from: lib/tools/zentao/presentation/detail/subtask_list.dart
import CoreDomain
import CoreUI
import SharedKit
import SwiftUI

/// A parent task's subtasks: id, name, assignee and status; tapping one opens it in the detail panel (fetched from
/// ZenTao first when not synced).
public struct ZentaoSubtaskList: View {
    @Environment(\.appTheme) private var theme
    @Environment(\.toasts) private var toasts
    let deps: ZentaoDependencies; let ticket: Ticket; let subtasks: [TicketSubtask]
    /// The subtask being fetched to open, if any.
    @State private var opening: String?

    public init(deps: ZentaoDependencies, ticket: Ticket, subtasks: [TicketSubtask]) {
        self.deps = deps; self.ticket = ticket; self.subtasks = subtasks
    }

    private func open(_ id: String) {
        opening = id
        Task {
            let r = await deps.openLinked(from: ticket, type: "task", id: id)
            opening = nil
            if case .failure(let f) = r { toasts?.show(appFormat("actionFailed", "Failed: %1$@", f.message), kind: .error) }
        }
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: theme.spacing.s8) {
            SectionLabel("\(appString("subtasks", "Subtasks")) (\(subtasks.count))")
            VStack(spacing: 0) {
                ForEach(Array(subtasks.enumerated()), id: \.element.id) { i, t in
                    if i > 0 { Divider().overlay(theme.colors.line) }
                    ZentaoSubtaskRow(task: t, opening: opening == t.id) { if opening == nil { open(t.id) } }
                }
            }
            .overlay(RoundedRectangle(cornerRadius: theme.radii.md).stroke(theme.colors.line, lineWidth: theme.borders.hairline))
        }
    }
}

private struct ZentaoSubtaskRow: View {
    @Environment(\.appTheme) private var theme
    let task: TicketSubtask; let opening: Bool; let onTap: () -> Void
    var body: some View {
        let c = theme.colors
        HoverSurface(onTap: onTap, cornerRadius: 0) {
            HStack(spacing: theme.spacing.s12) {
                Text("#\(task.id)").font(theme.typography.mono).foregroundStyle(c.tx2)
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
