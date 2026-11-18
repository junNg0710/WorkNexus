import CoreDomain
import CoreUI
import SwiftUI

/// A reply thread beside the chat: the root message and every reply to it (and to its replies). A reply is written in the
/// chat's own composer, so each message here has a reply button that sets the composer's draft.
/// Ported from: lib/features/chat/presentation/widgets/reply_thread_panel.dart
struct ReplyThreadPanel: View {
    @Environment(\.appTheme) private var theme
    @Environment(\.chatSettings) private var settings
    let model: ChatShellModel
    let session: ChatThreadSession
    let rootId: Int
    @State private var root: ChatMessage??
    @State private var allReplies: [ChatMessage] = []

    var body: some View {
        let state = session.state
        let replies = BuildReplyThread()(rootId, allReplies, reactions: settings.reactions).replies
        ChatSidePanelFrame(title: shellString("chatThread", "Thread"), width: ChatShellLayout.panelRoom, onClose: { state.closePanel() }) {
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    switch root {
                    case .none: AppInlineSpinner()
                    case .some(.none): AppInlineNote(shellString("chatReplyMissing", "Original message not loaded"))
                    case .some(.some(let m)):
                        ChatMessageCard(users: model.users, message: m, label: shellString("chatThread", "Thread"), labelIcon: "bubble.left.and.bubble.right",
                                        onViewOriginal: { state.requestJump(to: rootId) }) {
                            AppIconButton("arrowshape.turn.up.left", help: shellString("chatReply", "Reply")) { state.replyDraft = m }
                        }
                    }
                    if !replies.isEmpty {
                        Text(shellString("chatReplies", replies.count == 1 ? "1 reply" : "{count} replies", ["count": "\(replies.count)"]))
                            .font(theme.typography.label).foregroundStyle(theme.colors.tx2).padding(.vertical, theme.spacing.s12)
                        ForEach(replies) { r in ReplyRow(users: model.users, message: r) { state.replyDraft = r } }
                    }
                }
                .padding(theme.spacing.s16)
            }
            // Pointing anywhere on the thread shows all of it while the privacy mode hides it.
            .chatPrivacyRevealRegion()
        }
        .task(id: rootId) {
            for await m in model.repository.watchMessage(accountId: state.accountId, chatGid: state.chatGid, serverId: rootId) { root = .some(m) }
        }
        .task { for await list in model.repository.watchReplies(accountId: state.accountId, chatGid: state.chatGid) { allReplies = list } }
    }
}

/// One reply in the thread: sender, time, preview and a reply button.
private struct ReplyRow: View {
    @Environment(\.appTheme) private var theme
    let users: [Int: ChatUser]
    let message: ChatMessage
    let onReply: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: theme.spacing.s10) {
            ChatPrivacyAvatar(avatar: ChatAvatarView(userId: message.senderId, users: users, size: .small, showPresence: false))
            VStack(alignment: .leading, spacing: theme.spacing.s2) {
                HStack(spacing: theme.spacing.s6) {
                    Text(ChatShellLabels.userName(users, message.senderId)).font(theme.typography.bodyStrong).foregroundStyle(theme.colors.tx)
                    Text(message.sentAt.formatted(date: .abbreviated, time: .shortened)).font(theme.typography.caption).foregroundStyle(theme.colors.tx3)
                }
                Text(ChatShellLabels.preview(message)).font(theme.typography.body).foregroundStyle(theme.colors.tx).textSelection(.enabled)
                    .chatPrivacyFade()
            }
            Spacer(minLength: 0)
            AppIconButton("arrowshape.turn.up.left", help: shellString("chatReply", "Reply"), action: onReply)
        }
        .padding(.vertical, theme.spacing.s8)
    }
}
