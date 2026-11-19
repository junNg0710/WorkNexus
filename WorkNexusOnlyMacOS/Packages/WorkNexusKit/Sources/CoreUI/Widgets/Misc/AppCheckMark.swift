import SwiftUI

/// Ported from: lib/core/widgets/app_check_mark.dart
/// The app's checkbox mark: a small rounded square, outlined when off and filled with the accent and a tick when on, easing
/// between the two. It only shows the state — the row around it handles the click and the hover. Not `enabled`: faded.
public struct AppCheckMark: View {
    @Environment(\.appTheme) private var theme
    let checked: Bool
    let enabled: Bool

    public init(checked: Bool, enabled: Bool = true) { self.checked = checked; self.enabled = enabled }

    public var body: some View {
        let side = theme.sizes.icon16
        RoundedRectangle(cornerRadius: theme.radii.xs)
            .fill(checked ? theme.colors.accent : .clear)
            .overlay(RoundedRectangle(cornerRadius: theme.radii.xs)
                .stroke(checked ? theme.colors.accent : theme.colors.tx3, lineWidth: theme.borders.hairline))
            .overlay {
                Image(systemName: "checkmark").font(.system(size: theme.sizes.icon12 * 0.85, weight: .bold))
                    .foregroundStyle(theme.colors.accentTx)
                    .scaleEffect(checked ? 1 : 0.01)
            }
            .frame(width: side, height: side)
            .opacity(enabled ? 1 : 0.45)
            .animation(.easeOut(duration: theme.motion.fast), value: checked)
            .accessibilityHidden(true)
    }
}
