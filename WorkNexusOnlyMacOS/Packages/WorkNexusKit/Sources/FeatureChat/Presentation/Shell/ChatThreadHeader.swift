import CoreDomain
import CoreUI
import SwiftUI

/// Top of an open chat: avatar, title and, for groups, the member count (for direct chats, presence or the account).
/// Clicking them shows the chat or group info; the right side has the in-chat search and the mute bell.
/// Ported from: lib/features/chat/presentation/widgets/chat_thread_header.dart
struct ChatThreadHeader: View {
    @Environment(\.appTheme) private var theme
    @Environment(\.chatShellLayout) private var layout
    @Environment(\.chatPanelVisibility) private var visibility
    let model: ChatShellModel
    let session: ChatThreadSession

    var body: some View {
        let chat = session.state.chat, users = model.users
        let title = ChatShellLabels.title(chat, users)
        let withPeer = chat.type == .one2one && !chat.isMyCloud
        let presence = withPeer ? ChatShellLabels.presence(users, chat.peerUserId) : nil
        HStack {
            if visibility.listHidden {
                AppIconButton("sidebar.left", help: shellString("chatShowList", "Show chat list")) { visibility.listHidden = false }
            }
            Button(action: showInfo) {
                HStack(spacing: theme.spacing.s12) {
                    ChatAvatarView(chat: chat, title: title, users: users, size: .large)
                    VStack(alignment: .leading, spacing: theme.spacing.s2) {
                        Text(title).font(theme.typography.titleSm).foregroundStyle(theme.colors.tx).lineLimit(1)
                        Subtitle(chat: chat, users: users, memberCount: session.memberCount, presence: presence)
                    }
                    Spacer(minLength: 0)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain).help(shellString("chatInfo", "Chat info"))
            AppIconButton("magnifyingglass", help: shellString("chatSearchMessages", "Search in conversation…")) { session.toggleSearch() }
                .background(session.search.isOpen ? theme.colors.sel : .clear, in: RoundedRectangle(cornerRadius: theme.radii.md))
            ChatMuteToggle(model: model, chat: chat)
            AppIconButton("sidebar.right", help: infoToggleHelp) { toggleInfo() }
        }
        .padding(.horizontal, theme.spacing.s20)
        .frame(height: ChatShellLayout.headerHeight)
        .background(theme.colors.panel)
        .overlay(alignment: .bottom) { Rectangle().fill(theme.colors.line).frame(height: theme.borders.hairline) }
    }

    private var infoShown: Bool { session.state.effectivePanel(infoRoom: layout.infoRoom) == .info }
    private var infoToggleHelp: String {
        infoShown ? shellString("chatHideInfo", "Hide chat info") : shellString("chatShowInfo", "Show chat info")
    }

    /// With room the info panel is a column you can collapse or bring back; without room it slides over the messages.
    private func toggleInfo() {
        if layout.infoFits {
            visibility.infoHidden.toggle()
            session.state.sidePanel = nil
        } else {
            session.state.togglePanel(.info, infoRoom: false)
        }
    }

    /// With room the info panel is already beside the chat: clicking only closes whatever else is open.
    private func showInfo() { session.state.sidePanel = layout.infoRoom ? nil : .info }
}

private struct Subtitle: View {
    @Environment(\.appTheme) private var theme
    let chat: ChatConversation
    let users: [Int: ChatUser]
    let memberCount: Int?
    let presence: ChatPresence?

    var body: some View {
        if let text {
            HStack(spacing: theme.spacing.s4) {
                if let presence {
                    Circle().fill(presence.isAround ? theme.colors.green : theme.colors.tx2).frame(width: theme.spacing.s8, height: theme.spacing.s8)
                } else {
                    Image(systemName: chat.isMyCloud ? "lock" : chat.type == .one2one ? "at" : "person")
                        .font(.system(size: theme.sizes.icon12)).foregroundStyle(theme.colors.tx2)
                }
                Text(text).font(theme.typography.meta).foregroundStyle(theme.colors.tx2).lineLimit(1)
            }
        }
    }

    private var text: String? {
        if chat.isMyCloud { return shellString("chatMyCloudHint", "Notes, links and files you keep for yourself") }
        if chat.type != .one2one, let memberCount { return ChatShellLabels.memberCount(memberCount) }
        if let presence { return ChatShellLabels.presenceLabel(presence) }
        return chat.peerUserId.flatMap { users[$0]?.account }
    }
}

/// Header bell: mutes or unmutes this chat; warns instead when the OS blocks notifications.
/// Ported from: lib/features/chat/presentation/widgets/chat_mute_toggle.dart
struct ChatMuteToggle: View {
    @Environment(\.appTheme) private var theme
    let model: ChatShellModel
    let chat: ChatConversation

    var body: some View {
        let blocked = model.events.notificationsBlocked
        AppIconButton(blocked ? "bell.badge" : chat.muted ? "bell.slash" : "bell",
                      help: blocked ? shellString("chatNotificationsBlockedShort", "Notifications are blocked in System Settings")
                          : chat.muted ? shellString("chatUnmuteChat", "Unmute chat") : shellString("chatMuteChat", "Mute chat")) {
            model.setMuted(chat, !chat.muted)
        }
        .foregroundStyle(blocked ? theme.colors.amber : theme.colors.tx2)
    }
}
