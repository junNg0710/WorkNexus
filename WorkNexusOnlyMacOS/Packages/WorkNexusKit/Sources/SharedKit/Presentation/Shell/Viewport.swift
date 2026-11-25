import CoreDomain
import CoreTools
import CoreUI
import SwiftUI

/// Ported from: app/shell/viewport. Renders the active place; features arrive through `ShellModel.host`. Places are kept
/// alive like the Dart `IndexedStack` cache: the last 5 sections stay mounted (filters, search and scroll survive a trip
/// elsewhere). The mini-app stack is always mounted (its pages stay alive while hidden) and covers the place while a mini
/// app is selected.
struct Viewport: View {
    @Environment(\.appTheme) private var theme
    let model: ShellModel

    var body: some View {
        let place = self.place
        ZStack {
            KeepAliveStack(activeKey: place.key, visible: !model.miniAppOnScreen, limit: Self.keepAliveLimit,
                           generation: model.activeWorkspaceId.hashValue, content: place.view)
                .contentArrival(on: place.key, backdrop: theme.colors.bg)
            model.host.miniAppStack()
        }
        .background(theme.colors.bg)
    }

    static let keepAliveLimit = 5

    /// The cache key of the place on screen and its view: `account:section`, `workspace:section`, `settings:section`, `chat`.
    private var place: (key: String, view: AnyView) {
        switch model.nav.state.rail {
        case .account(let id):
            guard let a = model.account(id), let tool = model.registry.module(for: a.providerType) else {
                return ("account:\(id):missing", AnyView(SectionErrorBoundary(message: appString("noToolForAccount", "No tool for this account")) {
                    model.nav.select(.workspace)
                }))
            }
            let location = model.nav.location(for: id)
            return ("\(id):\(location.section.rawValue)",
                    AnyView(AccountSectionView(model: model, account: a, section: tool.buildSection(account: a, location: location))))
        case .workspace:
            let s = model.nav.state.workspaceSection
            return ("workspace:\(s)", model.host.workspacePage(s))
        case .settings:
            let s = model.nav.state.settingsSection
            return ("settings:\(s)", model.host.settingsPage(s))
        case .chat:
            guard let a = model.chatAccount else {
                return ("chat:none", AnyView(AppStateView(.empty(appString("chatNoZentaoAccount", "Connect a ZenTao account in Integrations to use chat.")))))
            }
            return ("chat:\(a.id)", model.host.chatView(a))
        }
    }
}
