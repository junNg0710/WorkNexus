import CoreUI
import SwiftUI

/// Ported from: lib/features/ticket_editor/presentation/widgets/title_color_input.dart
/// The title's colour: none or one of ZenTao's swatches (`#rrggbb`).
struct TitleColorInput: View {
    @Environment(\.appTheme) private var theme
    let value: String
    let onChanged: (String) -> Void

    var body: some View {
        HStack(spacing: theme.spacing.s8) {
            ForEach([""] + ZenTaoChoices.titleColors, id: \.self) { hex in
                let selected = hex.lowercased() == value.lowercased()
                Button { onChanged(hex) } label: {
                    ZStack {
                        // Colours from ZenTao's data, not the theme.
                        Circle().fill(hex.isEmpty ? theme.colors.panel2 : Self.color(hex))
                        if hex.isEmpty {
                            Image(systemName: "nosign").font(.system(size: theme.sizes.icon12)).foregroundStyle(theme.colors.tx3)
                        }
                    }
                    .frame(width: theme.sizes.control32 - theme.spacing.s6, height: theme.sizes.control32 - theme.spacing.s6)
                    .overlay(Circle().stroke(selected ? theme.colors.tx : theme.colors.line, lineWidth: selected ? theme.borders.thick : theme.borders.hairline))
                }
                .buttonStyle(.plain)
                .help(hex.isEmpty ? appString("selectNone", "None") : hex)
            }
            Spacer(minLength: 0)
        }
    }

    static func color(_ hex: String) -> Color {
        let digits = hex.hasPrefix("#") ? String(hex.dropFirst()) : hex
        return UInt32(digits, radix: 16).map { Color(argb: 0xFF00_0000 | $0) } ?? .clear
    }
}
