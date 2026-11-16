/// Ported from: lib/features/chat/presentation/widgets/chat_style.dart
import CoreDomain
import CoreUI
import SwiftUI

/// Where a sender's avatar sits within a run of their messages.
public enum ChatAvatarPlacement: Sendable { case firstOfRun, lastOfRun, everyMessage }

/// How an avatar is clipped.
public enum ChatAvatarShape: Sendable { case circle, roundedSquare }

/// Where the name of a group-chat sender goes.
public enum ChatNamePlacement: Sendable {
    case aboveBubble, insideBubble
    /// A header over the first bubble of every run, for own messages and one-to-one chats too, with the run's time
    /// beside the name (ZenTao).
    case header
    /// Above the avatar and bubble together, so the avatar lines up with the bubble rather than with the name (TBChat).
    case aboveRow
}

/// Where a message's time goes.
public enum ChatTimePlacement: Sendable {
    /// Under the content, on the last message of a run.
    case belowContent
    /// Bottom-right inside the bubble, on every message (Telegram).
    case insideEnd
    /// Bottom inside the bubble, on every message, on the side the bubble is aligned to (TBChat).
    case insideAligned
    /// Not on messages: centered time separators after pauses instead.
    case separators
    /// In the run's header, beside the name (`ChatNamePlacement.header`).
    case header
}

/// Where a reply's quote of the original goes.
public enum ChatQuotePlacement: Sendable { case inside, above, below }

/// How date and time separators look.
public enum ChatSeparatorStyle: Sendable { case hairline, pill, plain }

/// Layout metrics and colours of one `ChatAppearance`, modelled on the real apps (Telegram from its open-source
/// palette and styles).
public struct ChatStyle {
    public var palette: ChatStylePalette
    public var avatar: ChatAvatarPlacement
    public var avatarShape: ChatAvatarShape
    public var avatarSize: CGFloat
    /// Own messages also get an avatar (on the right).
    public var ownAvatar: Bool
    /// Show avatars in one-to-one chats too (Telegram hides them).
    public var avatarInDirectChats: Bool
    public var name: ChatNamePlacement
    public var time: ChatTimePlacement
    public var quote: ChatQuotePlacement
    public var separator: ChatSeparatorStyle
    /// Pause after which a centered time separator is shown (nil = never).
    public var separatorGap: TimeInterval?
    /// Bubble corner radius, and the radius where bubbles of a run touch.
    public var radius: CGFloat
    public var joinRadius: CGFloat
    public var tail: BubbleTailKind?
    public var padding: EdgeInsets
    public var maxWidth: CGFloat
    /// Vertical space between bubbles of one run, and between runs.
    public var runGap: CGFloat
    public var groupGap: CGFloat
    /// Message text size.
    public var fontSize: CGFloat
    /// Show a sent tick after the time of own messages.
    public var ticks: Bool
    /// Size of the sender name and reply quote inside a bubble; nil keeps the caption ramp. Telegram sets them at the message size.
    public var labelSize: CGFloat?
    /// Size of the time; nil keeps the caption ramp.
    public var metaSize: CGFloat?
    /// A thread root shows its reply count beside the time (Telegram) instead of a chip of repliers under the bubble.
    public var threadInMeta = false
    /// A reply quote in an incoming bubble takes the quoted sender's name colour for its bar, tint and name (Telegram).
    public var quoteInSenderColor = false
    /// Own messages sit on the left with the others', their avatar before them (ZenTao); otherwise they are on the right.
    public var ownOnLeft = false

    /// The style `appearance` draws in `theme`. `primaryBubbles` gives the messenger styles' own bubbles the app's
    /// accent (the default style already follows the theme).
    public static func resolve(_ appearance: ChatAppearance, theme: AppTheme, primaryBubbles: Bool = false) -> ChatStyle {
        let dark = theme.colors.isDark
        // The background is shared by every style (the chat wallpaper setting): a style only shapes and colours bubbles,
        // avatars and separators.
        var style = chatStyleSpec(appearance, theme: theme, dark: dark)
        style.palette = style.palette.withBackground(ChatColor(theme.colors.bg))
        if primaryBubbles && appearance != .worknexus {
            style.palette = style.palette.withPrimaryBubbles(accent: ChatColor(theme.colors.accent), dark: dark)
        }
        return style
    }

    /// Whether a message lines up with the right edge.
    public func alignEnd(mine: Bool) -> Bool { mine && !ownOnLeft }

