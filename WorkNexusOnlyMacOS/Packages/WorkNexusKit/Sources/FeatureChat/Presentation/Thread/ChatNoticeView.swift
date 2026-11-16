/// Ported from: lib/features/chat/presentation/widgets/chat_notice.dart
import CoreDomain
import CoreUI
import SwiftUI

/// A server notice about the chat ("@A invited @B to the group"), centered like a date separator rather than drawn as a
/// message from its sender: a bell, the time and the text with its mentions.
struct ChatNoticeView: View {
    @Environment(\.appTheme) private var theme
    @Environment(\.chatStyle) private var style
    @Environment(\.chatSettings) private var settings
    let ctx: ThreadContext
    let message: ChatMessage

    var body: some View {
        let p = style.palette
        let onPicture = chatWallpaperIsPicture(settings.wallpaper)
        // Same look as the style's separators: its own pill, a dark scrim pill over a picture background, or plain text.
        let ownPill = style.separator == .pill
        let scrimPill = onPicture && !ownPill
        let filled = ownPill || scrimPill
        let ink = scrimPill ? ChatColor(theme.colors.onScrim) : p.separatorText
        let text: String = if case .text(let t, let md) = message.content { ChatTextLabels.noticeText(t, markdown: md) } else { ChatTextLabels.preview(message) }
        let noticeInk = ChatBubbleInk(
            text: ink, meta: ink,
            // On a pill the names stand out by weight; plain text over the chat background can take the link colour.
            link: filled ? ink : p.incomingLink, quoteBar: ink, quoteFill: ink, tileFill: ink, fontSize: 12)
        let row = HStack(alignment: .top, spacing: theme.spacing.s6) {
            Image(systemName: "bell").font(.system(size: theme.sizes.icon12)).foregroundStyle((filled ? ink : p.incomingLink).color)
                .padding(.top, theme.spacing.s2)
            Text(ChatTextLabels.clock(message.sentAt)).font(theme.typography.label).foregroundStyle(ink.color)
            MentionTextView(text: text, ctx: ctx).environment(\.chatBubbleInk, noticeInk)
        }
        Group {
            if filled {
                row.padding(.horizontal, theme.spacing.s12).padding(.vertical, theme.spacing.s4)
                    .background(scrimPill ? theme.colors.scrim.opacity(0.45) : (p.separatorFill ?? .clear).color, in: RoundedRectangle(cornerRadius: theme.radii.lg))
            } else {
                row
            }
        }
        .frame(maxWidth: style.maxWidth)
        .frame(maxWidth: .infinity)
        .padding(.vertical, theme.spacing.s4)
    }
}
