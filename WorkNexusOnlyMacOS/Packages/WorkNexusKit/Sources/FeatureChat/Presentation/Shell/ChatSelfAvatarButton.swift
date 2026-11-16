import CoreDomain
import CoreUI
import SwiftUI

/// The signed-in user's own avatar at the top of the chat list: a menu to open their profile or switch their presence
/// (busy / in meeting / away / online), the current one checked.
/// Ported from: lib/features/chat/presentation/widgets/chat_self_avatar_button.dart + chat_self_menu.dart
struct ChatSelfAvatarButton: View {
    @Environment(\.appTheme) private var theme
    let model: ChatShellModel

    var body: some View {
        if let me = model.selfUserId {
            let current = ChatShellLabels.presence(model.users, me)
            Menu {
                Button { model.profileUserId = me } label: { Label(shellString("chatMyProfile", "Your profile"), systemImage: "person.crop.circle") }
                Divider()
                ForEach(ChatPresence.selectable, id: \.self) { p in
                    Button { if p != current { model.setPresence(p) } } label: {
                        Label(ChatShellLabels.presenceLabel(p), systemImage: p == current ? "checkmark" : Self.icon(p))
                    }
                }
            } label: {
                ChatAvatarView(userId: me, users: model.users, diameter: theme.sizes.control32 + theme.spacing.s4)
            }
            .menuStyle(.button).buttonStyle(.plain).menuIndicator(.hidden).fixedSize()
            .help(shellString("chatMyProfile", "Your profile"))
        }
    }

    static func icon(_ p: ChatPresence) -> String {
        switch p {
        case .busy: "desktopcomputer"
        case .meeting: "calendar"
        case .away: "clock"
        case .online, .offline: "checkmark.circle"
        }
    }
}
