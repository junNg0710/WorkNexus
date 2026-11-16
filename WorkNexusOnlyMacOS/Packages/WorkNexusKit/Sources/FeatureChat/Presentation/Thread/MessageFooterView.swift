/// Ported from: lib/features/chat/presentation/widgets/message_footer.dart
import CoreDomain
import CoreUI
import SwiftUI

/// A message's time — or, while it is not sent, its state (tap a failed message to retry). The caller places it (under
/// the content, or at the bubble's bottom-end corner).
struct MessageFooterView: View {
    @Environment(\.appTheme) private var theme
    @Environment(\.chatBubbleInk) private var ink
    let ctx: ThreadContext
    let message: ChatMessage
    /// Colour of a "sent" tick after the time (Telegram style), or none.
    var tick: ChatColor?
    /// Reply count of a thread root, shown before the time (Telegram style); tapping it opens the thread.
    var replies: Int?
    var onOpenReplies: () -> Void = {}

    var body: some View {
        let size = ink.metaSize ?? 11
        let font = ink.metaSize.map { theme.typography.font(size: $0) } ?? theme.typography.caption
        switch message.sendState {
        case .sent:
            HStack(spacing: 0) {
                if let replies {
                    Button(action: onOpenReplies) {
                        HStack(spacing: theme.spacing.s2) {
                            Image(systemName: "arrowshape.turn.up.left").font(.system(size: size))
                            Text("\(replies)").font(font)
                        }
                    }
                    .buttonStyle(.plain).help(L.replies(replies)).pointerStyle(.link)
                    Spacer().frame(width: theme.spacing.s8)
                }
                Text(ChatTextLabels.clock(message.sentAt)).font(font)
                if let tick {
                    Image(systemName: "checkmark").font(.system(size: size * 1.1, weight: .light))
                        .foregroundStyle(tick.color).padding(.leading, theme.spacing.s2)
                }
            }
            .foregroundStyle(ink.meta.color)
        case .pending:
            Text(isUploading ? L.uploading : L.sending).font(font).foregroundStyle(ink.meta.color)
        case .failed:
            Button { retry() } label: {
                Text(L.sendFailed).font(font.weight(.medium)).foregroundStyle(theme.colors.red)
            }
            .buttonStyle(.plain).pointerStyle(.link)
        }
    }

    private var isUploading: Bool {
        if case .file(let f) = message.content { f.fileId == 0 } else { false }
    }

    private func retry() {
        let chat = ctx.services.chat, account = ctx.accountId, gid = message.gid
        let report = ctx.model.report
        Task { @MainActor in
            if case .failure(let f) = await RetrySendMessage(chat)(accountId: account, messageGid: gid) { report(f.message) }
        }
    }
}
