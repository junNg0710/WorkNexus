import CoreDomain
import CoreUI
import SwiftUI

/// A message set apart beside the chat — a pinned message, a thread's root: who sent it and what the card is, the body, then
/// when it was sent and a link back to it in the chat.
/// Ported from: lib/features/chat/presentation/widgets/chat_message_card.dart
struct ChatMessageCard<Trailing: View>: View {
    @Environment(\.appTheme) private var theme
    let users: [Int: ChatUser]
    let message: ChatMessage
    let label: String
    let labelIcon: String
    var onViewOriginal: (() -> Void)?
    @ViewBuilder let trailing: Trailing

    var body: some View {
        ChatPanelCard {
            VStack(alignment: .leading, spacing: theme.spacing.s12) {
                HStack(spacing: theme.spacing.s12) {
                    ChatPrivacyAvatar(avatar: ChatAvatarView(userId: message.senderId, users: users, showPresence: false))
                    VStack(alignment: .leading, spacing: theme.spacing.s2) {
                        Text(ChatShellLabels.userName(users, message.senderId)).font(theme.typography.bodyStrong).foregroundStyle(theme.colors.tx).lineLimit(1)
                        HStack(spacing: theme.spacing.s4) {
                            Image(systemName: labelIcon).font(.system(size: theme.sizes.icon12)).foregroundStyle(theme.colors.accent)
                            Text(label).font(theme.typography.meta).foregroundStyle(theme.colors.tx2)
                        }
                    }
                    Spacer(minLength: 0)
                    trailing
                }
                Text(ChatShellLabels.preview(message)).font(theme.typography.body).foregroundStyle(theme.colors.tx)
                    .lineLimit(message.deleted ? 1 : 6).frame(maxWidth: .infinity, alignment: .leading).textSelection(.enabled)
                    // The card stays solid under the faded words (the body here is always words: a picture shows as its label).
                    .chatPrivacyFade()
                HStack(spacing: theme.spacing.s4) {
                    Text(shellString("chatDateAtTime", "{date} at {time}", [
                        "date": message.sentAt.formatted(.dateTime.day(.twoDigits).month(.twoDigits).year()),
                        "time": message.sentAt.formatted(.dateTime.hour(.twoDigits(amPM: .omitted)).minute()),
                    ]))
                    if let onViewOriginal {
                        Text(verbatim: "|")
                        Button(action: onViewOriginal) {
                            Text(shellString("chatViewOriginal", "View original message")).foregroundStyle(theme.colors.accent).font(theme.typography.metaStrong)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .font(theme.typography.meta).foregroundStyle(theme.colors.tx3)
            }
        }
    }
}
