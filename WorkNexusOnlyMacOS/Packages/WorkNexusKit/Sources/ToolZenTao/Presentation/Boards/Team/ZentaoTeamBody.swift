/// Not in the Flutter app.
import CoreDomain
import CoreUI
import SharedKit
import SwiftUI

/// The board (or list) of a team group: a skeleton while the first reads are out, an error when none could be read,
/// else the usual kanban / table over the tickets read.
struct ZentaoTeamBody: View {
    let state: ZentaoUIState; let team: ZentaoTeamScope; let bugs: Bool; let list: Bool
    var deps: ZentaoDependencies?

    private var board: BoardController { bugs ? state.bugBoard : state.taskBoard }

    var body: some View {
        if team.allFailed, board.scoped.isEmpty {
            let reason: String = { if case .failed(let m)? = team.loads.values.first(where: \.isFailed) { return m } else { return "" } }()
            AppStateView(.error(reason)) { state.loadTeam(bugs: bugs, only: nil) }
        } else if team.isLoading, board.scoped.isEmpty {
            BoardSkeleton()
        } else if bugs {
            if list { ZentaoBugTableView(state: state) } else if let deps { ZentaoBugBoardView(deps: deps, state: state) }
        } else {
            if list { ZentaoTaskTableView(state: state) } else { ZentaoTaskBoardView(state: state) }
        }
    }
}

/// On a team's card: which execution (product) the ticket is in, as the board is not scoped to one.
struct ZentaoCardScopeLine: View {
    @Environment(\.appTheme) private var theme
    @Environment(\.zentaoState) private var state
    let ticket: Ticket

    var body: some View {
        if let state, state.team(bugs: zentaoKind(ticket) == "bug") != nil, let name = Self.scopeName(ticket) {
            HStack(spacing: theme.spacing.s4) {
                Image(systemName: "folder").font(.system(size: theme.sizes.icon12)).foregroundStyle(theme.colors.tx3)
                Text(name).font(theme.typography.caption).foregroundStyle(theme.colors.tx3).lineLimit(1)
            }
        }
    }

    static func scopeName(_ t: Ticket) -> String? {
        let name: String?
        switch t.providerEntity {
        case .zentaoTask(let e)?: name = e.executionName
        case .zentaoBug(let b)?: name = b.executionName?.isEmpty == false ? b.executionName : b.productName
        default: name = nil
        }
        return (name ?? "").isEmpty ? nil : name
    }
}
