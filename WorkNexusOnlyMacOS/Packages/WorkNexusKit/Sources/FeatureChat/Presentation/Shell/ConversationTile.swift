import CoreDomain
import CoreUI
import SwiftUI

/// One row of the chat list: avatar, title, last message, time and unread; pinned and muted marks.
/// Ported from: lib/features/chat/presentation/widgets/conversation_tile.dart
struct ConversationTile: View {
    @Environment(\.appTheme) private var theme
    @Environment(\.chatSettings) private var settings
    @Environment(\.chatPrivacyHidden) private var hidden
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let chat: ConversationRowData
    let selected: Bool
    let highlighted: Bool
    let compact: Bool

    var body: some View {
        let unread = chat.chat.unreadCount > 0
        HStack(spacing: theme.spacing.s12) {
            ChatAvatarView(chat: chat.chat, title: chat.title, users: chat.users)
                .privacyMasked(hidden.contains(.identity), group: chat.chat.type != .one2one)
            VStack(alignment: .leading, spacing: theme.spacing.s2) {
                HStack {
                    ChatPrivacyText(text: chat.title, part: .identity, font: unread ? theme.typography.bodyStrong : theme.typography.body,
                                    color: theme.colors.tx)
                    Spacer(minLength: theme.spacing.s4)
                    Text(ChatShellLabels.listTime(chat.chat.lastActiveAt)).font(theme.typography.caption)
                        .foregroundStyle(unread ? theme.colors.accent : theme.colors.tx3)
                }
                HStack(spacing: theme.spacing.s6) {
                    ChatPrivacyMasked(part: .preview) {
                        ConversationPreviewLine(chat: chat.chat, lastSender: chat.lastSender, typing: chat.typing, reactions: settings.reactions)
                    } mask: {
                        Text(chatPrivacyMaskText).font(theme.typography.meta).foregroundStyle(theme.colors.tx2).lineLimit(1)
                    }
                    Spacer(minLength: 0)
                    if chat.chat.muted { Image(systemName: "bell.slash").font(.system(size: theme.sizes.icon12)).foregroundStyle(theme.colors.tx3) }
                    if chat.chat.starred { Image(systemName: "pin.fill").font(.system(size: theme.sizes.icon12)).foregroundStyle(theme.colors.tx3) }
                    AppCountBadge(chat.chat.unreadCount)
                }
            }
        }
        .padding(.horizontal, compact ? theme.spacing.s12 : theme.spacing.s20).padding(.vertical, theme.spacing.s8)
        .frame(maxWidth: .infinity, alignment: .leading)
        // The selection fill eases from the row left to the row picked (only those two rows change).
        .background { (selected ? theme.colors.sel : (highlighted ? theme.colors.panel2 : .clear)).animation(fillEase, value: selected) }
        .contentShape(Rectangle())
    }
}

extension ConversationTile {
    private var fillEase: Animation? { reduceMotion ? nil : .easeOut(duration: theme.motion.fast) }
}

/// Everything a row draws, resolved by the list (so a typing signal redraws only the rows it concerns).
struct ConversationRowData: Equatable {
    var chat: ChatConversation
    var title: String
    var users: [Int: ChatUser]
    var lastSender: String?
    var typing: String?
}

/// The second line of a chat-list row: the last message, or — while someone types — who is typing.
/// Ported from: lib/features/chat/presentation/widgets/conversation_preview_line.dart
struct ConversationPreviewLine: View {
    @Environment(\.appTheme) private var theme
    let chat: ChatConversation
    let lastSender: String?
    let typing: String?
    let reactions: Bool

    var body: some View {
        let unread = chat.unreadCount > 0
        Group {
            if let typing {
                HStack(spacing: theme.spacing.s6) {
                    TypingDots(color: theme.colors.accent)
                    Text(typing).font(theme.typography.meta).foregroundStyle(theme.colors.accent).lineLimit(1)
                }
            } else {
                (Text(lastSender.map { "\($0): " } ?? "").foregroundColor(unread ? theme.colors.tx : theme.colors.tx2)
                    + Text(chat.lastMessage.map { ChatShellLabels.preview($0, reactions: reactions) } ?? ""))
                    .font(theme.typography.meta).foregroundStyle(unread ? theme.colors.tx : theme.colors.tx2).lineLimit(1)
            }
        }
        .animation(.easeOut(duration: theme.motion.base), value: typing)
    }
}

/// Three dots rising in turn, beside "typing…".
/// Ported from: lib/features/chat/presentation/widgets/typing_dots.dart
private struct TypingDots: View {
    @Environment(\.appTheme) private var theme
    let color: Color
    @State private var phase = false

    var body: some View {
        HStack(spacing: theme.spacing.s2) {
            ForEach(0..<3, id: \.self) { i in
                Circle().fill(color).frame(width: theme.spacing.s4, height: theme.spacing.s4)
                    .opacity(phase ? 1 : 0.3)
                    .animation(.easeInOut(duration: 0.5).repeatForever().delay(Double(i) * 0.15), value: phase)
            }
        }
        .onAppear { phase = true }
    }
}
