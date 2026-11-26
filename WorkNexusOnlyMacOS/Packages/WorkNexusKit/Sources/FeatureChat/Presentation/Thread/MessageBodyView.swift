/// Ported from: lib/features/chat/presentation/widgets/message_body.dart (MessageBody)
import CoreDomain
import CoreUI
import SwiftUI

/// The content of a message, by content type. Images, files and videos are the Media slice's (`MessageMediaAdapter`).
/// A picture (an image, a sticker, a video, a big emoji) is covered whole in grey while the privacy mode hides messages; the
/// rest fades with the bubble's insides (`MessageBubbleContent`).
struct MessageBodyView: View {
    let ctx: ThreadContext
    let message: ChatMessage

    var body: some View {
        if !message.deleted, isChatPicture(message.content) {
            MessageBodyContent(ctx: ctx, message: message).chatPrivacyCover()
        } else {
            MessageBodyContent(ctx: ctx, message: message)
        }
    }
}

private struct MessageBodyContent: View {
    @Environment(\.appTheme) private var theme
    @Environment(\.chatBubbleInk) private var ink
    let ctx: ThreadContext
    let message: ChatMessage

    var body: some View {
        if message.deleted {
            RetractedBody(ctx: ctx, message: message)
        } else {
            switch message.content {
            case .text(let text, let markdown):
                ChatTextBody(ctx: ctx, text: text, markdown: ChatTextLabels.rendersMarkdown(text, markdown: markdown))
            case .emoji(let emoji):
                // Large, without a bubble (the bubble treats it as media).
                Text(emoji).font(.system(size: theme.spacing.s40 * 1.5)).lineSpacing(0)
            case .notification(let n):
                NotificationBodyView(ctx: ctx, notification: n)
            case .image, .file:
                MessageMediaAdapter(message: message, state: ctx.state)
            // The link stays in the bubble; its preview shows under it.
            case .link(let url, let title):
                ChatTextBody(ctx: ctx, text: title == nil || title == url ? url : "\(title ?? "")\n\(url)", markdown: false)
            case .code(let code, _, let name):
                VStack(alignment: .leading, spacing: theme.spacing.s4) {
                    if let name { Text(name).font(theme.typography.paragraph).foregroundStyle(ink.meta.color) }
                    CodeBlock(code, fontSize: ink.fontSize - 1, collapsedLines: 10)
                }
            case .unsupported(let type):
                Text(L.unsupported(type)).font(theme.typography.paragraph).italic().foregroundStyle(ink.meta.color)
            }
        }
    }
}

/// A retracted message: the note that it was, and for one of the user's own retracted in this chat just now, "Edit
/// again" - its text goes back into the input, to change and send.
private struct RetractedBody: View {
    @Environment(\.appTheme) private var theme
    @Environment(\.chatBubbleInk) private var ink
    let ctx: ThreadContext
    let message: ChatMessage

    var body: some View {
        let note = Text(L.retracted).font(theme.typography.body).italic().foregroundStyle(ink.meta.color)
        if let kept = ctx.state.retracted[message.gid] {
            HStack(spacing: theme.spacing.s8) {
                note
                Button(L.editAgain) {
                    ctx.state.editAgain(message.gid, quoted: kept.replyToId.flatMap { ctx.model.shownMessage(serverId: $0) })
                }
                .buttonStyle(.plain).font(theme.typography.body).foregroundStyle(ink.link.color).pointerStyle(.link)
            }
        } else {
            note
        }
    }
}
