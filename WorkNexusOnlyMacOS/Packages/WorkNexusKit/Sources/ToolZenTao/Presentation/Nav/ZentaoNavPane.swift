/// Ported from: lib/tools/zentao/presentation/nav/zentao_nav_pane.dart
import CoreDomain
import CoreTools
import CoreUI
import SharedKit
import SwiftUI

/// Navigation pane (L3/L4) for ZenTao accounts: the account switcher (two accounts or more), then the side panel of
/// the open section - the Bugs products and modules, the Tasks executions and modules, or the Docs libraries.
/// `docsPane` is the Docs section's library tree (`ZentaoDocLibsPane`), shown while Docs is open.
public struct ZentaoNavPane: View {
    let deps: ZentaoDependencies; let state: ZentaoUIState; let account: Account; let location: ToolLocation
    let sections: [ToolSection]; let docsPane: AnyView
    public init(deps: ZentaoDependencies, state: ZentaoUIState, account: Account, location: ToolLocation,
                sections: [ToolSection], docsPane: AnyView) {
        self.deps = deps; self.state = state; self.account = account; self.location = location
        self.sections = sections; self.docsPane = docsPane
    }

    public var body: some View {
        // Tasks and Bugs are rail places of their own; the pane picks the account instead.
        ToolPaneScaffold(title: ProviderType.zentao.displayName, subtitle: account.handle) {
            ZentaoAccountSwitcher(state: state, account: account, section: location.section)
            ZentaoNavBody(state: state, account: account, location: location, docsPane: docsPane)
                .frame(maxHeight: .infinity)
        }
    }
}

/// The side panel under the account switcher: one pane per section.
struct ZentaoNavBody: View {
    let state: ZentaoUIState; let account: Account; let location: ToolLocation; let docsPane: AnyView

    var body: some View {
        switch location.section {
        case ZentaoSection.tasks: ZentaoTaskModulePane(state: state, account: account)
        case ZentaoSection.bugs: ZentaoBugModulePane(state: state, account: account, location: location)
        case ZentaoSection.docs: docsPane
        default: Color.clear
        }
    }
}
