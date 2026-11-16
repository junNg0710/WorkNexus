/// Ported from: lib/tools/zentao/presentation/widgets/{zentao_bug_row,zentao_task_row,zentao_task_row_parts,
/// zentao_bug_table_view,zentao_task_table_view (headers)}.dart - the list layout's columns, as `TicketTableColumn`s of
/// the shared sortable / resizable table.
import CoreDomain
import CoreUI
import SharedKit
import SwiftUI

enum ZentaoTableColumns {
    /// ID, title, assignee, severity / priority, status, resolution.
    @MainActor static func bugs(palette: AppPalette) -> [TicketTableColumn] {
        [idColumn(), titleColumn(), assigneeColumn(),
         TicketTableColumn(id: "pri", label: "\(appString("severity", "Severity")) / \(appString("priority", "Priority"))", width: 110, sortField: .severity) {
             AnyView(ZentaoSeverityPriorityCell(ticket: $0))
         },
         TicketTableColumn(id: "status", label: appString("status", "Status"), width: 130, sortField: .status) { t in
             let (label, color) = ZentaoColumnVisual.bug(zentaoBugColumnFor(t), palette)
             return AnyView(TableStatusCell(label, color))
         },
         TicketTableColumn(id: "resolution", label: appString("resolution", "Resolution"), width: 110, sortField: .resolution) { t in
             if case .zentaoBug(let b)? = t.providerEntity, let label = zentaoResolutionLabel(b.resolution) { return AnyView(TableTextCell(label)) }
             return AnyView(EmptyView())
         }]
    }

    /// ID, title, assignee, sprint (execution), status, due.
    @MainActor static func tasks(palette: AppPalette) -> [TicketTableColumn] {
        [idColumn(), titleColumn(), assigneeColumn(),
         TicketTableColumn(id: "sprint", label: appString("tableColumnSprint", "Sprint"), width: 110) { t in
             if case .zentaoTask(let e)? = t.providerEntity, let name = e.executionName { return AnyView(TableTextCell(name)) }
             return AnyView(EmptyView())
         },
         TicketTableColumn(id: "status", label: appString("status", "Status"), width: 130, sortField: .status) { t in
             let (label, color) = ZentaoColumnVisual.task(zentaoTaskColumnFor(t), palette)
             return AnyView(TableStatusCell(label, color))
         },
         TicketTableColumn(id: "due", label: appString("tableColumnDue", "Due"), width: 100) { AnyView(ZentaoDueCell(ticket: $0)) }]
    }

    private static func idColumn() -> TicketTableColumn {
        TicketTableColumn(id: "id", label: appString("tableColumnId", "ID"), width: 80, sortField: .id) { AnyView(TableIdCell($0)) }
    }
    private static func titleColumn() -> TicketTableColumn {
        TicketTableColumn(id: "title", label: appString("tableColumnTitle", "Title"), sortField: .title) { AnyView(ZentaoTitleCell(ticket: $0)) }
    }
    private static func assigneeColumn() -> TicketTableColumn {
        TicketTableColumn(id: "assignee", label: appString("assignedTo", "Assigned to"), width: 160, sortField: .assignee) { AnyView(TableAssigneeCell($0)) }
    }
}

/// The title of a row without its bracketed tags, with the copy actions in its context menu and a quick copy-title
/// button while the pointer is over it.
struct ZentaoTitleCell: View {
    @Environment(\.appTheme) private var theme
    let ticket: Ticket
    var body: some View {
        let (title, tags) = ZentaoFormatters.extractTags(ticket.title)
        HoverRegion { hovered in
            HStack(spacing: theme.spacing.s6) {
                Text(title).font(theme.typography.paragraph).foregroundStyle(theme.colors.tx).lineLimit(1)
                ForEach(tags.prefix(2), id: \.self) { MiniTag($0, theme.colors.accent) }
                if hovered { ZentaoRowQuickCopyButton(ticket: ticket) }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .zentaoRowContextMenu(ticket: ticket)
    }
}

struct ZentaoSeverityPriorityCell: View {
    @Environment(\.appTheme) private var theme
    let ticket: Ticket
    var body: some View {
        HStack(spacing: theme.spacing.s4) {
            if let s = ticket.severity { SeverityTag(s) }
            if hasExplicitPriority(ticket) { ZentaoPriorityBadge(ticket.priority, size: 18) }
        }
    }
}

/// The deadline of a task, in the error colour once it is late.
struct ZentaoDueCell: View {
    @Environment(\.appTheme) private var theme
    let ticket: Ticket
    var body: some View {
        if let d = ZentaoFormatters.extractDeadline(ticket) {
            let late = ZentaoFormatters.delayText(d) != nil && ticket.status != .done
            Text(ZentaoFormatters.formatDeadline(d)).font(theme.typography.mono)
                .foregroundStyle(late ? theme.colors.red : theme.colors.tx2).lineLimit(1)
        }
    }
}
