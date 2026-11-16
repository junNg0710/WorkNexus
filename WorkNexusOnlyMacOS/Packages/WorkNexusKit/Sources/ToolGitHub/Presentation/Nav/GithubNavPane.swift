import CoreDomain
import CoreTools
import CoreUI
import SharedKit
import SwiftUI

/// Ported from: lib/tools/github/presentation/nav/github_nav_pane.dart
/// Navigation pane (L3/L4) for GitHub accounts: header, the feature tab strip (Pull requests / Issues) and the
/// repository scope list.
struct GithubNavPane: View {
    let ctx: GithubContext
    let account: Account
    let sections: [ToolSection]

    var body: some View {
        let loc = ctx.nav.location(for: account.id)
        ToolPaneScaffold(title: ProviderType.github.displayName, subtitle: account.handle) {
            FeatureTabStrip(sections: sections, selected: loc.section) { ctx.nav.setSection($0, accountId: account.id) }
            GithubReposScopeList(ctx: ctx, account: account).frame(maxHeight: .infinity)
        }
        .task { ctx.start() }
    }
}
