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
        return ZentaoBulkOps(workflow: deps.workflow, editor: deps.editor, assigner: { ticket, login, comment in
            await ZentaoAssignAction.run(deps: deps, ticket: ticket, assignee: login, comment: comment, left: nil)
        })
    }
}

/// Who picked tickets can go to: the people of each of their teams (execution / product, read once each), else the
/// account's users when no team could be read.
struct ZentaoBulkAssignSource: Equatable {
    var teams: [String: [ProviderUser]]
    var fallback: [ProviderUser]
}

extension ZentaoUIState {
    /// Reads the teams of `tickets` one after another (ZenTao signs a burst of parallel requests out of each other).
    func bulkAssignSource(_ tickets: [Ticket]) async -> Outcome<ZentaoBulkAssignSource> {
        var firstOf: [String: Ticket] = [:]
        var keys: [String] = []
        for t in tickets { if let k = ZenTaoAssignTeams.key(t), firstOf[k] == nil { firstOf[k] = t; keys.append(k) } }
        var teams: [String: [ProviderUser]] = [:]
        for key in keys {
            guard let t = firstOf[key] else { continue }
            let read: Outcome<[ProviderUser]>? = switch t.providerEntity {
            case .zentaoTask(let e)?: await zentaoLinkId(e.execution).asyncMap { await deps.teamMembers.executionMembers(accountId: t.accountId, executionId: $0) }
            case .zentaoBug(let b)?: await zentaoLinkId(b.product).asyncMap { await deps.teamMembers.productMembers(accountId: t.accountId, productId: $0) }
            default: nil
            }
            if let list = read?.value, !list.isEmpty { teams[key] = list }
        }
        if !teams.isEmpty { return .success(ZentaoBulkAssignSource(teams: teams, fallback: [])) }
        guard let first = tickets.first, let account = await deps.account(id: first.accountId),
              let adapter = await deps.services.sync.adapter(for: account) else {
            return .failure(.auth("No stored credentials for this account"))
        }
        return await adapter.listUsers().map { ZentaoBulkAssignSource(teams: [:], fallback: $0) }
    }
}

private extension Optional {
    func asyncMap<T>(_ f: (Wrapped) async -> T) async -> T? {
        guard let v = self else { return nil }
        return await f(v)
    }
}
