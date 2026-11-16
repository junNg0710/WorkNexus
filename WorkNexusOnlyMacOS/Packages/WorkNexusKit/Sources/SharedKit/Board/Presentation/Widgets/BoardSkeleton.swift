import CoreUI
import SwiftUI

/// Ported from: lib/shared/board/presentation/widgets/ticket_card_skeleton.dart + `BoardSkeleton` (board_view.dart)
public struct TicketCardSkeleton: View {
    @Environment(\.appTheme) private var theme
    public init() {}
    public var body: some View {
        VStack(alignment: .leading, spacing: theme.spacing.s8) {
            HStack { SkeletonBox(width: 52, height: 16, radius: theme.radii.xs); Spacer(); SkeletonBox(width: 38, height: 16, radius: theme.radii.xs) }
            SkeletonBox(height: 14, radius: theme.radii.xs).padding(.trailing, theme.spacing.s24)
            SkeletonBox(width: 120, height: 14, radius: theme.radii.xs)
            HStack(spacing: theme.spacing.s6) { SkeletonBox(width: 18, height: 18, radius: theme.radii.pill); SkeletonBox(width: 72, height: 12, radius: theme.radii.xs) }
        }
        .padding(theme.cardPadding)
        .background(theme.colors.card, in: RoundedRectangle(cornerRadius: theme.radii.card))
        .overlay { if theme.showOutline { RoundedRectangle(cornerRadius: theme.radii.card).stroke(theme.colors.line, lineWidth: theme.borders.hairline) } }
    }
}

/// Six placeholder columns shown while a board loads.
public struct BoardSkeleton: View {
    @Environment(\.appTheme) private var theme
    public init() {}
    public var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(alignment: .top, spacing: theme.spacing.s12) {
                ForEach(0..<6, id: \.self) { _ in
                    VStack(alignment: .leading, spacing: theme.spacing.s8) {
                        SkeletonBox(width: 90, height: 16, radius: theme.radii.xs).padding(.bottom, theme.spacing.s6)
                        ForEach(0..<3, id: \.self) { _ in TicketCardSkeleton() }
                    }
                    .frame(width: theme.sizes.boardColumn)
                }
            }
            .padding(theme.spacing.s20)
        }
        .scrollDisabled(true)
    }
}
