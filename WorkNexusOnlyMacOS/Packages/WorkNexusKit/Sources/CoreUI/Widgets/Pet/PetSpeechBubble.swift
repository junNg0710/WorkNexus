import SwiftUI

/// What the pet says, in a small rounded bubble with a tail pointing down at it. Not in the Flutter app.
public struct PetSpeechBubble: View {
    @Environment(\.appTheme) private var theme
    let text: String
    /// Off when the tail is drawn apart, right above the pet, because the bubble was moved sideways to stay on screen.
    let showsTail: Bool

    public init(_ text: String, showsTail: Bool = true) { self.text = text; self.showsTail = showsTail }

    /// The widest a bubble grows before its text wraps (three lines at most).
    public static let maxWidth: CGFloat = 200
    /// The room a bubble takes above the pet, tail included.
    public static let areaHeight: CGFloat = 64

    public var body: some View {
        VStack(spacing: -theme.borders.hairline) {
            Text(text)
                .font(theme.typography.meta)
                .foregroundStyle(theme.colors.tx)
                .multilineTextAlignment(.center)
                .lineLimit(3)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, theme.spacing.s10).padding(.vertical, theme.spacing.s6)
                .background(theme.colors.card, in: RoundedRectangle(cornerRadius: theme.radii.md))
                .overlay(RoundedRectangle(cornerRadius: theme.radii.md).strokeBorder(theme.colors.line, lineWidth: theme.borders.hairline))
            if showsTail { PetBubbleTail() }
        }
        .frame(maxWidth: Self.maxWidth)
        .accessibilityLabel(text)
    }
}

/// The bubble's tail: a small triangle pointing down at the pet, in the bubble's colours.
public struct PetBubbleTail: View {
    @Environment(\.appTheme) private var theme
    public static let size = CGSize(width: 12, height: 6)

    public init() {}

    public var body: some View {
        PetBubbleTailShape().fill(theme.colors.card)
            .overlay(PetBubbleTailShape().stroke(theme.colors.line, lineWidth: theme.borders.hairline))
            .frame(width: Self.size.width, height: Self.size.height)
    }
}

/// A small triangle pointing down.
struct PetBubbleTailShape: Shape {
    func path(in r: CGRect) -> Path {
        var p = Path()
        p.move(to: CGPoint(x: r.minX, y: r.minY))
        p.addLine(to: CGPoint(x: r.midX, y: r.maxY))
        p.addLine(to: CGPoint(x: r.maxX, y: r.minY))
        return p
    }
}
