/// Ported from: lib/app/shell (the workspace section switch: overview / integrations / members)
import CoreUI
import SwiftUI

/// The workspace rail's content: the page of the active workspace section (`AppNavState.workspaceSection`). The
/// Integrations account list belongs to the connections feature, so the shell passes it as `accounts`.
public struct WorkspaceOverviewHost<Accounts: View>: View {
    let model: OverviewModel
    let accounts: Accounts
    let onConnect: (() -> Void)?

    public init(model: OverviewModel, onConnect: (() -> Void)? = nil, @ViewBuilder accounts: () -> Accounts) {
        self.model = model; self.onConnect = onConnect; self.accounts = accounts()
    }

    public var body: some View {
        switch model.nav.state.workspaceSection {
        case "integrations": IntegrationsPage(workspaceName: model.workspace?.name ?? "", onConnect: onConnect) { accounts }
        case "members": MembersPage()
        default: OverviewPage(model: model, onConnect: onConnect)
        }
    }
}

public extension WorkspaceOverviewHost where Accounts == EmptyView {
    init(model: OverviewModel, onConnect: (() -> Void)? = nil) { self.init(model: model, onConnect: onConnect) { EmptyView() } }
}
