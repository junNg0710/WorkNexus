/// Ported from: lib/core/widgets/custom_color_dialog.dart
import SwiftUI

/// The free colour picker: the saturation / value area, the hue bar, a hex field and a preview. `onPick` gets the chosen
/// opaque colour as `0xAARRGGBB` (what `AppSettings.accentColorValue` holds). Present it with `.appDialog`.
public struct CustomColorDialog: View {
    @Environment(\.appTheme) private var theme
    @State private var color: HsvColor
    @State private var hex: String
    @State private var invalid = false
    let onPick: (Int) -> Void
    let onClose: () -> Void

    /// - Parameter initial: the colour to start from, `0xAARRGGBB` (alpha ignored).
    public init(initial: Int, onPick: @escaping (Int) -> Void, onClose: @escaping () -> Void) {
        let start = HsvColor(hex: String(format: "#%06X", initial & 0xFFFFFF)) ?? HsvColor(h: 0, s: 0, v: 0)
        _color = State(initialValue: start); _hex = State(initialValue: start.hex)
        self.onPick = onPick; self.onClose = onClose
    }

    /// `0xAARRGGBB` of an `HsvColor`, opaque.
    public static func argb(_ c: HsvColor) -> Int {
        let (r, g, b) = c.rgb
        func byte(_ x: Double) -> Int { Int((min(max(x, 0), 1) * 255).rounded()) }
        return 0xFF00_0000 | (byte(r) << 16) | (byte(g) << 8) | byte(b)
    }

    public var body: some View {
        AppDialogFrame(title: appString("colorCustom", "Custom color"), maxWidth: theme.sizes.dialogSm + theme.spacing.s40 * 2, onClose: onClose) {
            VStack(alignment: .leading, spacing: theme.spacing.s14) {
                HsvSaturationValueArea(color: color, onChange: picked)
                HsvHueBar(color: color, onChange: picked)
                HStack(alignment: .bottom, spacing: theme.spacing.s10) {
                    VStack(alignment: .leading, spacing: theme.spacing.s4) {
                        Text(appString("colorHex", "Hex")).font(theme.typography.label).foregroundStyle(theme.colors.tx2)
                        TextField("#3B82F6", text: $hex).textFieldStyle(.plain).font(theme.typography.mono)
                            .padding(.horizontal, theme.spacing.s10).frame(height: theme.sizes.control36)
                            .background(theme.colors.panel2, in: RoundedRectangle(cornerRadius: theme.radii.md))
                            .overlay(RoundedRectangle(cornerRadius: theme.radii.md)
                                .stroke(invalid ? theme.colors.red : theme.colors.line, lineWidth: theme.borders.hairline))
                            .onChange(of: hex) { _, text in typed(text) }
                        if invalid {
                            Text(appString("colorHexInvalid", "Enter a color like #3B82F6")).font(theme.typography.caption).foregroundStyle(theme.colors.red)
                        }
                    }
                    RoundedRectangle(cornerRadius: theme.radii.md).fill(color.color)
                        .frame(width: theme.sizes.control36 + theme.spacing.s8, height: theme.sizes.control36)
                        .overlay(RoundedRectangle(cornerRadius: theme.radii.md).stroke(theme.colors.line, lineWidth: theme.borders.hairline))
                }
            }
            .padding(.horizontal, theme.spacing.s24).padding(.bottom, theme.spacing.s20)
        } actions: {
            Spacer(minLength: 0)
            AppButton(appString("cancel", "Cancel"), kind: .ghost, action: onClose)
            AppButton(appString("save", "Save"), kind: .primary) { onPick(Self.argb(color)); onClose() }
                .disabled(invalid).opacity(invalid ? 0.5 : 1)
        }
    }

    /// From the area or the hue bar: the hex field follows.
    private func picked(_ c: HsvColor) { color = c; hex = c.hex; invalid = false }

    /// From the hex field: the area and bar follow once it parses; a grey keeps the hue it had.
    private func typed(_ text: String) {
        guard let parsed = HsvColor(hex: text) else { invalid = true; return }
        invalid = false
        if parsed.hex == color.hex { return }   // the echo of a drag
        var next = parsed
        if parsed.s == 0 { next.h = color.h }
        color = next
    }
}
