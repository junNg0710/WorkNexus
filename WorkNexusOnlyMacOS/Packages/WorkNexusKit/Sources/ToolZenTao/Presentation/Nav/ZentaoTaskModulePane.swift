import CoreDomain
import CoreTools
import CoreUI
import SharedKit
import SwiftUI

/// Ported from: lib/tools/zentao/presentation/nav/zentao_task_module_pane.dart
/// The Tasks side panel, like the Bugs one: the pinned executions (and the open one), a picker for any other, then
/// the execution's module tree, which narrows the board.
struct ZentaoTaskModulePane: View {
    @Environment(\.appTheme) private var theme
    let state: ZentaoUIState
    let account: Account

    var body: some View {
        let pinned = state.taskBoard.settings.pinnedExecutions
        let open = state.execution.flatMap { sel in
            sel.accountId == account.id
                ? ProviderExecution(id: sel.executionId, name: sel.executionName, projectId: sel.projectId, accountId: sel.accountId) : nil
        }
        let known = (state.projects[account.id]?.value ?? []).flatMap { state.executionsOf(accountId: account.id, projectId: $0.id)?.value ?? [] }
        let rows = ZentaoNavLogic.executionRows(open: open, pinned: pinned, known: known, accountId: account.id)
        // Once every execution list is in, a pin that matches none is dead: listed so it can still be unpinned.
        let projects = state.projects[account.id]?.value
        let settled = projects != nil && (projects ?? []).allSatisfy { state.executionsOf(accountId: account.id, projectId: $0.id)?.value != nil }
        let stale = settled ? ZentaoNavLogic.staleExecutionIds(open: open, pinned: pinned, known: known, accountId: account.id) : []
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    ScopeGroupHeader(title: appString("executions", "Executions"))
                    ForEach(rows) { e in
                        let isPinned = pinned.contains(ZentaoNavLogic.executionKey(accountId: account.id, executionId: e.id))
                        ScopeEntryRow(name: e.name, systemImage: "bolt", selected: e.id == open?.id, isPinned: isPinned,
                                      onPinToggle: { state.togglePinnedExecution(accountId: account.id, executionId: e.id) },
                                      onTap: { state.openExecution(e) })
                    }
                    ForEach(stale, id: \.self) { id in
                        ScopeEntryRow(name: "#\(id)", systemImage: "bolt.slash", selected: false, isPinned: true,
                                      onPinToggle: { state.togglePinnedExecution(accountId: account.id, executionId: id) }, onTap: {})
                            .opacity(0.6)
                            .help(appString("zentaoExecutionGone", "This execution no longer exists"))
                    }
                    ZentaoScopePickerRow(label: appString("zentaoOtherExecutions", "Other executions…")) { close in
                        ZentaoExecutionPopover(state: state, account: account, onClose: close)
                    }
                    Spacer().frame(height: theme.spacing.s8)
                    ZentaoModuleTreeSection(state: state, bugs: false)
                }
                .padding(EdgeInsets(top: theme.spacing.s4, leading: theme.spacing.s8, bottom: theme.spacing.s16, trailing: theme.spacing.s8))
            }
            ZentaoHideEmptyModulesToggle(state: state)
        }
        // A pin carries only its key: the account's executions are loaded so the pinned rows can be named and opened.
        .task(id: PinResolution(pins: ZentaoNavLogic.pinnedExecutionIds(pinned, accountId: account.id),
                                projectIds: (state.projects[account.id]?.value ?? []).map(\.id))) {
            guard !ZentaoNavLogic.pinnedExecutionIds(pinned, accountId: account.id).isEmpty else { return }
            state.loadProjects(account.id)
            for p in state.projects[account.id]?.value ?? [] { state.loadExecutions(accountId: account.id, projectId: p.id) }
        }
    }

    /// What the loading of the pinned rows' executions depends on: the pins and the projects known so far.
    private struct PinResolution: Equatable { let pins: [String]; let projectIds: [String] }
}
