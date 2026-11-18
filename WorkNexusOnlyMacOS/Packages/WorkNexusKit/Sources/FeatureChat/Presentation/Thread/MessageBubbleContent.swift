/// Ported from: lib/features/chat/presentation/widgets/message_bubble_content.dart
import SwiftUI

/// What sits inside a text-like bubble: sender name, reply quote, the body, its translation and link previews, then the
/// time on a row of its own.
///
/// With `timeAtEnd` that row is at the bubble's end side, as in Telegram: an invisible copy of the footer keeps the row's
/// room and the visible one is pinned over it at the end, so the bubble is never wider than its content needs.
///
/// While the privacy mode hides messages the insides fade, never the bubble itself: it stays solid, so the faded words leave
/// no hole to the wallpaper. A picture (an image answering a quote) is not faded — its grey cover must show — so only the
/// words around it are.
struct MessageBubbleContent<Name: View, Quote: View, Footer: View>: View {
    @Environment(\.appTheme) private var theme
    let ctx: ThreadContext
    let message: ChatMessage
    let timeAtEnd: Bool
    let name: Name?
    let quote: Quote?
    let footer: Footer?

    var body: some View {
        let pinned = timeAtEnd && footer != nil
        let picture = !message.deleted && isChatPicture(message.content)
        let column = VStack(alignment: .leading, spacing: 0) {
            if let name { name.padding(.bottom, theme.spacing.s2).chatPrivacyFade(when: picture) }
            if let quote { quote.chatPrivacyFade(when: picture) }
            MessageBodyView(ctx: ctx, message: message)
            Group {
                MessageTranslationView(controller: ctx.model.translation, message: message)
                // Compact previews of the links, under the text.
                MessageLinkPreviews(ctx: ctx, message: message)
            }
            .chatPrivacyFade(when: picture)
            if let footer {
                // Pinned: an invisible copy keeps the row's room.
                footer.opacity(pinned ? 0 : 1).allowsHitTesting(!pinned).padding(.top, theme.spacing.s4).chatPrivacyFade(when: picture)
            }
        }
        Group {
            if pinned, let footer {
                column.overlay(alignment: .bottomTrailing) { footer.chatPrivacyFade(when: picture) }
            } else {
                column
            }
        }
        .chatPrivacyFade(when: !picture)
    }
}
