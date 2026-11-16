import CoreDomain
import CoreUI
import SwiftUI

/// One chat in the list: its tile with the right-click menu, selecting it on tap.
/// Ported from: lib/features/chat/presentation/widgets/conversation_row.dart (+ conversation_menu.dart)
struct ConversationRow: View {
    let model: ChatShellModel
    let item: ListedChat
    let compact: Bool

    var body: some View {
        let chat = item.chat
        ConversationTile(chat: data, selected: chat.gid == model.selectedGid,
                         highlighted: model.isSearching && chat.gid == model.highlightedGid, compact: compact)
            .onTapGesture { model.select(chat.gid) }
            .contextMenu {
                Button { model.setStarred(chat, !chat.starred) } label: {
                    Label(chat.starred ? shellString("chatUnpinChat", "Unpin chat") : shellString("chatPinChat", "Pin chat"),
                          systemImage: chat.starred ? "pin.slash" : "pin")
                }
                Button { model.setMuted(chat, !chat.muted) } label: {
                    Label(chat.muted ? shellString("chatUnmuteChat", "Unmute chat") : shellString("chatMuteChat", "Mute chat"),
                          systemImage: chat.muted ? "bell" : "bell.slash")
                }
            }
    }

    private var data: ConversationRowData {
        let chat = item.chat
        let typing = model.typing(in: chat.gid)
        return ConversationRowData(
            chat: chat, title: item.title, users: model.users, lastSender: lastSender(chat),
            typing: typing.isEmpty ? nil
                : chat.type == .one2one ? shellString("chatTyping", "typing…") : ChatShellLabels.typingLabel(model.users, typing))
    }

    /// Who sent a group's last message, for its row; nil in direct chats and for system notices.
    private func lastSender(_ chat: ChatConversation) -> String? {
        guard chat.type != .one2one, let last = chat.lastMessage, last.content.asNotification == nil, !last.isNotice else { return nil }
        return last.isMine ? shellString("chatYou", "You") : ChatShellLabels.userName(model.users, last.senderId)
    }
}
