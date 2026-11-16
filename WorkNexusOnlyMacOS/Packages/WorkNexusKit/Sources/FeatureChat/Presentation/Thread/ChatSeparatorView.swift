/// Ported from: lib/features/chat/presentation/widgets/chat_separator.dart
import CoreUI
import SwiftUI

/// A centered date or time separator in the chat style's look: a pill (Telegram, Zalo), plain text (ZenTao, WeChat) or
/// text between hairlines. Over a picture background (pattern or image) plain and hairline separators become a dark
/// translucent pill, or they would not read.
struct ChatSeparatorView: View {
    @Environment(\.appTheme) private var theme
    @Environment(\.chatStyle) private var style
    @Environment(\.chatSettings) private var settings
    let label: String

    var body: some View {
        let p = style.palette
        let onPicture = chatWallpaperIsPicture(settings.wallpaper)
        let ownPill = style.separator == .pill
        let scrimPill = onPicture && !ownPill
        let text = Text(label).font(theme.typography.label).foregroundStyle(scrimPill ? theme.colors.onScrim : p.separatorText.color)
        Group {
            if ownPill || scrimPill {
                text.padding(.horizontal, theme.spacing.s12).padding(.vertical, theme.spacing.s4)
                    .background(scrimPill ? theme.colors.scrim.opacity(0.45) : (p.separatorFill ?? .clear).color, in: Capsule())
            } else if style.separator == .hairline {
                HStack(spacing: 0) {
                    theme.colors.line.frame(height: theme.borders.hairline)
                    text.padding(.horizontal, theme.spacing.s12).fixedSize()
                    theme.colors.line.frame(height: theme.borders.hairline)
                }
            } else {
                text
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.top, theme.spacing.s20).padding(.bottom, theme.spacing.s4)
    }
}
