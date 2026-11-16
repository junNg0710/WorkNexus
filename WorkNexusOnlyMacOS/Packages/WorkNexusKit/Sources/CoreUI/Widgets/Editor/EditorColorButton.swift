import SwiftUI

/// Ported from: lib/core/widgets/editor_color_button.dart
/// The rich-text toolbar's text-colour (or, with `isBackground`, highlight) button: the glyph over a bar in the
/// selection's colour; a click drops down "default" over the 24-swatch grid and a "custom colour" swatch that opens
/// the colour picker.
struct EditorColorButton: View {
    @Environment(\.appTheme) private var theme
    let commands: RichEditorCommands
    let isBackground: Bool
    @State private var open = false
    @State private var customOpen = false

    private var current: String? {
        EditorTextColors.normalized(isBackground ? commands.activeInline.background : commands.activeInline.color)
    }

    /// `#rrggbb` as the `0xAARRGGBB` the colour dialog takes.
    private static func argb(_ hex: String) -> Int { 0xFF00_0000 | (HsvColor.parseHex(hex).map { Int($0.0 * 255) << 16 | Int($0.1 * 255) << 8 | Int($0.2 * 255) } ?? 0) }

    private func apply(_ hex: String?) {
        open = false; customOpen = false
        if isBackground { commands.setBackground(hex) } else { commands.setColor(hex) }
    }

    var body: some View {
        Button { open.toggle() } label: {
            VStack(spacing: theme.spacing.s2) {
                Image(systemName: isBackground ? "highlighter" : "textformat").font(.system(size: theme.sizes.icon14))
                    .foregroundStyle(theme.colors.tx2)
                Capsule().fill(current.flatMap { HsvColor(hex: $0)?.color } ?? theme.colors.line2)
                    .frame(width: theme.sizes.icon14, height: theme.spacing.s4 - theme.borders.hairline)
            }
            .frame(width: theme.sizes.control32 - theme.spacing.s4, height: theme.sizes.control32 - theme.spacing.s4)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(isBackground ? appString("editorHighlightColor", "Highlight colour") : appString("editorTextColor", "Text colour"))
        .popover(isPresented: $open, arrowEdge: .bottom) { EditorColorPalette(current: current, onPick: apply, onCustom: { open = false; customOpen = true }) }
        .appDialog(isPresented: $customOpen) {
            CustomColorDialog(initial: Self.argb(current ?? (isBackground ? "#fbeeb8" : "#e03e2d")),
                              onPick: { apply(String(format: "#%06x", $0 & 0xFFFFFF)) }, onClose: { customOpen = false })
        }
    }
}

/// The drop-down: "default" (no colour) over the swatch grid, then the "pick your own" swatch.
struct EditorColorPalette: View {
    @Environment(\.appTheme) private var theme
    let current: String?
    let onPick: (String?) -> Void
    let onCustom: () -> Void

    var body: some View {
        let swatch = theme.sizes.control32 - theme.spacing.s6
        let columns = Array(repeating: GridItem(.fixed(swatch), spacing: theme.spacing.s6), count: EditorTextColors.columns)
        VStack(alignment: .leading, spacing: theme.spacing.s8) {
            HoverSurface(onTap: { onPick(nil) }, selected: current == nil) {
                HStack(spacing: theme.spacing.s8) {
                    Image(systemName: "circle.slash").font(.system(size: theme.sizes.icon14)).foregroundStyle(theme.colors.tx3)
                    Text(appString("colorDefault", "Default")).font(theme.typography.meta).foregroundStyle(theme.colors.tx)
                    Spacer(minLength: 0)
                }
                .padding(.horizontal, theme.spacing.s8).padding(.vertical, theme.spacing.s6)
            }
            LazyVGrid(columns: columns, spacing: theme.spacing.s6) {
                ForEach(EditorTextColors.swatches, id: \.self) { hex in
                    EditorSwatch(hex: hex, size: swatch, selected: hex == current) { onPick(hex) }
                }
            }
            HStack(spacing: theme.spacing.s8) {
                AppSwatchButton(size: swatch, color: nil, selected: current.map { !EditorTextColors.swatches.contains($0) } ?? false,
                                help: appString("colorCustom", "Custom color"), action: onCustom)
                Text(appString("colorCustom", "Custom color")).font(theme.typography.meta).foregroundStyle(theme.colors.tx2)
            }
        }
        .padding(theme.spacing.s12)
        .frame(width: swatch * CGFloat(EditorTextColors.columns) + theme.spacing.s6 * CGFloat(EditorTextColors.columns - 1) + theme.spacing.s24)
    }
}

/// One square swatch: a ring while hovered, a check on the selected one that reads on its colour.
private struct EditorSwatch: View {
    @Environment(\.appTheme) private var theme
    let hex: String; let size: CGFloat; let selected: Bool; let action: () -> Void

    var body: some View {
        HoverRegion { hovered in
            Button(action: action) {
                RoundedRectangle(cornerRadius: theme.radii.sm).fill(HsvColor(hex: hex)?.color ?? .clear)
                    .overlay {
                        if selected {
                            Image(systemName: "checkmark").font(.system(size: theme.sizes.icon14, weight: .bold))
                                .foregroundStyle(EditorTextColors.prefersDarkInk(on: hex) ? theme.colors.onColorInk : theme.colors.onScrim)
                        }
                    }
                    .overlay(RoundedRectangle(cornerRadius: theme.radii.sm)
                        .stroke(selected ? theme.colors.tx : (hovered ? theme.colors.line2 : theme.colors.line),
                                lineWidth: selected || hovered ? theme.borders.thick : theme.borders.hairline))
                    .frame(width: size, height: size)
            }
            .buttonStyle(.plain)
        }
        .help(hex)
    }
}
