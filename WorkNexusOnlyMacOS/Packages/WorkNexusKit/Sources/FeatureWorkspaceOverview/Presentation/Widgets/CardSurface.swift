/// Ported from: lib/features/workspace_overview/presentation/widgets/dashboard_card.dart (panel surface)
import CoreUI
import SwiftUI

/// A surface with a hairline border and rounded corners: the panel look of the overview's cards and lists.
struct CardSurface<Content: View>: View {
    @Environment(\.appTheme) private var theme
    var fill: KeyPath<AppPalette, Color> = \.card
    var padding: CGFloat = 0
    @ViewBuilder var content: Content

    var body: some View {
        content
            .padding(padding)
            .background(theme.colors[keyPath: fill], in: RoundedRectangle(cornerRadius: theme.radii.lg))
            .overlay(RoundedRectangle(cornerRadius: theme.radii.lg).stroke(theme.colors.line, lineWidth: theme.borders.hairline))
    }
}

/// The small uppercase group title of a card ("IN PROGRESS", status sections), with its colour dot and count.
struct DotSectionTitle: View {
    @Environment(\.appTheme) private var theme
    let title: String
    let color: Color
    let count: Int

    var body: some View {
        HStack(spacing: theme.spacing.s8) {
            Circle().fill(color).frame(width: OverviewLayout.dotSize, height: OverviewLayout.dotSize)
            Text(title.uppercased()).font(theme.typography.caption.weight(.semibold)).tracking(0.5)
                .foregroundStyle(theme.colors.tx3).lineLimit(1)
            AppCountBadge(count)
            Spacer(minLength: 0)
        }
    }
}
