import CoreDomain
import CoreUI
import SharedKit
import SwiftUI

/// Ported from: lib/tools/github/presentation/widgets/github_board_view.dart
/// The dedicated GitHub board: horizontally scrolling lifecycle columns (PR: Draft / Review / Merged / Closed;
/// issues: Open / In progress / Closed) over the filtered tickets. Read-only — state changes go through the detail
/// panel actions.
struct GithubBoardView: View {
    @Environment(\.appTheme) private var theme
    let model: GithubSectionModel

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

    private func columns(_ kind: GitHubItemKind, _ c: AppPalette) -> [GithubBoardColumnData] {
        if kind == .pullRequest {
            let b = model.prBoard
            return [
                GithubBoardColumnData(id: "draft", label: appString("githubColDraft", "Draft"), color: c.tx3, tickets: b.column(.draft).tickets),
                GithubBoardColumnData(id: "review", label: appString("colReview", "Review"), color: c.accent, tickets: b.column(.review).tickets),
                GithubBoardColumnData(id: "merged", label: appString("githubColMerged", "Merged"), color: c.green, tickets: b.column(.merged).tickets),
                GithubBoardColumnData(id: "closed", label: appString("githubColClosed", "Closed"), color: c.tx2, tickets: b.column(.closed).tickets),
            ]
        }
        let b = model.issueBoard
        return [
            GithubBoardColumnData(id: "open", label: appString("githubColOpen", "Open"), color: c.accent, tickets: b.column(.open).tickets),
            GithubBoardColumnData(id: "progress", label: appString("colInprogress", "In Progress"), color: c.amber, tickets: b.column(.inProgress).tickets),
            GithubBoardColumnData(id: "closed", label: appString("githubColClosed", "Closed"), color: c.tx2, tickets: b.column(.closed).tickets),
        ]
    }
}

struct GithubBoardColumnData: Identifiable {
    let id: String; let label: String; let color: Color; let tickets: [Ticket]
}
