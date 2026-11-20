/// Ported from: lib/features/chat/presentation/widgets/chat_link_card_frame.dart
import CoreUI
import SwiftUI

/// The box of a compact link card inside a message (merge request, ticket, page preview), shaped like a quote: a tinted
/// block with a bar on its left edge — in the item's state colour (`bar`), else the bubble's quote colour.
struct ChatLinkCardFrame<Content: View>: View {
    @Environment(\.appTheme) private var theme
    @Environment(\.chatBubbleInk) private var ink
    @State private var hovered = false
    let onTap: () -> Void
    var bar: Color?
    var height: CGFloat?
    @ViewBuilder let content: Content

    static var maxWidth: CGFloat { 420 }

    var body: some View {
        let radius = theme.radii.sm
        content
            .padding(.horizontal, theme.spacing.s10).padding(.vertical, height == nil ? theme.spacing.s8 : 0)
            .frame(maxWidth: Self.maxWidth, minHeight: height, maxHeight: height, alignment: .leading)
            .background((hovered ? ink.hoverFill.over(ink.quoteFill) : ink.quoteFill).color, in: RoundedRectangle(cornerRadius: radius))
            .overlay(alignment: .leading) { (bar ?? ink.quoteBar.color).frame(width: 3) }
            .clipShape(RoundedRectangle(cornerRadius: radius))
            .contentShape(RoundedRectangle(cornerRadius: radius))
            .onHover { hovered = $0 }
            .onTapGesture(perform: onTap)
            .pointerStyle(.link)
            .padding(.top, theme.spacing.s8)
    }
}

/// A part of a card's caption line: plain text in the meta colour, or bold in a colour that reads on the card.
enum ChatCardPart {
    case plain(String)
    case strong(String, ChatColor)
}

/// One caption line of parts joined by ` · `.
struct ChatCardLine: View {
    @Environment(\.appTheme) private var theme
    @Environment(\.chatBubbleInk) private var ink
    let parts: [ChatCardPart]

    var body: some View {
        let meta = ChatColor.readable(ink.meta, on: ink.quoteSurface, towards: ink.text).color
        var line = Text(verbatim: "")
        for (i, part) in parts.enumerated() {
            if i > 0 { line = line + Text(verbatim: " · ").foregroundStyle(meta) }
            switch part {
            case .plain(let s): line = line + Text(s).foregroundStyle(meta)
            case .strong(let s, let c):
                line = line + Text(s).font(theme.typography.label).foregroundStyle(ChatColor.readable(c, on: ink.quoteSurface, towards: ink.text).color)
            }
        }
        return line.font(theme.typography.caption).lineLimit(1).truncationMode(.tail)
    }
}

/// A card's title: one bold line.
struct ChatCardTitle: View {
    @Environment(\.appTheme) private var theme
    @Environment(\.chatBubbleInk) private var ink
    let title: String
    var body: some View {
        Text(title).font(theme.typography.bodyStrong).foregroundStyle(ink.text.color).lineLimit(1).truncationMode(.tail)
    }
}
