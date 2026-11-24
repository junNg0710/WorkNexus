import SwiftUI

/// Wraps its children onto new rows when they run out of width.
public struct FlowLayout: Layout {
    public var spacing: CGFloat
    public var rowSpacing: CGFloat
    public init(spacing: CGFloat, rowSpacing: CGFloat? = nil) { self.spacing = spacing; self.rowSpacing = rowSpacing ?? spacing }

    /// The rows worked out for one width. The stacks around a wrap ask for its size several times a layout, and each
    /// answer measured every chip again: on a board's bar of chips that was 4–5 % of the main thread while moving
    /// between places. SwiftUI makes a new cache when the chips change.
    public struct Rows {
        var width: CGFloat?
        var frames: [CGRect] = []
        var size = CGSize.zero
    }

    public func makeCache(subviews: Subviews) -> Rows { Rows() }

    public func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout Rows) -> CGSize {
        layout(proposal.width ?? .infinity, subviews, &cache)
        return cache.size
    }

    public func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout Rows) {
        layout(bounds.width, subviews, &cache)
        for (i, f) in cache.frames.enumerated() where i < subviews.count {
            subviews[i].place(at: CGPoint(x: bounds.minX + f.minX, y: bounds.minY + f.minY), proposal: ProposedViewSize(f.size))
        }
    }

    private func layout(_ width: CGFloat, _ subviews: Subviews, _ cache: inout Rows) {
        if cache.width == width, cache.frames.count == subviews.count { return }
        let rows = Self.rows(width, subviews.map { $0.sizeThatFits(ProposedViewSize(width: width.isFinite ? width : nil, height: nil)) },
                             spacing: spacing, rowSpacing: rowSpacing)
        cache = Rows(width: width, frames: rows.frames, size: rows.size)
    }

    /// Where children of `sizes` go in rows no wider than `width`, and the size of the whole.
    static func rows(_ width: CGFloat, _ sizes: [CGSize], spacing: CGFloat, rowSpacing: CGFloat) -> (frames: [CGRect], size: CGSize) {
        var frames: [CGRect] = [], x: CGFloat = 0, y: CGFloat = 0, rowH: CGFloat = 0, maxW: CGFloat = 0
        for sz in sizes {
            if x > 0, x + sz.width > width { x = 0; y += rowH + rowSpacing; rowH = 0 }
            frames.append(CGRect(origin: CGPoint(x: x, y: y), size: sz))
            x += sz.width + spacing; rowH = max(rowH, sz.height); maxW = max(maxW, x - spacing)
        }
        return (frames, CGSize(width: maxW, height: y + rowH))
    }
}

/// Ported from: lib/core/widgets/label_chips.dart
/// A wrap of label/tag chips. A label with a provider colour in `colors` (`#RRGGBB` background) is filled to
/// match the provider's palette, using `textColors` for the text (else a readable contrast); otherwise it is
/// a neutral outlined chip.
public struct LabelChips: View {
    @Environment(\.appTheme) private var theme
    let labels: [String]; let colors: [String: String]; let textColors: [String: String]
    public init(_ labels: [String], colors: [String: String] = [:], textColors: [String: String] = [:]) {
        self.labels = labels; self.colors = colors; self.textColors = textColors
    }
    public var body: some View {
        FlowLayout(spacing: theme.spacing.s4) {
            ForEach(Array(labels.enumerated()), id: \.offset) { _, label in
                LabelChip(label: label, fill: ProviderColor.argb(fromHex: colors[label]), ink: ProviderColor.argb(fromHex: textColors[label]))
            }
        }
    }
}

private struct LabelChip: View {
    @Environment(\.appTheme) private var theme
    let label: String; let fill: UInt32?; let ink: UInt32?

    var body: some View {
        // Prefer the provider's own text colour; otherwise a readable ink token based on how light the fill is.
        let fg = ink.map { Color(argb: $0) }
            ?? (fill.map { ProviderColor.luminance($0) > 0.5 ? theme.colors.onColorInk : theme.colors.accentTx } ?? theme.colors.tx2)
        Text(label).font(theme.typography.mono).lineLimit(1)
            .foregroundStyle(fg)
            .padding(.horizontal, theme.spacing.s8).padding(.vertical, theme.spacing.s2)
            .background(fill.map { Color(argb: $0) } ?? theme.colors.panel2, in: RoundedRectangle(cornerRadius: theme.radii.xs))
            .overlay {
                if fill == nil { RoundedRectangle(cornerRadius: theme.radii.xs).stroke(theme.colors.line, lineWidth: theme.borders.hairline) }
            }
    }
}
