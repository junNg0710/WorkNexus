/// Ported from: lib/tools/zentao/presentation/providers/{zentao_board_providers (board models),zentao_table_providers,
/// zentao_module_tree_provider (shown count)}.dart. The derived models the board and table views render.
import CoreDomain
import Foundation
import SharedKit

@MainActor
enum ZentaoBoards {
    /// The bug board's columns after the filters (the Closed column only on the All tab).
    static func bugBoard(_ s: ZentaoUIState) -> ZenTaoBugBoardModel {
        s.bugCache.bugBoard(s.cacheKey(bugs: true)) {
            BuildZenTaoBugBoard(includeClosed: s.bugTab == .all, leader: s.leader(bugs: true), names: s.memberNames)(s.bugBoard.boardQuery)
        }
    }

    static func taskBoard(_ s: ZentaoUIState) -> ZenTaoTaskBoardModel {
        s.taskCache.taskBoard(s.cacheKey(bugs: false)) {
            BuildZenTaoTaskBoard(leader: s.leader(bugs: false), names: s.memberNames)(s.taskBoard.boardQuery)
        }
    }

    /// The task board as one table: status by status, each status view's tasks showing once the statuses before it are
    /// fully loaded.
    static func taskTable(_ s: ZentaoUIState) -> PagedTable<ZenTaoTaskColumn> {
        let hasExec = s.execution != nil && s.taskTeam == nil
        return BuildPagedTable<ZenTaoTaskColumn>()(PagedTableQuery(
            segments: taskBoard(s).columns.map {
                PagedTableSegment(view: $0.column, tickets: $0.tickets, complete: !hasExec || !(s.taskStreams.views[$0.column]?.hasMore ?? false))
            }, sort: s.taskSort))
    }

    /// The bug board as one table: view by view in column order (a view feeding several columns is one stretch).
    static func bugTable(_ s: ZentaoUIState) -> PagedTable<ZenTaoBugStream> {
        var order: [ZenTaoBugStream] = []
        var byView: [ZenTaoBugStream: [Ticket]] = [:]
        for col in bugBoard(s).columns {
            let view = ZenTaoBugStream.of(col.column, related: s.bugRelated)
            if byView[view] == nil { order.append(view) }
            byView[view, default: []].append(contentsOf: col.tickets)
        }
        return BuildPagedTable<ZenTaoBugStream>()(PagedTableQuery(
            segments: order.map { PagedTableSegment(view: $0, tickets: byView[$0] ?? [], complete: s.bugTeam != nil || !(s.bugStreams.views[$0]?.hasMore ?? false)) },
            sort: s.bugSort))
    }

    /// How many bugs the board shows and how many it would with no chip filters (its view kept): "6 of 21 shown".
    static func bugShownCount(_ s: ZentaoUIState) -> (shown: Int, total: Int) {
        let query = s.bugBoard.boardQuery
        var base = FilterState()
        base.workspaceId = query.filter.workspaceId; base.savedView = query.filter.savedView
        let build = BuildZenTaoBugBoard(includeClosed: s.bugTab == .all)
        var shown = build
        shown.leader = s.leader(bugs: true); shown.names = s.memberNames
        return (shown(query).total, build(query.withFilter(base)).total)
    }
}
