import CoreDomain
import CoreTools
import Foundation
import Observation
import SharedKit

/// Ported from: lib/tools/github/presentation/sections/github_{pulls,issues}_section.dart (the data half) +
/// providers/github_board_providers.dart (`githubPrBoardProvider`, `githubIssueBoardProvider`).
/// One per section on screen: a shared `BoardController` (DB-backed tickets, filters, search) scoped to this account,
/// the open repository, the section's kind and the Review-requested quick scope.
@MainActor @Observable
final class GithubSectionModel {
    let ctx: GithubContext
    let account: Account
    let kind: GitHubItemKind
    let board: BoardController

    init(ctx: GithubContext, account: Account, kind: GitHubItemKind) {
        self.ctx = ctx; self.account = account; self.kind = kind
        board = BoardController(services: ctx.services, nav: ctx.nav, registry: ctx.registry)
        board.facetScope = .none
    }

    func start() { ctx.start(); board.start() }

    /// (Re)installs the scope closure — assigning it recomputes the board — and remembers the filter per board.
    func installScope(scopeId: String?, reviewRequested: Bool) {
        let accountId = account.id, kind = kind, account = account
        board.scopeTickets = { tickets in
            scopeGitHubTickets(tickets, accountId: accountId, scopeId: scopeId).filter {
                githubTicketIsKind($0, kind) && (!reviewRequested || githubReviewRequested($0, account: account))
            }
        }
        board.openBoard(board.currentBoardKey)
    }

    /// The scoped tickets after the user's filters and search.
    var filtered: [Ticket] { FilterTickets()(board.boardQuery) }

    var prBoard: GitHubPrBoardModel { BuildGitHubPrBoard()(filtered) }
    var issueBoard: GitHubIssueBoardModel { BuildGitHubIssueBoard()(filtered) }

    /// The list rows: the scoped, filtered tickets, narrowed to a state tab for pull requests.
    func listRows(state: GithubPrListState?) -> [Ticket] {
        let rows = filtered
        guard let state else { return rows }
        return rows.filter(state.matches)
    }
}

/// Sorts a list's rows by a table column (`id` numerically when both keys are numbers).
func githubSort(_ rows: [Ticket], by sort: TicketSort) -> [Ticket] {
    func cmp(_ a: Ticket, _ b: Ticket) -> Bool {
        switch sort.field {
        case .title: return a.title.localizedCaseInsensitiveCompare(b.title) == .orderedAscending
        case .status: return GithubItemState.of(a).label < GithubItemState.of(b).label
        case .updated: return (a.updatedAt ?? .distantPast) < (b.updatedAt ?? .distantPast)
        default:
            if let x = Int(a.externalKey), let y = Int(b.externalKey) { return x < y }
            return a.externalKey < b.externalKey
        }
    }
    return rows.sorted { sort.descending ? cmp($1, $0) : cmp($0, $1) }
}
