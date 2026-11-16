import CoreDomain
import CoreUI
import SharedKit
import SwiftUI

/// Ported from: lib/tools/gitlab/presentation/widgets/gitlab_board_view.dart (+ gitlab_ticket_card.dart, identical to the
/// shared `TicketCard`). The dedicated GitLab board: horizontally scrolling lifecycle columns (MR: Draft / Review /
/// Merged / Closed; issues: Open / In progress / Closed) over the filtered tickets. Read-only — state changes go through
/// the detail panel actions.
struct GitlabBoardView: View {
    @Environment(\.appTheme) private var theme
    let model: GitlabSectionModel

    var body: some View {
        BoardHorizontalScroll {
            HStack(alignment: .top, spacing: theme.spacing.s12) {
                ForEach(columns(model.kind, theme.colors)) { col in
                    BoardColumnFrame(label: col.label, itemCount: col.tickets.count) {
                        BoardColumnDot(col.color)
                    } badge: {
                        AppCountBadge(col.tickets.count)
                    } content: {
                        ForEach(col.tickets) { TicketCard($0, controller: model.board) }
                    }
                }
            }
            .frame(maxHeight: .infinity, alignment: .top)
        }
    }

    private func columns(_ kind: GitLabItemKind, _ c: AppPalette) -> [GitlabBoardColumnData] {
        if kind == .mergeRequest {
            let b = model.mrBoard
            return [
                GitlabBoardColumnData(id: "draft", label: appString("gitlabColDraft", "Draft"), color: c.tx3, tickets: b.column(.draft).tickets),
                GitlabBoardColumnData(id: "review", label: appString("colReview", "Review"), color: c.accent, tickets: b.column(.review).tickets),
                GitlabBoardColumnData(id: "merged", label: appString("gitlabColMerged", "Merged"), color: c.green, tickets: b.column(.merged).tickets),
                GitlabBoardColumnData(id: "closed", label: appString("gitlabColClosed", "Closed"), color: c.tx2, tickets: b.column(.closed).tickets),
            ]
        }
        let b = model.issueBoard
        return [
            GitlabBoardColumnData(id: "open", label: appString("gitlabColOpen", "Open"), color: c.accent, tickets: b.column(.open).tickets),
            GitlabBoardColumnData(id: "progress", label: appString("colInprogress", "In Progress"), color: c.amber, tickets: b.column(.inProgress).tickets),
            GitlabBoardColumnData(id: "closed", label: appString("gitlabColClosed", "Closed"), color: c.tx2, tickets: b.column(.closed).tickets),
        ]
    }
}

struct GitlabBoardColumnData: Identifiable {
    let id: String; let label: String; let color: Color; let tickets: [Ticket]
}
