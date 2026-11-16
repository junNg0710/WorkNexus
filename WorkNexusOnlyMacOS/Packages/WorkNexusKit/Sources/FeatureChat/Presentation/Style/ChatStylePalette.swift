/// Ported from: lib/core/theme/chat_style_palette.dart
import CoreUI
import SwiftUI

/// Colour tokens of one chat style (`ChatAppearance`) in one brightness. Each starts from the real app's colours
/// (Telegram Desktop's palette and night theme, WeChat's PC client, best matches for Zalo and ZenTao) and is then tuned
/// for WCAG contrast against its bubble: message text >= 7:1, and times, links, sender names, quote headers and
/// separator labels >= 4.5:1. This file is a token table, so it holds literal ARGB values.
public struct ChatStylePalette: Hashable, Sendable {
    /// Chat area behind the messages.
    public var background: ChatColor
    public var incomingBubble: ChatColor
    public var incomingText: ChatColor
    /// Time and secondary text in incoming bubbles.
    public var incomingMeta: ChatColor
    public var incomingLink: ChatColor
    public var incomingQuoteBar: ChatColor
    public var outgoingBubble: ChatColor
    public var outgoingText: ChatColor
    public var outgoingMeta: ChatColor
    public var outgoingLink: ChatColor
    public var outgoingQuoteBar: ChatColor
    /// Date/time separators: text colour (and, below, the pill fill; nil = plain text).
    public var separatorText: ChatColor
    /// Bubble outlines (Zalo, TBChat); nil = no border.
    public var incomingBorder: ChatColor?
    public var outgoingBorder: ChatColor?
    public var separatorFill: ChatColor?
    /// Per-sender name colours (Telegram); nil = `incomingMeta`.
    public var nameColors: [ChatColor]?
    /// Sent ticks on outgoing bubbles (Telegram); nil = none.
    public var outgoingTicks: ChatColor?
    /// Quote background; nil = the quote bar colour at low opacity.
    public var quoteFill: ChatColor?
    /// Quote/card background in outgoing bubbles, when it differs from `quoteFill`.
    public var outgoingQuoteFill: ChatColor?
    /// A reply quote shown outside the bubble (WeChat): its box and text; nil = the incoming bubble colour and `incomingMeta`.
    public var outsideQuoteFill: ChatColor?
    public var outsideQuoteText: ChatColor?

    /// Quote/card background inside a dark or saturated bubble: a darker inset keeps light text readable.
    public static let darkInset = ChatColor(0x2E00_0000)

    public init(background: ChatColor, incomingBubble: ChatColor, incomingText: ChatColor, incomingMeta: ChatColor,
                incomingLink: ChatColor, incomingQuoteBar: ChatColor, outgoingBubble: ChatColor, outgoingText: ChatColor,
                outgoingMeta: ChatColor, outgoingLink: ChatColor, outgoingQuoteBar: ChatColor, separatorText: ChatColor,
                incomingBorder: ChatColor? = nil, outgoingBorder: ChatColor? = nil, separatorFill: ChatColor? = nil,
                nameColors: [ChatColor]? = nil, outgoingTicks: ChatColor? = nil, quoteFill: ChatColor? = nil,
                outgoingQuoteFill: ChatColor? = nil, outsideQuoteFill: ChatColor? = nil, outsideQuoteText: ChatColor? = nil) {
        self.background = background; self.incomingBubble = incomingBubble; self.incomingText = incomingText
        self.incomingMeta = incomingMeta; self.incomingLink = incomingLink; self.incomingQuoteBar = incomingQuoteBar
        self.outgoingBubble = outgoingBubble; self.outgoingText = outgoingText; self.outgoingMeta = outgoingMeta
        self.outgoingLink = outgoingLink; self.outgoingQuoteBar = outgoingQuoteBar; self.separatorText = separatorText
        self.incomingBorder = incomingBorder; self.outgoingBorder = outgoingBorder; self.separatorFill = separatorFill
        self.nameColors = nameColors; self.outgoingTicks = outgoingTicks; self.quoteFill = quoteFill
        self.outgoingQuoteFill = outgoingQuoteFill; self.outsideQuoteFill = outsideQuoteFill; self.outsideQuoteText = outsideQuoteText
    }

