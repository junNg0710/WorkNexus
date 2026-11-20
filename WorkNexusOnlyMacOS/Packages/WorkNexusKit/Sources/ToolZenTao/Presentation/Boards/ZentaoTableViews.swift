/// Ported from: lib/tools/zentao/presentation/widgets/{zentao_bug_table_view,zentao_task_table_view}.dart
import CoreDomain
import CoreUI
import SharedKit
import SwiftUI

/// The ZenTao bug list: the bug board as one sortable table, view by view; the end of a view with more pages loads it.
struct ZentaoBugTableView: View {
    @Environment(\.appTheme) private var theme
    let state: ZentaoUIState

    var body: some View {
        let table = ZentaoBoards.bugTable(state)
        let rows = table.rows
        if rows.isEmpty && table.pending == nil {
            BoardEmptyState(controller: state.bugBoard)
        } else {
            VStack(spacing: 0) {
                ZentaoListCaption(text: appFormat("dashboardBugCount", rows.count == 1 ? "%1$@ bug" : "%1$@ bugs", "\(rows.count)"))
                TicketTable(id: "zentao.bugs", columns: ZentaoTableColumns.withoutEmpty(ZentaoTableColumns.bugs(palette: theme.colors), rows: rows), rows: rows,
                            controller: state.bugBoard, sort: state.bugSort,
                            onSort: { state.bugSort = state.bugSort.toggled($0); state.refreshFetchSorts() }) {
                    if let pending = table.pending, let column = ZenTaoBugColumn.allCases.first(where: {
                        ZenTaoBugStream.of($0, related: state.bugRelated) == pending }) {
                        ZentaoBugColumnFooter(state: state, column: column, visible: rows.count)
                    }
                }
            }
        }
    }
}

/// The ZenTao task list: the task board as one sortable table, status by status.
struct ZentaoTaskTableView: View {
    @Environment(\.appTheme) private var theme
    let state: ZentaoUIState

    var body: some View {
        let table = ZentaoBoards.taskTable(state)
        let rows = table.rows
        if rows.isEmpty && table.pending == nil {
            BoardEmptyState(controller: state.taskBoard)
        } else {
            VStack(spacing: 0) {
                ZentaoListCaption(text: appFormat("dashboardTaskCount", rows.count == 1 ? "%1$@ task" : "%1$@ tasks", "\(rows.count)"))
                TicketTable(id: "zentao.tasks", columns: ZentaoTableColumns.withoutEmpty(ZentaoTableColumns.tasks(palette: theme.colors), rows: rows), rows: rows,
                            controller: state.taskBoard, sort: state.taskSort,
                            onSort: { state.taskSort = state.taskSort.toggled($0); state.refreshFetchSorts() }) {
                    if let pending = table.pending {
                        ZentaoTaskColumnFooter(state: state, column: pending, visible: rows.filter { zentaoTaskColumnFor($0) == pending }.count)
                    }
                }
            }
        }
    }
}

/// "12 bugs" above a list.
struct ZentaoListCaption: View {
    @Environment(\.appTheme) private var theme
    let text: String
    var body: some View {
        Text(text).font(theme.typography.caption.weight(.semibold)).foregroundStyle(theme.colors.tx2)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, theme.spacing.s20).padding(.top, theme.spacing.s6)
    }
}
