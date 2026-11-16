import CoreUI
import SwiftUI

/// Ported from: lib/core/widgets/coming_soon_view.dart (as used by `GitlabModule.buildSection` for Actions, `body: ''`)
/// An icon tile and a title for a section that is not built yet.
struct GitlabComingSoon: View {
    @Environment(\.appTheme) private var theme
    let systemImage: String
    let title: String

    var body: some View {
        VStack(spacing: theme.spacing.s12) {
            Image(systemName: systemImage).font(.system(size: theme.sizes.icon24)).foregroundStyle(theme.colors.tx2)
                .frame(width: theme.sizes.control36 * 1.5, height: theme.sizes.control36 * 1.5)
                .background(theme.colors.panel2, in: RoundedRectangle(cornerRadius: theme.radii.md))
            Text(title).font(theme.typography.title).foregroundStyle(theme.colors.tx).multilineTextAlignment(.center)
        }
        .padding(theme.spacing.s16)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