    /// Whether the time inside a bubble aligned so (`alignEnd`) is pinned to its bottom-end corner, rather than on a row of its own.
    public func timeAtEnd(alignEnd: Bool) -> Bool {
        switch time {
        case .insideEnd: true
        case .insideAligned: alignEnd
        default: false
        }
    }

    /// Colour for a sender's name.
    public func nameColor(_ senderId: Int) -> ChatColor {
        guard let colors = palette.nameColors, !colors.isEmpty else { return palette.incomingMeta }
        return colors[((senderId % colors.count) + colors.count) % colors.count]
    }

    public func bubbleFill(mine: Bool) -> ChatColor { mine ? palette.outgoingBubble : palette.incomingBubble }
    public func bubbleBorder(mine: Bool) -> ChatColor? { mine ? palette.outgoingBorder : palette.incomingBorder }

    /// Ink for content inside a bubble.
    public func ink(mine: Bool) -> ChatBubbleInk {
        let p = palette
        let bar = mine ? p.outgoingQuoteBar : p.incomingQuoteBar
        let text = mine ? p.outgoingText : p.incomingText
        // Light ink on a dark or saturated bubble (night themes) needs a stronger tint for quotes and tiles to read as a
        // separate area; dark ink on a pale bubble needs only a hint.
        let surface = bubbleFill(mine: mine).over(p.background)
        let strong = surface.luminance < 0.2
        let quoteFill = (mine ? p.outgoingQuoteFill : nil) ?? p.quoteFill
            ?? (strong ? ChatStylePalette.darkInset : bar.opacity(0.12))
        return ChatBubbleInk(
            text: text, meta: mine ? p.outgoingMeta : p.incomingMeta, link: mine ? p.outgoingLink : p.incomingLink,
            quoteBar: bar, quoteFill: quoteFill, quoteSurface: quoteFill.over(surface),
            tileFill: text.opacity(strong ? 0.16 : 0.06), fontSize: fontSize, labelSize: labelSize, metaSize: metaSize)
    }

    /// Ink for a reply quote drawn outside the bubble, on the chat background (Messenger above, WeChat below): a muted
    /// grey box, not the app accent, so it reads as context rather than as a message of its own.
    public func outsideQuoteInk() -> ChatBubbleInk {
        let p = palette
        let text = p.outsideQuoteText ?? p.incomingMeta
        let fill = p.outsideQuoteFill ?? p.incomingBubble
        return ChatBubbleInk(text: text, meta: text, link: p.incomingLink, quoteBar: text, quoteFill: fill,
                             quoteSurface: fill.over(p.background), tileFill: text.opacity(0.06), fontSize: fontSize)
    }

    /// Bubble corners for its place in a run: corners where bubbles of a run touch use `joinRadius`; the tail corner is
    /// square so the tail joins.
    public func corners(mine: Bool, firstOfRun: Bool, lastOfRun: Bool, withTail: Bool) -> BubbleCorners {
        func corner(top: Bool, senderSide: Bool) -> CGFloat {
            if !senderSide { return radius }
            if withTail, tail == .curlBottom, !top { return 0 }
            let edge = top ? firstOfRun : lastOfRun
            return edge ? radius : joinRadius
        }
        return BubbleCorners(topLeft: corner(top: true, senderSide: !mine), topRight: corner(top: true, senderSide: mine),
                             bottomLeft: corner(top: false, senderSide: !mine), bottomRight: corner(top: false, senderSide: mine))
    }
}

private struct ChatStyleKey: EnvironmentKey {
    static let defaultValue = ChatStyle.resolve(.worknexus, theme: AppTheme())
}

public extension EnvironmentValues {
    /// The chat style in force (see `View.chatStyleScope()`).
    var chatStyle: ChatStyle {
        get { self[ChatStyleKey.self] }
        set { self[ChatStyleKey.self] = newValue }
    }
}

/// Resolves `\.chatStyle` from `\.chatSettings` (appearance, primary bubbles) and `\.appTheme`, so everything below
/// draws in the user's chat style and follows changes of either.
struct ChatStyleScope: ViewModifier {
    @Environment(\.chatSettings) private var settings
    @Environment(\.appTheme) private var theme
    func body(content: Content) -> some View {
        content.environment(\.chatStyle, ChatStyle.resolve(settings.appearance, theme: theme, primaryBubbles: settings.primaryBubbles))
    }
}

public extension View {
    /// Provides `\.chatStyle` resolved from the injected chat settings and theme.
    func chatStyleScope() -> some View { modifier(ChatStyleScope()) }
}
