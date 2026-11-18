/// Ported from: lib/tools/zentao/presentation/detail/subtask_list.dart
import CoreDomain
import CoreUI
import SharedKit
import SwiftUI

/// A parent task's subtasks: its direct ones, each with its own subtasks folded under a chevron (ZenTao lists every level
/// flat). Tapping a row opens that subtask in the detail panel (fetched from ZenTao first when not synced).
public struct ZentaoSubtaskList: View {
    @Environment(\.appTheme) private var theme
    @Environment(\.toasts) private var toasts
    let deps: ZentaoDependencies; let ticket: Ticket; let subtasks: [TicketSubtask]
    /// The subtask being fetched to open, if any.
    @State private var opening: String?
    /// The subtasks whose own subtasks are showing; all folded at first.
    @State private var expanded: Set<String> = []

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

    private func toggle(_ id: String) {
        if expanded.contains(id) { expanded.remove(id) } else { expanded.insert(id) }
    }

    /// The header count: the direct subtasks, and all levels when some have their own.
    private func count(_ tree: SubtaskTree) -> String {
        let direct = tree.roots.count
        return tree.total > direct ? appFormat("subtaskCountNested", "%1$@ · %2$@ total", "\(direct)", "\(tree.total)") : "\(direct)"
    }

    public var body: some View {
        let tree = BuildSubtaskTree()(SubtaskTreeInput(parentId: ticket.externalKey, subtasks: subtasks))
        let rows = tree.visible(expanded: expanded)
        VStack(alignment: .leading, spacing: theme.spacing.s8) {
            SectionLabel("\(appString("subtasks", "Subtasks")) (\(count(tree)))")
            VStack(spacing: 0) {
                ForEach(Array(rows.enumerated()), id: \.element.node.subtask.id) { i, row in
                    let id = row.node.subtask.id
                    if i > 0 { Divider().overlay(theme.colors.line) }
                    ZentaoSubtaskRow(task: row.node.subtask, depth: row.depth, showToggle: tree.isNested,
                                     expanded: row.node.hasChildren ? expanded.contains(id) : nil,
                                     onToggle: { toggle(id) }, opening: opening == id) { if opening == nil { open(id) } }
                }
            }
            .overlay(RoundedRectangle(cornerRadius: theme.radii.md).stroke(theme.colors.line, lineWidth: theme.borders.hairline))
        }
        .onChange(of: ticket.id) { expanded = [] }
    }
}
