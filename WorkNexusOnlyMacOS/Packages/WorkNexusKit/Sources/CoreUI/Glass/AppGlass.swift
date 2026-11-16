import SwiftUI

/// Liquid Glass (macOS 26 "Tahoe" and later, including 27). Everything here degrades to a material/opaque surface on
/// macOS 15–25 and whenever the user turns on "Reduce transparency", so call sites never branch on the OS version.
///
/// Where glass belongs (Apple's guidance): the *chrome that floats above content* — sidebar, title-bar controls,
/// slide-over panels, popovers, toasts, floating buttons — never the content itself (lists, boards, message bubbles).
public enum GlassSupport {
    /// True when the running OS draws real Liquid Glass.
    public static var isAvailable: Bool {
        if #available(macOS 26.0, *) { return true } else { return false }
    }
}

public struct AppGlassModifier<S: Shape>: ViewModifier {
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.appTheme) private var theme
    let shape: S; let tint: Color?; let interactive: Bool; let fallback: Color?

    public func body(content: Content) -> some View {
        if #available(macOS 26.0, *), !reduceTransparency {
            content.glassEffect(.regular.tint(tint).interactive(interactive), in: shape)
        } else {
            content
                .background(fallback ?? theme.colors.panel, in: shape)
                .overlay(shape.stroke(theme.colors.line, lineWidth: theme.borders.hairline))
        }
    }
}

public extension View {
    /// Draws `self` on a Liquid Glass surface of `shape` (`.regular` glass; `tint` colours it, `interactive` adds the
    /// press/hover response for controls). `fallback` is the opaque fill used when glass is unavailable.
    func appGlass<S: Shape>(in shape: S, tint: Color? = nil, interactive: Bool = false, fallback: Color? = nil) -> some View {
        modifier(AppGlassModifier(shape: shape, tint: tint, interactive: interactive, fallback: fallback))
    }
}

/// Groups neighbouring glass shapes so they blend/morph into one another (Apple's `GlassEffectContainer`).
public struct AppGlassContainer<Content: View>: View {
    let spacing: CGFloat; let content: Content
    public init(spacing: CGFloat = 12, @ViewBuilder content: () -> Content) { self.spacing = spacing; self.content = content() }
    public var body: some View {
        if #available(macOS 26.0, *) { GlassEffectContainer(spacing: spacing) { content } } else { content }
    }
}
