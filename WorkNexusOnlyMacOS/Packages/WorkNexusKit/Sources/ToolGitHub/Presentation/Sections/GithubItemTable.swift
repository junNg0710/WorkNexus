import CoreDomain
import CoreUI
import SharedKit
import SwiftUI

/// Ported from: lib/tools/github/presentation/widgets/github_pr_row.dart + github_issues_section.dart (`_IssueRow`)
/// The list view as a sortable `TicketTable`: `#key`, title, state (Draft / Open / Merged / Closed), updated.
struct GithubItemTable: View {
    let model: GithubSectionModel
    let rows: [Ticket]
    let sort: TicketSort
    let onSort: (TicketSortField) -> Void

    private var columns: [TicketTableColumn] {
        let dateFormat = model.board.settings.dateFormat
        return [
            TicketTableColumn(id: "key", label: model.kind == .pullRequest ? appString("githubColPr", "PR") : appString("githubColIssue", "Issue"),
                              width: 80, sortField: .id) { AnyView(GithubKeyCell(ticket: $0)) },
            TicketTableColumn(id: "title", label: appString("title", "Title"), sortField: .title) { AnyView(TableTitleCell($0)) },
            TicketTableColumn(id: "state", label: appString("status", "State"), width: 120, sortField: .status) { AnyView(GithubStateCell(ticket: $0)) },
            TicketTableColumn(id: "updated", label: appString("updated", "Updated"), width: 110, alignEnd: true, sortField: .updated) {
                AnyView(TableUpdatedCell($0, dateFormat: dateFormat))
            },
        ]
    }

    var body: some View {
        TicketTable(id: model.kind == .pullRequest ? "github.pulls" : "github.issues", columns: columns, rows: rows,
                    controller: model.board, sort: sort, onSort: onSort)
    }
}

private struct GithubKeyCell: View {
    @Environment(\.appTheme) private var theme
    let ticket: Ticket
    var body: some View {
        Text(verbatim: "#\(ticket.externalKey)").font(theme.typography.mono.weight(.semibold)).foregroundStyle(theme.colors.tx2)
    }
}

private struct GithubStateCell: View {
    @Environment(\.appTheme) private var theme
    let ticket: Ticket
    var body: some View {
        let state = GithubItemState.of(ticket)
        TableStatusCell(state.label, state.color(theme.colors))
    }
}
