import CoreDomain
import CoreUI
import SwiftUI

/// A chat to forward to: avatar, title and a round tick; picked rows are tinted, like the people picker of a new chat.
/// Ported from: lib/features/chat/presentation/widgets/forward_chat_row.dart
struct ForwardChatRow: View {
    @Environment(\.appTheme) private var theme
    let chat: ListedChat
    let users: [Int: ChatUser]
    let picked: Bool
    let onTap: () -> Void

    var body: some View {
        HoverSurface(onTap: onTap, selected: picked) {
            HStack(spacing: theme.spacing.s12) {
                ChatAvatarView(chat: chat.chat, title: chat.title, users: users)
                Text(chat.title).font(theme.typography.bodyStrong).foregroundStyle(theme.colors.tx).lineLimit(1)
                Spacer(minLength: 0)
                Image(systemName: picked ? "checkmark.circle.fill" : "circle").font(.system(size: theme.sizes.icon18))
                    .foregroundStyle(picked ? theme.colors.accent : theme.colors.line2)
            }
            .padding(.horizontal, theme.spacing.s12).padding(.vertical, theme.spacing.s6)
        }
    }
}
