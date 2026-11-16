import SwiftUI

/// Ported from: lib/core/widgets/hover_surface.dart
/// Tracks whether the pointer is over its content and hands that to `content`. It paints nothing itself.
public struct HoverRegion<Content: View>: View {
    @State private var hovered = false
    private let enabled: Bool
    private let content: (Bool) -> Content
    public init(enabled: Bool = true, @ViewBuilder content: @escaping (_ hovered: Bool) -> Content) {
        self.enabled = enabled; self.content = content
    }
    public var body: some View {
        content(hovered && enabled).onHover { hovered = $0 }
    }
}

/// A tappable block that tints its own fill while hovered (or `selected`); a pointing-hand cursor when
/// `onTap` is set and the surface is enabled.
public struct HoverSurface<Content: View>: View {
    @Environment(\.appTheme) private var theme
    @State private var hovered = false
    private let onTap: (() -> Void)?
    private let selected: Bool
    private let enabled: Bool
    private let height: CGFloat?
    private let fill: Color?
    private let border: Color?
    private let cornerRadius: CGFloat?
    private let content: Content

    public init(onTap: (() -> Void)? = nil, selected: Bool = false, enabled: Bool = true, height: CGFloat? = nil,
                fill: Color? = nil, border: Color? = nil, cornerRadius: CGFloat? = nil, @ViewBuilder content: () -> Content) {
        self.onTap = onTap; self.selected = selected; self.enabled = enabled; self.height = height
        self.fill = fill; self.border = border; self.cornerRadius = cornerRadius; self.content = content()
    }

    public var body: some View {
        let radius = cornerRadius ?? theme.radii.md
        let on = enabled && (hovered || selected)
        content
            .frame(height: height)
            .background(on ? theme.colors.sel : (fill ?? .clear), in: RoundedRectangle(cornerRadius: radius))
            .overlay {
                if let border { RoundedRectangle(cornerRadius: radius).stroke(border, lineWidth: theme.borders.hairline) }
            }
            .contentShape(RoundedRectangle(cornerRadius: radius))
            .onHover { hovered = $0 && enabled }
            .onTapGesture { if enabled { onTap?() } }
            .pointerStyle(onTap != nil && enabled ? .link : .default)
            .opacity(enabled ? 1 : 0.6)
    }
}
