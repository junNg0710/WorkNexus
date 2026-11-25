/// Ported from: lib/features/chat/presentation/widgets/message_list_item.dart (MessageListItem, _Highlight)
import CoreUI
import SwiftUI

/// One row of the message list: a day divider, a time marker, the typing bubble, a server notice or a message.
///
/// Equatable on what it is given (the row, the model it belongs to, whether senders show): the list redraws for its own
/// reasons (scroll metrics, a page arriving) and without this every loaded row - hundreds - re-ran its body each time.
/// What a row reads from the model itself (reactions, summaries, the highlight) still redraws it through Observation.
struct ThreadRowView: View, Equatable {
    @Environment(\.chatStyle) private var style
    @Environment(\.appTheme) private var theme
    let ctx: ThreadContext
    let row: ChatListRow
    let showSenders: Bool
    private let modelKey: ObjectIdentifier

    init(ctx: ThreadContext, row: ChatListRow, showSenders: Bool) {
        self.ctx = ctx; self.row = row; self.showSenders = showSenders
        modelKey = ObjectIdentifier(ctx.model)
    }

    nonisolated static func == (a: ThreadRowView, b: ThreadRowView) -> Bool {
        a.modelKey == b.modelKey && a.showSenders == b.showSenders && a.row == b.row
    }

    var body: some View {
        let side = theme.spacing.s24
        switch row.item {
        case .day(let day):
            ChatSeparatorView(label: ChatTextLabels.dayLabel(day)).padding(.horizontal, side)
        case .marker(let at):
            ChatSeparatorView(label: ChatTextLabels.clock(at)).padding(.horizontal, side)
        case .typing:
            ChatTypingRow(ctx: ctx, typing: ctx.model.typing, showSenders: showSenders)
                .modifier(ChatRowEntrance(fresh: true, rise: theme.spacing.s4))
        case .message(let m) where m.isNotice:
            HighlightedRow(model: ctx.model, serverId: m.serverId, gapAbove: style.groupGap, gapBelow: style.groupGap) {
                ChatNoticeView(ctx: ctx, message: m).padding(.horizontal, side)
            }
        case .message(let m):
            HighlightedRow(model: ctx.model, serverId: m.serverId, gapAbove: row.firstOfRun ? style.groupGap : style.runGap,
                           gapBelow: row.lastOfRun ? style.groupGap : style.runGap) {
                MessageSelectionRow(state: ctx.state, message: m) {
                    MessageBubbleView(ctx: ctx, message: m, firstOfRun: row.firstOfRun, lastOfRun: row.lastOfRun,
                                      showSender: showSenders, thread: m.serverId.flatMap { ctx.model.summaries[$0] })
                        .padding(.horizontal, side)
                }
            }
            // A message that arrives while the chat is open fades in; loaded pages and rows scrolled back show as they are.
            .modifier(ChatRowEntrance(fresh: ctx.model.arrivals.isFresh(m.gid), rise: theme.spacing.s8))
            // One accessibility element per message (its words read together) instead of one per name, line, badge and
            // button: with an accessibility client running, every element of a row scrolling into view had SwiftUI walk
            // the whole window for focus - a sixth of the main thread while scrolling.
            .accessibilityElement(children: .combine)
        }
    }
}

/// Tints the full-width row of the message just jumped to, fading out again. Stronger than the selection fill: it has to
/// catch the eye after a jump.
private struct HighlightedRow<Content: View>: View {
    @Environment(\.appTheme) private var theme
    let model: MessageTimelineModel
    let serverId: Int?
    let gapAbove: CGFloat
    let gapBelow: CGFloat
    @ViewBuilder let content: Content

    static var alpha: Double { 0.3 }

    var body: some View {
        let on = serverId != nil && model.highlighted == serverId
        // The same margin above and below the message: the tint starts inside the gap above it and runs as far into the
        // next row's gap below it — never onto a neighbouring bubble.
        let margin = min(gapAbove, gapBelow, theme.spacing.s8)
        content
            .padding(.top, gapAbove)
            .background {
                theme.colors.accent.opacity(on ? Self.alpha : 0)
                    .padding(.top, gapAbove - margin).padding(.bottom, -margin).allowsHitTesting(false)
                    .animation(.easeOut(duration: 0.5), value: on)
            }
    }
}
