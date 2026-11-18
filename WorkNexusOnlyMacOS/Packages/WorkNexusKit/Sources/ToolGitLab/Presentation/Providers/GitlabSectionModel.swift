import CoreDomain
import CoreTools
import Foundation
import Observation
import SharedKit

/// Ported from: lib/tools/gitlab/presentation/sections/gitlab_{mrs,issues}_section.dart (the data half) +
/// providers/gitlab_board_providers.dart (`gitlabMrBoardProvider`, `gitlabIssueBoardProvider`).
/// One per section on screen: a shared `BoardController` (DB-backed tickets, filters, search) scoped to this account,
/// the open project, the section's kind and the "Assigned to me" quick scope.
@MainActor @Observable
final class GitlabSectionModel {
    let ctx: GitlabContext
    let account: Account
    let kind: GitLabItemKind
    let board: BoardController

    init(ctx: GitlabContext, account: Account, kind: GitLabItemKind) {
        self.ctx = ctx; self.account = account; self.kind = kind
        board = BoardController(services: ctx.services, nav: ctx.nav, registry: ctx.registry)
        board.facetScope = kind == .mergeRequest ? .gitlabMergeRequest : .none
    }

    func start() { ctx.start(); board.start() }

    /// (Re)installs the scope closure — assigning it recomputes the board — and remembers the filter per board.
    func installScope(scopeId: String?, assignedToMe: Bool) {
        let accountId = account.id, kind = kind, account = account
        board.scopeTickets = { tickets in
            scopeGitLabTickets(tickets, accountId: accountId, scopeId: scopeId).filter {
                gitlabTicketIsKind($0, kind) && (!assignedToMe || IsAssignedToMe()($0, account))
            }
        }
        board.openBoard(board.currentBoardKey)
    }

    /// The scoped tickets after the user's filters and search.
    var filtered: [Ticket] { FilterTickets()(board.boardQuery) }

    var mrBoard: GitLabMrBoardModel { BuildGitLabMrBoard(sort: board.nav.boardSort)(filtered) }
    var issueBoard: GitLabIssueBoardModel { BuildGitLabIssueBoard(sort: board.nav.boardSort)(filtered) }

    /// The list rows: the scoped, filtered tickets, narrowed to a state tab and a chip for merge requests.
    func listRows(state: GitlabMrListState?, chip: GitlabMrChip) -> [Ticket] {
        guard let state else { return filtered }
        return filtered.filter { state.matches($0) && chip.matches($0, account: account) }
    }
}

/// Sorts a list's rows by a table column (`id` numerically when both keys are numbers).
func gitlabSort(_ rows: [Ticket], by sort: TicketSort) -> [Ticket] {
    func cmp(_ a: Ticket, _ b: Ticket) -> Bool {
        switch sort.field {
        case .title: return a.title.localizedCaseInsensitiveCompare(b.title) == .orderedAscending
        case .status: return a.providerStatus < b.providerStatus
        case .updated: return (a.updatedAt ?? .distantPast) < (b.updatedAt ?? .distantPast)
        default:
            if let x = Int(a.externalKey), let y = Int(b.externalKey) { return x < y }
            return a.externalKey < b.externalKey
        }
    }
    return rows.sorted { sort.descending ? cmp($1, $0) : cmp($0, $1) }
}
