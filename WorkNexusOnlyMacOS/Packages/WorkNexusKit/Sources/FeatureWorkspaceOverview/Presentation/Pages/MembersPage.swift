/// Ported from: lib/features/workspace_overview/presentation/pages/members_page.dart
import CoreUI
import SwiftUI

/// The Workspace Members placeholder page: a "coming soon" view explaining that connections are shared.
struct MembersPage: View {
    @Environment(\.appTheme) private var theme

    var body: some View {
        VStack(spacing: theme.spacing.s12) {
            Image(systemName: "person.2").font(.system(size: theme.sizes.icon24)).foregroundStyle(theme.colors.tx2)
                .frame(width: OverviewLayout.stateTile, height: OverviewLayout.stateTile)
                .background(theme.colors.panel2, in: RoundedRectangle(cornerRadius: theme.radii.md))
            Text(OL.members).font(theme.typography.title).foregroundStyle(theme.colors.tx)
            Text(OL.membersComingSoonBody).font(theme.typography.paragraph).foregroundStyle(theme.colors.tx2)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: OverviewLayout.stateMessageMax)
        .padding(theme.spacing.s40)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(theme.colors.bg)
    }
}
