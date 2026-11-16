import SwiftUI

/// Ported from: lib/core/widgets/app_dropdown.dart
/// The app's dropdown picker, filling its width: the current choice with a caret, and a menu of `values` that
/// checks the picked one.
public struct AppDropdown<T: Hashable>: View {
    @Environment(\.appTheme) private var theme
    let value: T; let values: [T]; let labelOf: (T) -> String; let onChanged: (T) -> Void; let help: String?
    let fontFamilyOf: ((T) -> String?)?

    /// - Parameter fontFamilyOf: lets the *current* choice preview itself (the font picker shows each font in its own face).
    public init(value: T, values: [T], labelOf: @escaping (T) -> String, help: String? = nil,
                fontFamilyOf: ((T) -> String?)? = nil, onChanged: @escaping (T) -> Void) {
        self.value = value; self.values = values; self.labelOf = labelOf; self.help = help
        self.fontFamilyOf = fontFamilyOf; self.onChanged = onChanged
    }

    public var body: some View {
        Menu {
            ForEach(values, id: \.self) { option in
                Button { onChanged(option) } label: {
                    if option == value { Label(labelOf(option), systemImage: "checkmark") } else { Text(labelOf(option)) }
                }
            }
        } label: {
            HStack(spacing: theme.spacing.s4) {
                Text(labelOf(value)).font(font(for: value)).foregroundStyle(theme.colors.tx).lineLimit(1)
                Spacer(minLength: 0)
                Image(systemName: "chevron.down").font(.system(size: theme.sizes.icon12)).foregroundStyle(theme.colors.tx2)
            }
            .padding(.horizontal, theme.spacing.s12).padding(.vertical, theme.spacing.s6)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(theme.colors.panel2, in: RoundedRectangle(cornerRadius: theme.radii.md))
            .overlay(RoundedRectangle(cornerRadius: theme.radii.md).stroke(theme.colors.line, lineWidth: theme.borders.hairline))
            .contentShape(Rectangle())
        }
        .menuStyle(.button).buttonStyle(.plain).menuIndicator(.hidden).help(help ?? "")
    }

    private func font(for v: T) -> Font {
        if let family = fontFamilyOf?(v) { return .custom(family, size: 12).weight(.semibold) }
        return theme.typography.metaStrong
    }
}