    /// The default style follows the app theme. Secondary text uses the theme's secondary (not tertiary) ink, which keeps
    /// >= 4.5:1 on the tinted own bubble; quotes and link cards are neutral — grey in incoming, white in own bubbles.
    public static func fromTheme(_ c: AppPalette) -> ChatStylePalette {
        let bg = ChatColor(c.bg), card = ChatColor(c.card), tx = ChatColor(c.tx), tx2 = ChatColor(c.tx2)
        let accent = ChatColor(c.accent), panel = ChatColor(c.panel)
        // `card` (white in light mode) rather than the sidebar grey, which sits too close to the chat background. The own
        // bubble is an accent tint over it; a dark theme gets a weaker tint, or secondary text on it drops below 4.5:1.
        let dark = bg.luminance < 0.2
        let own = accent.opacity(dark ? 0.16 : 0.26).over(card)
        return ChatStylePalette(
            background: bg, incomingBubble: card, incomingText: tx, incomingMeta: tx2, incomingLink: accent,
            incomingQuoteBar: accent, outgoingBubble: own, outgoingText: tx, outgoingMeta: tx2,
            // The accent on the accent-tinted own bubble falls a little short.
            outgoingLink: .readable(accent, on: own, towards: tx), outgoingQuoteBar: accent, separatorText: tx2,
            quoteFill: bg, outgoingQuoteFill: panel)
    }

    /// This palette with own bubbles in the app's accent instead of the style's own colour: an accent tint over the
    /// incoming bubble with normal text, so contrast stays as in the theme.
    public func withPrimaryBubbles(accent: ChatColor, dark: Bool) -> ChatStylePalette {
        var p = self
        p.outgoingBubble = accent.opacity(dark ? 0.32 : 0.16).over(incomingBubble)
        p.outgoingText = incomingText; p.outgoingMeta = incomingMeta
        p.outgoingLink = accent; p.outgoingQuoteBar = accent
        p.outgoingBorder = outgoingBorder == nil ? nil : accent.opacity(0.35).over(incomingBubble)
        p.outgoingTicks = outgoingTicks == nil ? nil : accent
        // `outgoingQuoteFill` suits the style's own bubble, not the accent one.
        p.outgoingQuoteFill = nil
        return p
    }

    /// This palette over another chat background: every style shows on the one background the user picked.
    public func withBackground(_ color: ChatColor) -> ChatStylePalette { var p = self; p.background = color; return p }

    // MARK: Telegram

    private static let tgNamesDay: [ChatColor] = ([0xFFC0_3D33, 0xFF3D_8623, 0xFF9A_6D04, 0xFF14_7CB9, 0xFF85_44D6, 0xFFCD_4073, 0xFF23_8194, 0xFFB8_5C18] as [UInt32]).map(ChatColor.init)
    private static let tgNamesNight: [ChatColor] = ([0xFFFB_6169, 0xFF85_DE85, 0xFFF3_BC5C, 0xFF65_BDF3, 0xFFB4_8BF2, 0xFFFF_5694, 0xFF62_D4E3, 0xFFFA_A357] as [UInt32]).map(ChatColor.init)

    public static let telegramDay = ChatStylePalette(
        background: ChatColor(0xFFA9_C08E), incomingBubble: ChatColor(0xFFFF_FFFF), incomingText: ChatColor(0xFF00_0000),
        incomingMeta: ChatColor(0xFF67_7887), incomingLink: ChatColor(0xFF14_7CB9), incomingQuoteBar: ChatColor(0xFF1B_71A3),
        outgoingBubble: ChatColor(0xFFEF_FDDE), outgoingText: ChatColor(0xFF00_0000), outgoingMeta: ChatColor(0xFF43_7F3E),
        outgoingLink: ChatColor(0xFF37_8124), outgoingQuoteBar: ChatColor(0xFF37_7430),
        // Near-opaque: the pill sits on whichever background the user picked.
        separatorText: ChatColor(0xFFFF_FFFF), separatorFill: ChatColor(0xF240_5A33), nameColors: tgNamesDay,
        outgoingTicks: ChatColor(0xFF4A_A140))

    public static let telegramNight = ChatStylePalette(
        background: ChatColor(0xFF0B_121B), incomingBubble: ChatColor(0xFF1E_2C3A), incomingText: ChatColor(0xFFF5_F5F5),
        incomingMeta: ChatColor(0xFF84_93A1), incomingLink: ChatColor(0xFF70_BAF5), incomingQuoteBar: ChatColor(0xFF42_9BDB),
        outgoingBubble: ChatColor(0xFF2B_5278), outgoingText: ChatColor(0xFFFF_FFFF), outgoingMeta: ChatColor(0xFFA8_C5E1),
        outgoingLink: ChatColor(0xFF83_CAFF), outgoingQuoteBar: ChatColor(0xFF65_B9F4),
        separatorText: ChatColor(0xFFFF_FFFF), separatorFill: ChatColor(0xD521_3040), nameColors: tgNamesNight,
        outgoingTicks: ChatColor(0xFF6B_BFFF))

    // MARK: Zalo

