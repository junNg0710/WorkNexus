/// Ported from: lib/features/chat/presentation/widgets/chat_bubble_theme.dart
import CoreUI
import SwiftUI

/// Ink for the content of one bubble. Chat styles colour bubbles their own way (Telegram's green outgoing bubble,
/// ZenTao's pale blue one, …), so text, time, links and quotes inside must follow the bubble, not the app theme.
public struct ChatBubbleInk: Hashable, Sendable {
    public var text: ChatColor
    /// Time, sizes, secondary lines.
    public var meta: ChatColor
    /// Links and mentions.
    public var link: ChatColor
    /// Reply quote: the bar on its left edge and its background.
    public var quoteBar: ChatColor
    public var quoteFill: ChatColor
    /// What a quote or link card actually shows as its background: `quoteFill` blended over the bubble and the chat
    /// background (opaque), for checking that coloured text on it stays readable.
    public var quoteSurface: ChatColor
    /// Background of icon tiles (link and file cards) inside the bubble.
    public var tileFill: ChatColor
    /// Message text size of the active chat style.
    public var fontSize: CGFloat
    /// Sender name / reply quote size, and time size; nil keeps the caption ramp.
    public var labelSize: CGFloat?
    public var metaSize: CGFloat?

    public init(text: ChatColor, meta: ChatColor, link: ChatColor, quoteBar: ChatColor, quoteFill: ChatColor,
                quoteSurface: ChatColor? = nil, tileFill: ChatColor, fontSize: CGFloat = 13,
                labelSize: CGFloat? = nil, metaSize: CGFloat? = nil) {
        self.text = text; self.meta = meta; self.link = link; self.quoteBar = quoteBar; self.quoteFill = quoteFill
        self.quoteSurface = quoteSurface ?? quoteFill; self.tileFill = tileFill; self.fontSize = fontSize
        self.labelSize = labelSize; self.metaSize = metaSize
    }

    /// The app theme's ink, for content outside any styled bubble.
    public static func fromTheme(_ c: AppPalette) -> ChatBubbleInk {
        ChatBubbleInk(text: ChatColor(c.tx), meta: ChatColor(c.tx3), link: ChatColor(c.accent), quoteBar: ChatColor(c.accent),
                      quoteFill: ChatColor(c.bg), tileFill: ChatColor(c.bg))
    }

    /// Pointer-hover tint for the cards inside the bubble: the bubble's own ink at low alpha, so it reads on every style.
    public var hoverFill: ChatColor { text.opacity(0.06) }
}

private struct ChatBubbleInkKey: EnvironmentKey { static let defaultValue = ChatBubbleInk.fromTheme(AppTheme().colors) }

public extension EnvironmentValues {
    /// The ink of the bubble being drawn (set by `MessageBubbleBox`'s owner); app-theme ink outside any bubble.
    var chatBubbleInk: ChatBubbleInk {
        get { self[ChatBubbleInkKey.self] }
        set { self[ChatBubbleInkKey.self] = newValue }
    }
}
