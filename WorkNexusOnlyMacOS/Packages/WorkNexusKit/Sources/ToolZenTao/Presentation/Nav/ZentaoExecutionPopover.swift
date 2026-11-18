import CoreDomain
import CoreTools
import CoreUI
import SwiftUI

/// Ported from: lib/tools/zentao/presentation/widgets/{zentao_execution_popover,zentao_execution_list}.dart
/// The picker of the Tasks side panel and header: search, Mine / Others tabs and the account's projects with their
/// open task counts; a project opens to its executions, which are what is picked (ZenTao lists tasks per
/// execution). Picking one opens its task board and calls `onClose`; right-clicking one pins it to the side panel. With
/// no `account`, the rail's is used.
struct ZentaoExecutionPopover: View {
    let state: ZentaoUIState
    var account: Account?
    let onClose: () -> Void
    @State private var search = ""
    @State private var tab = ZentaoPickerTab.mine

    /// The account the list is of: the given one, else the rail's. None: no projects (never stand-ins that would
    /// select ids of some other server).
    private var accountId: String? {
        if let account { return account.id }
        if case .account(let id) = state.deps.nav.state.rail { return id }
        return nil
    }

    var body: some View {
        ZentaoPickerShell(searchHint: appString("zentaoSearchProject", "Search project…"), search: $search, tab: $tab) {
            if let accountId {
                ZentaoExecutionList(state: state, accountId: accountId, account: account ?? state.taskBoard.accounts[accountId],
                                    search: search, tab: tab, onSelect: { e in state.openExecution(e); onClose() })
            }
        }
        .task(id: accountId) { if let accountId { state.loadProjects(accountId) } }
    }
}

/// The projects of the picker, each a folder of its executions.
struct ZentaoExecutionList: View {
    @Environment(\.appTheme) private var theme
    let state: ZentaoUIState
    let accountId: String
    let account: Account?
    let search: String
    let tab: ZentaoPickerTab
    let onSelect: (ProviderExecution) -> Void

    var body: some View {
        let choices = ZentaoNavLogic.projectChoices(
            projects: state.projects[accountId]?.value ?? [], tickets: state.taskBoard.tickets, account: account,
            accountId: accountId, search: search, tab: tab)
        let open = state.execution?.accountId == accountId ? state.execution : nil
        let prefix = "\(accountId):"
        let pinned = Set(state.taskBoard.settings.pinnedExecutions.filter { $0.hasPrefix(prefix) }.map { String($0.dropFirst(prefix.count)) })
        if choices.isEmpty {
            ZentaoPickerEmpty(systemImage: "folder.badge.questionmark", text: appString("zentaoNoProjectsFound", "No projects found"))
        } else {
            ScrollView {
                LazyVStack(spacing: theme.spacing.s2) {
                    ForEach(choices) { choice in
                        ZentaoProjectNode(
                            choice: choice, openExecutionId: open?.executionId, openProjectId: open?.projectId,
                            expandedByDefault: !search.trimmingCharacters(in: .whitespaces).isEmpty,
                            executions: state.executionsOf(accountId: accountId, projectId: choice.id),
                            onExpand: { state.loadExecutions(accountId: accountId, projectId: choice.id) },
                            pinnedIds: pinned, onTogglePin: { state.togglePinnedExecution(accountId: accountId, executionId: $0.id) },
                            onSelect: onSelect)
                    }
                }
                .padding(.vertical, theme.spacing.s4).padding(.horizontal, theme.spacing.s8)
            }
        }
    }
}
