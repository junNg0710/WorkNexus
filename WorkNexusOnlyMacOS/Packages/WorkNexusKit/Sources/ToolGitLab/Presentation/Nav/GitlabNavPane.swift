import CoreDomain
import CoreTools
import CoreUI
import SharedKit
import SwiftUI

/// Ported from: lib/tools/gitlab/presentation/nav/gitlab_nav_pane.dart
/// Navigation pane (L3/L4) for GitLab accounts: header, the feature tab strip (Merge requests / Issues) and the project
/// scope list.
struct GitlabNavPane: View {
    let ctx: GitlabContext
    let account: Account
    let sections: [ToolSection]

    var body: some View {
        let loc = ctx.nav.location(for: account.id)
        ToolPaneScaffold(title: ProviderType.gitlab.displayName, subtitle: account.handle) {
            FeatureTabStrip(sections: sections, selected: loc.section) { ctx.nav.setSection($0, accountId: account.id) }
            GitlabProjectsScopeList(ctx: ctx, account: account).frame(maxHeight: .infinity)
        }
        .task { ctx.start() }
    }
}