    public static let zaloLight = ChatStylePalette(
        background: ChatColor(0xFFEE_F0F3), incomingBubble: ChatColor(0xFFFF_FFFF), incomingText: ChatColor(0xFF08_1C36),
        incomingMeta: ChatColor(0xFF63_7894), incomingLink: ChatColor(0xFF00_68FF), incomingQuoteBar: ChatColor(0xFF00_65F7),
        outgoingBubble: ChatColor(0xFFD3_E5FF), outgoingText: ChatColor(0xFF08_1C36), outgoingMeta: ChatColor(0xFF54_677E),
        outgoingLink: ChatColor(0xFF00_5CE2), outgoingQuoteBar: ChatColor(0xFF00_65F7), separatorText: ChatColor(0xFF5A_6D86),
        incomingBorder: ChatColor(0xFFD6_DBE1), outgoingBorder: ChatColor(0xFFA9_C8F2), separatorFill: ChatColor(0x99FF_FFFF),
        quoteFill: ChatColor(0xFFF0_F4FA))

    public static let zaloDark = ChatStylePalette(
        background: ChatColor(0xFF16_191D), incomingBubble: ChatColor(0xFF2A_2E33), incomingText: ChatColor(0xFFE3_E5E8),
        incomingMeta: ChatColor(0xFF8B_97A6), incomingLink: ChatColor(0xFF4D_9BFF), incomingQuoteBar: ChatColor(0xFF4D_9BFF),
        outgoingBubble: ChatColor(0xFF1B_4A82), outgoingText: ChatColor(0xFFF2_F5F8), outgoingMeta: ChatColor(0xFFA9_C1E0),
        outgoingLink: ChatColor(0xFF9C_C8FF), outgoingQuoteBar: ChatColor(0xFF9C_C8FF), separatorText: ChatColor(0xFFB8_C2CE),
        incomingBorder: ChatColor(0xFF35_3A40), outgoingBorder: ChatColor(0xFF24_5A99), separatorFill: ChatColor(0xFF2A_2E33))

    // MARK: ZenTao

    /// ZenTao's chat as its own client draws it: a pale blue bubble for own messages and a light grey one for the
    /// others, dark text, blue links.
    public static let zentaoLight = ChatStylePalette(
        background: ChatColor(0xFFFF_FFFF), incomingBubble: ChatColor(0xFFF0_F1F3), incomingText: ChatColor(0xFF1F_2430),
        incomingMeta: ChatColor(0xFF66_6E7A), incomingLink: ChatColor(0xFF15_58C8), incomingQuoteBar: ChatColor(0xFF66_6E7A),
        outgoingBubble: ChatColor(0xFFD9_E8FF), outgoingText: ChatColor(0xFF1F_2430), outgoingMeta: ChatColor(0xFF4F_5B6D),
        outgoingLink: ChatColor(0xFF15_58C8), outgoingQuoteBar: ChatColor(0xFF15_58C8), separatorText: ChatColor(0xFF5A_6270),
        nameColors: [ChatColor(0xFF1F_2430)])

    public static let zentaoDark = ChatStylePalette(
        background: ChatColor(0xFF00_0000), incomingBubble: ChatColor(0xFF2A_2E35), incomingText: ChatColor(0xFFE6_EBF2),
        incomingMeta: ChatColor(0xFFA7_B3C4), incomingLink: ChatColor(0xFF8D_B9FF), incomingQuoteBar: ChatColor(0xFFA7_B3C4),
        outgoingBubble: ChatColor(0xFF1E_3A5F), outgoingText: ChatColor(0xFFE6_EBF2), outgoingMeta: ChatColor(0xFFB4_C5DC),
        outgoingLink: ChatColor(0xFF8D_B9FF), outgoingQuoteBar: ChatColor(0xFF8D_B9FF), separatorText: ChatColor(0xFFA7_B3C4),
        nameColors: [ChatColor(0xFFE6_EBF2)])

    // MARK: WeChat

    public static let wechatLight = ChatStylePalette(
        background: ChatColor(0xFFE8_E8E8), incomingBubble: ChatColor(0xFFFF_FFFF), incomingText: ChatColor(0xFF19_1919),
        incomingMeta: ChatColor(0xFF76_7676), incomingLink: ChatColor(0xFF57_6B95), incomingQuoteBar: ChatColor(0xFF57_6B95),
        outgoingBubble: ChatColor(0xFFAD_D897), outgoingText: ChatColor(0xFF0F_170A), outgoingMeta: ChatColor(0xFF3D_5E2C),
        outgoingLink: ChatColor(0xFF2F_4F1F), outgoingQuoteBar: ChatColor(0xFF2F_4F1F), separatorText: ChatColor(0xFF68_6868),
        quoteFill: ChatColor(0x0F00_0000),
        // A pale wash on the green own bubble: a dark tint turns it muddy.
        outgoingQuoteFill: ChatColor(0x99FF_FFFF), outsideQuoteFill: ChatColor(0xFFDA_DADA), outsideQuoteText: ChatColor(0xFF4C_4C4C))

