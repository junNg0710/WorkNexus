/// Ported from: lib/features/chat/presentation/widgets/message_under_bubble.dart
import SwiftUI

/// What hangs under a message's bubble: the reactions to it and, when it roots a thread, the thread chip (`thread` nil:
/// none to show here).
struct MessageUnderBubble: View {
    @Environment(\.appTheme) private var theme
    let ctx: ThreadContext
    let message: ChatMessage
    let alignEnd: Bool
    var thread: ThreadSummary?

    var body: some View {
        VStack(alignment: alignEnd ? .trailing : .leading, spacing: 0) {
            ReactionChipsView(ctx: ctx, message: message, alignEnd: alignEnd)
            if let thread, let sid = message.serverId {
                ThreadChipView(ctx: ctx, summary: thread) { ctx.openThread(sid) }.padding(.top, theme.spacing.s6)
            }
        }
        .frame(maxWidth: .infinity, alignment: alignEnd ? .trailing : .leading)
    }
}
