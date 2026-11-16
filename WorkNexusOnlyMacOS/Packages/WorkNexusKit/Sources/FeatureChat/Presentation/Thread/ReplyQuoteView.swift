/// Ported from: lib/features/chat/presentation/widgets/reply_quote.dart
import CoreDomain
import CoreUI
import SwiftUI

/// The message a reply answers, quoted above the reply. Fetches it from the server when it is older than what is loaded.
/// Tap jumps to it in the chat.
struct ReplyQuoteView: View {
    @Environment(\.appTheme) private var theme
    @Environment(\.chatBubbleInk) private var ink
    @State private var hovered = false
    @State private var original: ChatMessage?
    let ctx: ThreadContext
    let replyToId: Int
    let onTap: () -> Void
    /// When set, the quote takes the quoted sender's colour for its bar, tint and name (Telegram) instead of the bubble's quote ink.
    var senderColor: ((Int) -> ChatColor)?

    var body: some View {
        let accent = original.flatMap { m in senderColor?(m.senderId) }
        let bar = accent ?? ink.quoteBar
        let fill = accent?.opacity(0.12) ?? ink.quoteFill
        let label = ink.labelSize.map { theme.typography.font(size: $0) } ?? theme.typography.caption
        HStack(spacing: theme.spacing.s8) {
            if let m = original, ReplyMediaThumbView.shows(m.content), !m.deleted {
                ReplyMediaThumbView(ctx: ctx, content: m.content)
            }
            if let m = original {
                VStack(alignment: .leading, spacing: 0) {
                    Text(ctx.name(of: m.senderId))
                        .font(label.weight(ink.labelSize == nil ? .medium : .semibold))
                        .foregroundStyle(ChatColor.readable(bar, on: ink.quoteSurface, towards: ink.text).color)
                    Text(m.deleted ? L.retracted : ChatTextLabels.preview(m, reactions: ctx.model.reactionsOn))
                        .font(label).foregroundStyle(ink.text.color).lineLimit(1).truncationMode(.tail)
                }
            } else {
                Text(L.replyMissing).font(label).foregroundStyle(theme.colors.tx3)
            }
        }
        .padding(.horizontal, theme.spacing.s10).padding(.vertical, theme.spacing.s6)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background((hovered ? ink.hoverFill.over(fill) : fill).color, in: RoundedRectangle(cornerRadius: theme.radii.md))
        .overlay(alignment: .leading) { bar.color.frame(width: 3) }
        .clipShape(RoundedRectangle(cornerRadius: theme.radii.md))
        .contentShape(RoundedRectangle(cornerRadius: theme.radii.md))
        .onHover { hovered = $0 }
        .onTapGesture(perform: onTap)
        .pointerStyle(.link)
        .padding(.bottom, theme.spacing.s8)
        .task(id: replyToId) { await watch() }
    }

    private func watch() async {
        let chat = ctx.services.chat, account = ctx.accountId, gid = ctx.state.chatGid, id = replyToId
        var requested = false
        for await m in chat.watchMessage(accountId: account, chatGid: gid, serverId: id) {
            original = m
            if m == nil, !requested {
                requested = true
                _ = await FetchChatMessages(chat)(accountId: account, chatGid: gid, serverIds: [id])
            }
        }
    }
}