    public static let wechatDark = ChatStylePalette(
        background: ChatColor(0xFF11_1111), incomingBubble: ChatColor(0xFF2C_2C2C), incomingText: ChatColor(0xFFD5_D5D5),
        incomingMeta: ChatColor(0xFF93_9393), incomingLink: ChatColor(0xFF82_94AC), incomingQuoteBar: ChatColor(0xFF7E_91AA),
        outgoingBubble: ChatColor(0xFF37_A169), outgoingText: ChatColor(0xFF00_0000), outgoingMeta: ChatColor(0xFF10_2E1E),
        outgoingLink: ChatColor(0xFF0A_2E1D), outgoingQuoteBar: ChatColor(0xFF07_1F13), separatorText: ChatColor(0xFF8C_8C8C),
        quoteFill: ChatColor(0x1400_0000), outgoingQuoteFill: ChatColor(0x4DFF_FFFF),
        outsideQuoteFill: ChatColor(0xFF26_2626), outsideQuoteText: ChatColor(0xFFB2_B2B2))

    // MARK: TBChat

    private static let tbNamesLight: [ChatColor] = ([0xFFC0_3D33, 0xFF1F_8A4C, 0xFF9A_6D04, 0xFF14_7CB9, 0xFF85_44D6, 0xFFCD_4073, 0xFF23_8194, 0xFFB8_5C18] as [UInt32]).map(ChatColor.init)
    private static let tbNamesDark: [ChatColor] = ([0xFFFF_8A80, 0xFF7F_DC9A, 0xFFF3_BC5C, 0xFF65_BDF3, 0xFFB9_A0F5, 0xFFFF_7FAE, 0xFF62_D4E3, 0xFFFA_A357] as [UInt32]).map(ChatColor.init)

    /// The TBChat client's bubbles (tbchat_socialfi `PrimaryColorsApi.bubbleColor` / `otherSideBubbleColor`, a 6% black
    /// hairline): pale green own, white other; text black, secondary text black at 65% (made opaque); quote bars the
    /// app's green. Links use a darker green, which reads on both.
    public static let tbchatLight = ChatStylePalette(
        background: ChatColor(0xFFEA_E6DF), incomingBubble: ChatColor(0xFFFF_FFFF), incomingText: ChatColor(0xFF00_0000),
        incomingMeta: ChatColor(0xFF59_5959), incomingLink: ChatColor(0xFF0A_7A3D), incomingQuoteBar: ChatColor(0xFF0D_CC61),
        outgoingBubble: ChatColor(0xFFD4_FDD1), outgoingText: ChatColor(0xFF00_0000), outgoingMeta: ChatColor(0xFF4A_5949),
        outgoingLink: ChatColor(0xFF0A_7A3D), outgoingQuoteBar: ChatColor(0xFF0D_CC61), separatorText: ChatColor(0xFF54_656F),
        incomingBorder: ChatColor(0x0F00_0000), outgoingBorder: ChatColor(0x0F00_0000),
        // Near-opaque: the pill sits on whichever background the user picked.
        separatorFill: ChatColor(0xF2FF_FFFF), nameColors: tbNamesLight, quoteFill: ChatColor(0x0F00_0000),
        outgoingQuoteFill: ChatColor(0x99FF_FFFF))

    /// TBChat's dark bubbles: deep green own, slate other, a 12% white hairline; text white, secondary white at 65%.
    public static let tbchatDark = ChatStylePalette(
        background: ChatColor(0xFF0B_141A), incomingBubble: ChatColor(0xFF18_2025), incomingText: ChatColor(0xFFFF_FFFF),
        incomingMeta: ChatColor(0xFFAE_B1B3), incomingLink: ChatColor(0xFF5F_E39A), incomingQuoteBar: ChatColor(0xFF0D_CC61),
        outgoingBubble: ChatColor(0xFF00_4E35), outgoingText: ChatColor(0xFFFF_FFFF), outgoingMeta: ChatColor(0xFFA6_C1B8),
        outgoingLink: ChatColor(0xFF7D_EBB0), outgoingQuoteBar: ChatColor(0xFF0D_CC61), separatorText: ChatColor(0xFFB4_C0C6),
        incomingBorder: ChatColor(0x1FFF_FFFF), outgoingBorder: ChatColor(0x1FFF_FFFF), separatorFill: ChatColor(0xF218_2229),
        nameColors: tbNamesDark, quoteFill: ChatColor(0x14FF_FFFF), outgoingQuoteFill: ChatColor(0x3300_0000))
}
