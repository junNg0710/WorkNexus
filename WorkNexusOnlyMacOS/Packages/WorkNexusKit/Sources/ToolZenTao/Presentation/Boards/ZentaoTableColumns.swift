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
         TicketTableColumn(id: "status", label: appString("status", "Status"), width: 160, sortField: .status) { t in
             let (label, color) = ZentaoColumnVisual.bug(zentaoBugColumnFor(t), palette)
             return AnyView(TableStatusCell(label, color))
         },
         TicketTableColumn(id: "resolution", label: appString("resolution", "Resolution"), width: 110, sortField: .resolution) { t in
             if case .zentaoBug(let b)? = t.providerEntity, let label = zentaoResolutionLabel(b.resolution) { return AnyView(TableTextCell(label)) }
             return AnyView(EmptyView())
         },
         TicketTableColumn(id: "due", label: appString("tableColumnDue", "Due"), width: 100, sortField: .deadline) { AnyView(ZentaoDueCell(ticket: $0)) }]
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
         TicketTableColumn(id: "hours", label: appString("tableColumnHours", "Left / est."), width: 90, sortField: .left) { AnyView(ZentaoHoursCell(ticket: $0)) },
         TicketTableColumn(id: "due", label: appString("tableColumnDue", "Due"), width: 100, sortField: .deadline) { AnyView(ZentaoDueCell(ticket: $0)) }]
    }

    /// `columns` without those that would be empty on every row (no bug resolved yet, nothing with a deadline, no
    /// sprint named): their room goes to the titles, which were cut short beside columns of blanks.
    @MainActor static func withoutEmpty(_ columns: [TicketTableColumn], rows: [Ticket]) -> [TicketTableColumn] {
        columns.filter { column in
            guard let filled = optional[column.id] else { return true }
            return rows.contains(where: filled)
        }
    }

    /// The columns that may be left out, with what makes a row fill them.
    @MainActor private static let optional: [String: (Ticket) -> Bool] = [
        "resolution": { if case .zentaoBug(let b)? = $0.providerEntity { zentaoResolutionLabel(b.resolution) != nil } else { false } },
        "due": { ZentaoFormatters.extractDeadline($0) != nil },
        "sprint": { if case .zentaoTask(let e)? = $0.providerEntity { e.executionName != nil } else { false } },
    ]

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

/// Hours left over the estimate of a task ("2 / 8 h").
struct ZentaoHoursCell: View {
    @Environment(\.appTheme) private var theme
    let ticket: Ticket
    var body: some View {
        if case .zentaoTask(let t)? = ticket.providerEntity, t.left != nil || t.estimate != nil {
            Text(verbatim: "\(zentaoHoursText(t.left ?? 0)) / \(zentaoHoursText(t.estimate ?? 0)) h").font(theme.typography.mono)
                .foregroundStyle(theme.colors.tx2).lineLimit(1)
        }
    }
}

/// The deadline of a ticket, in the error colour once it is late.
struct ZentaoDueCell: View {
    @Environment(\.appTheme) private var theme
    let ticket: Ticket
    var body: some View {
        if let d = ZentaoFormatters.extractDeadline(ticket) {
            let late = zentaoDeadlineState(ticket).isOverdue
            Text(ZentaoFormatters.formatDeadline(d)).font(theme.typography.mono)
                .foregroundStyle(late ? theme.colors.red : theme.colors.tx2).lineLimit(1)
        }
    }
}
