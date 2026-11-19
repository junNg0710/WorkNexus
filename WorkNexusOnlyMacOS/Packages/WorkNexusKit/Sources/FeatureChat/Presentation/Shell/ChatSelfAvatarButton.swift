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
            AppMenuButton(help: shellString("chatMyProfile", "Your profile"), items: { menuItems(me) }) {
                ChatAvatarView(userId: me, users: model.users, diameter: theme.sizes.control32 + theme.spacing.s4)
            }
            .fixedSize()
        }
    }

    /// Your profile, then the presences with the current one checked — read when pressed, so it is the presence of now.
    private func menuItems(_ me: Int) -> [AppNativeMenu.Item] {
        let current = ChatShellLabels.presence(model.users, me)
        return [AppNativeMenu.Item(shellString("chatMyProfile", "Your profile"), icon: "person.crop.circle") { model.profileUserId = me }]
            + ChatPresence.selectable.enumerated().map { i, p in
                AppNativeMenu.Item(ChatShellLabels.presenceLabel(p), icon: Self.icon(p), dividerBefore: i == 0, checked: p == current) {
                    if p != current { model.setPresence(p) }
                }
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
