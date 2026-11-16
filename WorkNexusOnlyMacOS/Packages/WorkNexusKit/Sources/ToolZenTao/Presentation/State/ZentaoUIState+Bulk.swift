/// Not in the Flutter app: the tickets picked on a board, and the bulk actions on them.
import CoreDomain
import Foundation

extension ZentaoUIState {
    /// The picked tickets that are on the board right now: a ticket a filter has since hidden is not acted on blind.
    func bulkTargets(bugs: Bool) -> [Ticket] {
        let board = bugs ? bugBoard : taskBoard
        return shownTickets(bugs: bugs).filter { board.selectedIds.contains($0.id) }
    }

    /// Every ticket the board shows, column by column.
    func shownTickets(bugs: Bool) -> [Ticket] {
        bugs ? ZentaoBoards.bugBoard(self).columns.flatMap(\.tickets) : ZentaoBoards.taskBoard(self).columns.flatMap(\.tickets)
    }

    func selectAllShown(bugs: Bool) { (bugs ? bugBoard : taskBoard).select(shownTickets(bugs: bugs).map(\.id)) }

    func bulkOps() -> ZentaoBulkOps {
        let deps = deps
        return ZentaoBulkOps(workflow: deps.workflow, editor: deps.editor, assigner: { ticket, login in
            await ZentaoAssignAction.run(deps: deps, ticket: ticket, assignee: login, comment: nil, left: nil)
        })
    }
}
