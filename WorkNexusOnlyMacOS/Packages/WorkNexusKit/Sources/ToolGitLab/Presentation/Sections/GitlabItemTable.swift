import CoreDomain
import CoreUI
import SharedKit
import SwiftUI

/// Ported from: lib/tools/gitlab/presentation/widgets/gitlab_mr_table.dart + gitlab_mr_table_row.dart (+ the issue rows of
/// gitlab_issues_section.dart). The list view as a sortable `TicketTable`: `!key` / `#key`, title, state, updated.
struct GitlabItemTable: View {
    let model: GitlabSectionModel
    let rows: [Ticket]
    let sort: TicketSort
    let onSort: (TicketSortField) -> Void

    private var isMr: Bool { model.kind == .mergeRequest }

    private var columns: [TicketTableColumn] {
        let dateFormat = model.board.settings.dateFormat
        let isMr = isMr
        return [
            TicketTableColumn(id: "key", label: isMr ? appString("gitlabColMr", "MR") : appString("githubColIssue", "Issue"),
                              width: 80, sortField: .id) { AnyView(GitlabKeyCell(ticket: $0, prefix: isMr ? "!" : "#")) },
            TicketTableColumn(id: "title", label: appString("title", "Title"), sortField: .title) { AnyView(TableTitleCell($0)) },
            TicketTableColumn(id: "state", label: appString("status", "State"), width: 120, sortField: .status) { AnyView(GitlabStateCell(ticket: $0)) },
            TicketTableColumn(id: "updated", label: appString("updated", "Updated"), width: 110, alignEnd: true, sortField: .updated) {
                AnyView(TableUpdatedCell($0, dateFormat: dateFormat))
            },
        ]
    }

    var body: some View {
        TicketTable(id: isMr ? "gitlab.mrs" : "gitlab.issues", columns: columns, rows: rows, controller: model.board, sort: sort, onSort: onSort)
    }
}

private struct GitlabKeyCell: View {
    @Environment(\.appTheme) private var theme
    let ticket: Ticket
    let prefix: String
    var body: some View {
        Text(verbatim: "\(prefix)\(ticket.externalKey)").font(theme.typography.mono.weight(.semibold)).foregroundStyle(theme.colors.tx2)
    }
}

private struct GitlabStateCell: View {
    @Environment(\.appTheme) private var theme
    let ticket: Ticket
    var body: some View {
        let isMr = (ticket.externalType ?? "").lowercased() == "mergerequest"
        if isMr {
            let s = gitlabMrTableState(ticket, palette: theme.colors)
            TableStatusCell(s.label, s.color)
        } else {
            let closed = ticket.providerStatus.lowercased() == "closed" || ticket.status == .done
            TableStatusCell(closed ? appString("viewClosed", "Closed") : appString("viewOpen", "Open"), closed ? theme.colors.tx3 : theme.colors.green)
        }
    }
}
