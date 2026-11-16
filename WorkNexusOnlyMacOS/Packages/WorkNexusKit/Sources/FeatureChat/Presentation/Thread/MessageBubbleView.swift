/// Ported from: lib/features/chat/presentation/widgets/message_bubble.dart
import CoreDomain
import CoreUI
import SwiftUI

/// One message, drawn the way the user's chat style draws it: bubble colours and shape, tail, avatar size/shape/position,
/// where the name, time and reply quote go. Consecutive messages from one sender form a run.
struct MessageBubbleView: View {
    @Environment(\.chatStyle) private var style
    @Environment(\.appTheme) private var theme
    let ctx: ThreadContext
    let message: ChatMessage
    var firstOfRun = true
    var lastOfRun = true
    /// Group chats show sender names; one-to-one chats do not.
    var showSender = true
    /// Set when this message is the root of a reply thread.
    var thread: ThreadSummary?

    var body: some View {
        let l = BubbleLayout(style: style, message: message, firstOfRun: firstOfRun, lastOfRun: lastOfRun, showSender: showSender)
        let ink = style.ink(mine: l.mine)
        let name = ctx.name(of: message)
        let nameView = MessageSenderNameView(
            ctx: ctx, userId: message.senderId, name: name, color: style.nameColor(message.senderId), labelSize: style.labelSize,
            time: l.headed ? message.sentAt : nil, timeColor: ink.meta, timeSize: style.metaSize)
        let gutter = l.gutter(style: style)
        let quote = l.hasQuote ? quoteView(l) : nil
        MessageRowLayout(hasAvatar: l.hasAvatarSlot, alignEnd: l.alignEnd, style: style, name: l.nameOverRow ? nameView : nil) {
            MessageAvatarSlot(ctx: ctx, senderId: message.senderId, name: name, style: style, visible: l.avatarVisible)
        } content: {
            VStack(alignment: l.alignEnd ? .trailing : .leading, spacing: 0) {
                if l.nameAbove { nameView.padding(.horizontal, theme.spacing.s4).padding(.bottom, theme.spacing.s4) }
                if style.quote == .above, let quote {
                    quote.environment(\.chatBubbleInk, style.outsideQuoteInk())
                        .padding(.leading, gutter.leading).padding(.trailing, gutter.trailing).padding(.bottom, theme.spacing.s4)
                }
                MessageHoverActions(ctx: ctx, message: message, alignEnd: l.alignEnd, inThread: message.replyToId != nil || thread != nil) {
                    MessageBubbleBody(ctx: ctx, message: message, layout: l, firstOfRun: firstOfRun, lastOfRun: lastOfRun, nameView: nameView,
                                      quote: quote, footer: footerView(l))
                        .environment(\.chatBubbleInk, ink)
                }
                if style.quote == .below, let quote {
                    quote.environment(\.chatBubbleInk, style.outsideQuoteInk())
                        .padding(.leading, gutter.leading).padding(.trailing, gutter.trailing).padding(.top, theme.spacing.s4)
                }
                MessageUnderBubble(ctx: ctx, message: message, alignEnd: l.alignEnd, thread: style.threadInMeta ? nil : thread)
                    .padding(.leading, gutter.leading).padding(.trailing, gutter.trailing)
            }
        }
    }

    // MARK: pieces

    private func quoteView(_ l: BubbleLayout) -> ReplyQuoteView {
        let replyTo = message.replyToId ?? 0
        return ReplyQuoteView(ctx: ctx, replyToId: replyTo, onTap: { ctx.state.requestJump(to: replyTo) },
                              senderColor: style.quoteInSenderColor && !l.mine ? { style.nameColor($0) } : nil)
    }

    private func footerView(_ l: BubbleLayout) -> MessageFooterView? {
        guard l.showFooter else { return nil }
        let inMeta = style.threadInMeta && message.serverId != nil
        return MessageFooterView(ctx: ctx, message: message, tick: style.ticks && l.mine ? style.palette.outgoingTicks : nil,
                                 replies: inMeta ? thread?.count : nil, onOpenReplies: { message.serverId.map(ctx.openThread) })
    }
}

/// The bubble itself — a bare image / emoji / video, or the filled, tailed box with its content.
private struct MessageBubbleBody: View {
    @Environment(\.chatStyle) private var style
    @Environment(\.appTheme) private var theme
    let ctx: ThreadContext
    let message: ChatMessage
    let layout: BubbleLayout
    let firstOfRun: Bool
    let lastOfRun: Bool
    let nameView: MessageSenderNameView
    let quote: ReplyQuoteView?
    let footer: MessageFooterView?

    var body: some View {
        let l = layout
        let ink = style.ink(mine: l.mine)
        let gutter = l.gutter(style: style)
        if l.media {
            VStack(alignment: l.alignEnd ? .trailing : .leading, spacing: 0) {
                MessageBodyView(ctx: ctx, message: message)
                if let footer { footer.padding(.top, theme.spacing.s4) }
            }
            .padding(.leading, gutter.leading).padding(.trailing, gutter.trailing)
            .frame(maxWidth: BubbleLayout.maxMediaWidth, alignment: l.alignEnd ? .trailing : .leading)
        } else {
            let wide = ChatTextLabels.showsWide(message)
            MessageBubbleBox(
                fill: style.bubbleFill(mine: l.mine), hoverFill: ink.hoverFill, border: style.bubbleBorder(mine: l.mine),
                corners: style.corners(mine: l.mine, firstOfRun: firstOfRun, lastOfRun: lastOfRun, withTail: l.tailed),
                padding: style.padding, mine: l.mine, tail: l.tailed ? style.tail : nil, tailTip: l.tailTip(style: style)
            ) {
                MessageBubbleContent(
                    ctx: ctx, message: message, timeAtEnd: style.timeAtEnd(alignEnd: l.alignEnd),
                    name: l.showName && style.name == .insideBubble ? nameView : nil,
                    quote: style.quote == .inside ? quote : nil, footer: footer)
            }
            // A tailed box makes its own room for the tail.
            .padding(.leading, l.tailed ? 0 : gutter.leading).padding(.trailing, l.tailed ? 0 : gutter.trailing)
            .frame(maxWidth: wide ? style.maxWidth * BubbleLayout.wideBubbleFactor : style.maxWidth, alignment: l.alignEnd ? .trailing : .leading)
        }
    }
}
