import CoreDomain
import CoreUI
import SwiftUI

/// Ported from: lib/tools/zentao/presentation/widgets/zentao_execution_switcher.dart
/// The Tasks header's `Project › Execution ▾` switcher: shows the open execution and opens the execution picker.
/// With no `account`, the picker lists the rail's.
public struct ZentaoExecutionSwitcher: View {
    let state: ZentaoUIState
    var account: Account?

    public init(state: ZentaoUIState, account: Account? = nil) { self.state = state; self.account = account }

    public var body: some View {
        ZentaoSwitcherButton(kind: appString("project", "Project"),
                             title: state.execution?.executionName ?? appString("zentaoSelectProject", "Select Project")) { close in
            ZentaoExecutionPopover(state: state, account: account, onClose: close)
        }
    }
}
