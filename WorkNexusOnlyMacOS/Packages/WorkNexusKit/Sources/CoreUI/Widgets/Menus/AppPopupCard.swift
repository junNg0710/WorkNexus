import SwiftUI

/// Ported from: lib/core/widgets/app_popup_card.dart
/// The raised card every popup in the app sits on (menus, pickers): card fill, large radius, hairline border and
/// a soft shadow.
public struct AppPopupCard<Content: View>: View {
    @Environment(\.appTheme) private var theme
    let padding: CGFloat?; let content: Content
    public init(padding: CGFloat? = nil, @ViewBuilder content: () -> Content) { self.padding = padding; self.content = content() }
    public var body: some View {
        content
            .padding(padding ?? 0)
            .clipShape(RoundedRectangle(cornerRadius: theme.radii.lg, style: .continuous))
            .appGlass(in: RoundedRectangle(cornerRadius: theme.radii.lg, style: .continuous), fallback: theme.colors.card)
            .shadow(color: theme.colors.scrim.opacity(0.18), radius: theme.spacing.s24 / 2, y: theme.spacing.s8 / 2)
    }
}
