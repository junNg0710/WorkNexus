/// Ported from: lib/features/chat/presentation/widgets/chat_wallpaper_colors.dart
import CoreDomain
import CoreUI
import SwiftUI

/// The wallpaper colours under the colour tile: the app's plain background, the presets (each in the theme's shade), a last
/// swatch that opens a free picker right below them, and — once a colour is the wallpaper — whether the doodle pattern is
/// drawn over it.
struct ChatWallpaperColors: View {
    @Environment(\.appTheme) private var theme
    @Environment(\.chatSettings) private var settings
    let onSelect: (String) -> Void
    @State private var picking = false

    var body: some View {
        let dark = theme.colors.isDark
        // What is on screen, so the swatches follow a colour being dragged.
        let shown = ChatWallpaperPreview.shared.shown(saved: settings.wallpaper)
        let chosen = ChatWallpaperColor.parse(shown)
        let preset = ChatWallpaperTint.presets.first { $0.id == chosen?.color }
        let custom = chosen != nil && preset == nil ? ChatDoodlePalette.forColor(chosen!.color, dark: dark)?.base : nil
        let doodles = chosen?.doodles ?? true
        let plain = !chatWallpaperIsPicture(shown)
        VStack(alignment: .leading, spacing: theme.spacing.s12) {
            FlowLayout(spacing: theme.spacing.s4) {
                AppSwatchButton(size: swatch, color: theme.colors.bg, selected: plain, help: shellString("chatWallpaperDefault", "Default")) {
                    picking = false; ChatWallpaperPreview.shared.clear(); onSelect(ChatWallpaperColor.plain)
                }
                ForEach(ChatWallpaperTint.presets, id: \.id) { tint in
                    AppSwatchButton(size: swatch, color: tint.of(dark: dark).color, selected: preset == tint) {
                        picking = false; ChatWallpaperPreview.shared.clear()
                        // A new colour keeps the pattern choice; the first one starts with it.
                        onSelect(ChatWallpaperColor(tint.id, doodles: doodles).value)
                    }
                }
                AppSwatchButton(size: swatch, color: custom?.color, selected: custom != nil || picking,
                                help: shellString("colorCustom", "Custom colour")) { picking.toggle() }
            }
            if picking {
                ChatWallpaperCustomColor(initial: custom ?? (preset ?? .green).of(dark: dark), doodles: doodles, onSave: onSelect)
            }
            if let chosen {
                HStack {
                    Text(shellString("chatWallpaperDoodles", "Pattern over the colour")).font(theme.typography.paragraph).foregroundStyle(theme.colors.tx)
                    Spacer(minLength: theme.spacing.s12)
                    Toggle("", isOn: Binding(get: { chosen.doodles }, set: { var c = chosen; c.doodles = $0; onSelect(c.value) }))
                        .labelsHidden().toggleStyle(.switch).controlSize(.small)
                }
            }
        }
    }

    private var swatch: CGFloat { theme.sizes.control32 - theme.spacing.s4 }
}
