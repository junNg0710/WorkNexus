/// Ported from: lib/tools/zentao/presentation/sections/zentao_tasks_section.dart (+ util/keep_task_board_scope.dart)
import CoreDomain
import CoreTools
import CoreUI
import SharedKit
import SwiftUI

/// The L5 viewport of ZenTao Tasks: header (execution switcher, count, + New task), the toolbar (All / Related to me /
/// Due this week, filters, view mode) and the board or the list. Tasks are listed per execution only.
public struct ZentaoTasksSection: View {
    @Environment(\.appTheme) private var theme
    let deps: ZentaoDependencies; let state: ZentaoUIState; let account: Account; let location: ToolLocation

    public init(deps: ZentaoDependencies, state: ZentaoUIState, account: Account, location: ToolLocation) {
        self.deps = deps; self.state = state; self.account = account; self.location = location
    }

    /// Changes whenever something `keepTaskBoardScope` waits on (projects, executions) arrives.
    private var loadSignature: String {
        let projects = state.projects[account.id]?.value ?? []
        let execs = projects.map { state.executionsOf(accountId: account.id, projectId: $0.id)?.value?.count ?? -1 }
        return "\(account.id)|\(location.scopeId ?? "")|\(projects.count)|\(execs)"
    }

    public var body: some View {
        let viewMode = ZentaoSectionMode.mode(location, ZentaoSection.tasks, settings: state.taskBoard.settings)
        let isRelated = state.taskBoard.filter.savedView == .related
        let board = state.taskBoard
        VStack(spacing: 0) {
            ZentaoSectionHeader(deps: deps, state: state, account: account, location: location, bugs: false)
            ZentaoBoardToolbar(
                state: state, bugs: false,
                scopes: [
                    AppSegmentedTab(label: appString("viewAll", "All"), active: !isRelated) { board.leaveOwnView() },
                    // Related to me is a filter of its own: the others are set aside (All brings them back).
                    AppSegmentedTab(label: appString("relatedToMe", "Related to me"), active: isRelated) { board.enterOwnView(.related) },
                ],
                modes: ZentaoSectionMode.modes, viewMode: viewMode,
                onViewMode: { deps.nav.setViewMode($0, section: ZentaoSection.tasks, accountId: account.id) },
                filtering: !isRelated,
                searchScope: state.scopeTitle(accountId: account.id, scopeId: location.scopeId, bugs: false))
            ZentaoTasksBody(state: state, account: account, location: location, list: viewMode == "list")
        }
        .background(theme.colors.bg)
        .environment(\.zentaoState, state)
        .overlay { ZentaoBulkBar(deps: deps, state: state, bugs: false) }
        .task(id: loadSignature) {
            state.keepTaskBoardScope(account: account, location: location)
            state.loadBoardMembers(bugs: false); state.loadModuleNames(bugs: false)
        }
        .onChange(of: viewMode, initial: true) { _, mode in state.taskListMode = mode == "list"; state.refreshFetchSorts() }
    }
}

private struct ZentaoTasksBody: View {
    @Environment(\.appTheme) private var theme
    let state: ZentaoUIState; let account: Account; let location: ToolLocation; let list: Bool

    var body: some View {
        if let team = state.taskTeam {
            ZentaoTeamBody(state: state, team: team, bugs: false, list: list)
        } else if !state.taskBoardHasExecution(account: account, location: location) {
            // Until an execution is picked (or none could be): tasks are listed per execution only.
            AppStateView(.empty(appString("zentaoPickExecution", "Pick an execution to see its tasks")))
        } else if let failure = state.taskSlice.failure, state.taskBoard.scoped.isEmpty {
            AppStateView(.error(failure.message)) { state.reopenTaskStreams() }
        } else if state.taskSlice.isLoading && state.taskBoard.scoped.isEmpty {
            BoardSkeleton()
        } else if list {
            ZentaoTaskTableView(state: state)
        } else {
            ZentaoTaskBoardView(state: state)
        }
    }
}
