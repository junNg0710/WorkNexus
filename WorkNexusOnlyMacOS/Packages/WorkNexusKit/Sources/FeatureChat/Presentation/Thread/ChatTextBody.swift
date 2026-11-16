/// Ported from: lib/features/chat/presentation/widgets/message_body.dart (ChatTextBody)
import CoreUI
import SwiftUI

/// Message text — Markdown or plain with mentions and links. Link previews show under the text (`MessageLinkPreviews`).
struct ChatTextBody: View {
    @Environment(\.chatBubbleInk) private var ink
    let ctx: ThreadContext
    let text: String
    /// Render through the Markdown engine (see `ChatTextLabels.rendersMarkdown`); plain text otherwise.
    let markdown: Bool

    var body: some View {
        if markdown {
            MarkdownText(text, fontSize: ink.fontSize, color: ink.text.color, height: 1.5,
                         isPlainLink: { ChatTextLabels.mentionUserId($0) != nil }, linkColor: ink.link.color) { link in
                if let id = ChatTextLabels.mentionUserId(link) { ctx.actions.openProfile(id) } else { ctx.openLink(link) }
            }
            .textSelection(.enabled)
        } else {
            MentionTextView(text: text, ctx: ctx)
        }
    }
}
