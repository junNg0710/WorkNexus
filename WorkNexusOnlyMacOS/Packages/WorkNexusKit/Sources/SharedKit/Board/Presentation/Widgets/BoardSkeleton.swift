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

/// Placeholder columns shown while a board loads: as many as fit, anchored top-left and filling the board's area, so the
/// toolbar above keeps its place and the board takes over the same space. (In a horizontal scroll view they were centred
/// vertically, and the section around them shrank: an empty band showed above.)
public struct BoardSkeleton: View {
    @Environment(\.appTheme) private var theme
    public init() {}
    public var body: some View {
        HStack(alignment: .top, spacing: theme.spacing.s12) {
            ForEach(0..<8, id: \.self) { column in
                VStack(alignment: .leading, spacing: theme.spacing.s8) {
                    SkeletonBox(width: [90, 110, 80, 100][column % 4], height: 16, radius: theme.radii.xs).padding(.bottom, theme.spacing.s6)
                    ForEach(0..<(3 - column % 2), id: \.self) { _ in TicketCardSkeleton() }
                }
                .frame(width: theme.sizes.boardColumn)
            }
        }
        .padding(theme.spacing.s20)
        // As wide as the board's area, not as wide as the columns would like (they run past its right edge, clipped).
        .frame(minWidth: 0, maxWidth: .infinity, minHeight: 0, maxHeight: .infinity, alignment: .topLeading)
        .clipped()
        .modifier(SkeletonEntrance())
    }
}

/// Placeholder rows shown while a list (table) loads.
public struct TableSkeleton: View {
    @Environment(\.appTheme) private var theme
    public init() {}
    public var body: some View {
        VStack(spacing: 0) {
            ForEach(0..<14, id: \.self) { i in
                HStack(spacing: theme.spacing.s16) {
                    SkeletonBox(width: 52, height: 12, radius: theme.radii.xs)
                    SkeletonBox(height: 12, radius: theme.radii.xs).padding(.trailing, CGFloat([120, 60, 180, 90][i % 4]))
                    SkeletonBox(width: 70, height: 12, radius: theme.radii.xs)
                    SkeletonBox(width: 90, height: 12, radius: theme.radii.xs)
                }
                .padding(.horizontal, theme.spacing.s20).frame(height: 40)
                .overlay(alignment: .bottom) { Rectangle().fill(theme.colors.line).frame(height: theme.borders.hairline) }
            }
        }
        .padding(.top, theme.spacing.s12)
        .frame(minWidth: 0, maxWidth: .infinity, minHeight: 0, maxHeight: .infinity, alignment: .top)
        .clipped()
        .modifier(SkeletonEntrance())
    }
}

private struct SkeletonEntrance: ViewModifier {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.appTheme) private var theme
    @State private var shown = false

    func body(content: Content) -> some View {
        content.opacity(shown || reduceMotion ? 1 : 0)
            .task {
                try? await Task.sleep(for: .seconds(theme.motion.fast))
                guard !Task.isCancelled else { return }
                withAnimation(reduceMotion ? nil : .easeOut(duration: theme.motion.base)) { shown = true }
            }
    }
}
