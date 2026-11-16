/// Ported from: lib/tools/zentao/presentation/widgets/{zentao_bug_section_header,zentao_task_section_header}.dart
import CoreDomain
import CoreTools
import CoreUI
import SwiftUI

/// The top header of the Bugs (`bugs`) or Tasks section: the product / execution switcher, a caption
/// ("Bugs - 6 of 21 shown", "Tasks - 12") and the primary "New bug" / "New task" button.
struct ZentaoSectionHeader: View {
    @Environment(\.appTheme) private var theme
    let deps: ZentaoDependencies; let state: ZentaoUIState; let account: Account; let location: ToolLocation; let bugs: Bool

    private var caption: String {
        if bugs {
            let n = ZentaoBoards.bugShownCount(state)
            return "\(appString("bugs", "Bugs")) · \(appFormat("boardShownOfTotal", "%1$@ of %2$@ shown", "\(n.shown)", "\(n.total)"))"
        }
        return "\(appString("tasks", "Tasks")) · \(ZentaoBoards.taskTable(state).rows.count)"
    }

    /// Filed into the open product / execution (what the board is scoped to), else ZenTao's current one.
    private func create() {
        deps.nav.openEditor(bugs ? state.newBugRoute(accountId: account.id) : state.newTaskRoute(accountId: account.id))
    }

    var body: some View {
        HStack(spacing: theme.spacing.s12) {
            if bugs { ZentaoProductSwitcher(state: state, account: account) } else { ZentaoExecutionSwitcher(state: state, account: account) }
            Text(caption).font(theme.typography.body).foregroundStyle(theme.colors.tx3).lineLimit(1)
            Spacer(minLength: 0)
            AppButton(bugs ? appString("newBug", "New bug") : appString("newTask", "New task"), systemImage: "plus", kind: .primary, action: create)
        }
        .padding(.horizontal, theme.spacing.s20).padding(.vertical, theme.spacing.s10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(theme.colors.panel)
    }
}
