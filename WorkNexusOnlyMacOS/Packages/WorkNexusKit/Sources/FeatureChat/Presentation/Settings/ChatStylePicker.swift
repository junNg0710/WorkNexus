/// Ported from: lib/features/chat/presentation/widgets/chat_appearance_settings.dart (`_StyleCard`) + chat_style_preview.dart
import CoreDomain
import CoreUI
import SwiftUI

/// The chat style choice: a card per style showing a miniature chat in it — its separator, an incoming bubble with an avatar and
/// an own bubble, in the style's colours, corner radius and avatar shape — so styles can be compared before picking. Reads
/// `\.chatSettings` (the style in force, accent bubbles); the host saves what `onSelect` reports.
public struct ChatStylePicker: View {
    @Environment(\.appTheme) private var theme
    @Environment(\.chatSettings) private var settings
    let onSelect: (ChatAppearance) -> Void

    public init(onSelect: @escaping (ChatAppearance) -> Void) { self.onSelect = onSelect }

    /// Messenger names are brands and stay as they are in every language.
    static func label(_ a: ChatAppearance) -> String {
        switch a {
        case .worknexus: shellString("chatAppearanceDefault", "Default")
        case .telegram: "Telegram"
        case .zalo: "Zalo"
        case .zentao: "ZenTao"
        case .wechat: "WeChat"
        case .tbchat: "TBChat"
        }
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: theme.spacing.s8) {
            Text(shellString("chatAppearance", "Style")).font(theme.typography.paragraph).foregroundStyle(theme.colors.tx)
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: theme.spacing.s8), count: 3), spacing: theme.spacing.s8) {
                ForEach(ChatAppearance.allCases, id: \.self) { a in
                    StyleCard(appearance: a, selected: a == settings.appearance,
                              style: ChatStyle.resolve(a, theme: theme, primaryBubbles: settings.primaryBubbles)) { onSelect(a) }
                }
            }
        }
    }
}

private struct StyleCard: View {
    @Environment(\.appTheme) private var theme
    let appearance: ChatAppearance
    let selected: Bool
    let style: ChatStyle
    let onTap: () -> Void

    var body: some View {
        let width = theme.spacing.s40 * 3.4, height = theme.spacing.s40 * 2.4
        HoverSurface(onTap: onTap, border: selected ? theme.colors.accent : theme.colors.line, cornerRadius: theme.radii.lg) {
            VStack(spacing: theme.spacing.s6) {
                // Laid out at the size it was designed for, scaled to the card.
                Color.clear.aspectRatio(width / height, contentMode: .fit).overlay {
                    GeometryReader { geo in
                        ChatStylePreview(style: style).frame(width: width, height: height)
                            .scaleEffect(geo.size.width / width, anchor: .topLeading)
                    }
                }
                HStack {
                    Text(ChatStylePicker.label(appearance)).font(theme.typography.metaStrong).foregroundStyle(selected ? theme.colors.accent : theme.colors.tx)
                    Spacer(minLength: 0)
                    if selected { Image(systemName: "checkmark.circle.fill").font(.system(size: theme.sizes.icon14)).foregroundStyle(theme.colors.accent) }
                }
            }
            .padding(theme.spacing.s6)
        }
        .overlay(RoundedRectangle(cornerRadius: theme.radii.lg).stroke(selected ? theme.colors.accent : .clear, lineWidth: theme.borders.thick))
        .accessibilityAddTraits(selected ? [.isButton, .isSelected] : .isButton)
    }
}

/// A miniature chat in `style`: its background, a separator, an incoming bubble with an avatar and an own bubble.
struct ChatStylePreview: View {
    @Environment(\.appTheme) private var theme
    let style: ChatStyle

    var body: some View {
        let p = style.palette
        VStack(spacing: 0) {
            PreviewSeparator(style: style)
            Spacer(minLength: 0)
            HStack(alignment: .bottom, spacing: theme.spacing.s4) {
                PreviewAvatar(style: style)
                PreviewBubble(style: style, mine: false, lines: [1, 0.6])
                Spacer(minLength: 0)
            }
            Spacer(minLength: 0)
            HStack(alignment: .bottom, spacing: theme.spacing.s4) {
                if !style.ownOnLeft { Spacer(minLength: 0) }
                if style.ownAvatar && style.ownOnLeft { PreviewAvatar(style: style) }
                PreviewBubble(style: style, mine: true, lines: [0.8])
                if style.ownAvatar && !style.ownOnLeft { PreviewAvatar(style: style) }
                if style.ownOnLeft { Spacer(minLength: 0) }
            }
        }
        .padding(theme.spacing.s6)
        .background(p.background.color)
        .clipShape(RoundedRectangle(cornerRadius: theme.radii.md))
    }
}

private struct PreviewBubble: View {
    @Environment(\.appTheme) private var theme
    let style: ChatStyle
    let mine: Bool
    /// Widths of the text lines, as fractions of the longest.
    let lines: [Double]

    var body: some View {
        let p = style.palette
        let ink = (mine ? p.outgoingText : p.incomingText).opacity(0.55).color
        let border = mine ? p.outgoingBorder : p.incomingBorder
        // The style's radius, shrunk to fit at preview scale.
        let radius = min(max(style.radius, 0), theme.spacing.s40 / 2)
        VStack(alignment: .leading, spacing: theme.spacing.s2) {
            ForEach(Array(lines.enumerated()), id: \.offset) { _, f in
                Capsule().fill(ink).frame(width: theme.spacing.s40 * 1.6 * f, height: theme.spacing.s4)
            }
        }
        .padding(.horizontal, theme.spacing.s6).padding(.vertical, theme.spacing.s4)
        .background((mine ? p.outgoingBubble : p.incomingBubble).color, in: RoundedRectangle(cornerRadius: radius))
        .overlay { if let border { RoundedRectangle(cornerRadius: radius).stroke(border.color, lineWidth: theme.borders.hairline) } }
    }
}

private struct PreviewAvatar: View {
    @Environment(\.appTheme) private var theme
    let style: ChatStyle

    var body: some View {
        let fill = style.palette.incomingMeta.opacity(0.45).color, side = theme.spacing.s20
        if style.avatarShape == .circle { Circle().fill(fill).frame(width: side, height: side) }
        else { RoundedRectangle(cornerRadius: theme.radii.sm).fill(fill).frame(width: side, height: side) }
    }
}

private struct PreviewSeparator: View {
    @Environment(\.appTheme) private var theme
    let style: ChatStyle

    var body: some View {
        let p = style.palette
        let label = Capsule().fill(p.separatorText.opacity(0.5).color).frame(width: theme.spacing.s40, height: theme.spacing.s4)
        switch style.separator {
        case .pill:
            label.padding(.horizontal, theme.spacing.s6).padding(.vertical, theme.spacing.s2)
                .background((p.separatorFill ?? p.incomingBubble).color, in: Capsule())
        case .plain: label
        case .hairline:
            HStack(spacing: theme.spacing.s4) {
                Rectangle().fill(p.separatorText.opacity(0.3).color).frame(height: theme.borders.hairline)
                label
                Rectangle().fill(p.separatorText.opacity(0.3).color).frame(height: theme.borders.hairline)
            }
        }
    }
}
