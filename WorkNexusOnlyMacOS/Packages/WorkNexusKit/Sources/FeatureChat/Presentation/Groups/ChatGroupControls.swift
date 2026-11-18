import CoreDomain
import CoreUI
import SwiftUI

/// A group's big picture in the info panel with, for its owner and admins, a round camera badge on its corner that changes
/// it — the edit sits on what it edits instead of a text button under it.
/// Ported from: lib/features/chat/presentation/widgets/chat_group_edit_controls.dart (`ChatGroupAvatarEditor`)
struct ChatGroupAvatarEditor<Avatar: View>: View {
    @Environment(\.appTheme) private var theme
    /// Owner and admins, as for pinning.
    let editable: Bool
    let onEdit: () -> Void
    @ViewBuilder let avatar: Avatar

    var body: some View {
        avatar.overlay(alignment: .bottomTrailing) {
            if editable {
                Button(action: onEdit) {
                    Image(systemName: "camera").font(.system(size: theme.sizes.icon14)).foregroundStyle(theme.colors.tx)
                        .frame(width: theme.sizes.control32, height: theme.sizes.control32)
                        .background(theme.colors.card, in: Circle())
                        // A ring of the panel's colour cuts the badge out of the avatar.
                        .overlay { Circle().stroke(theme.colors.bg, lineWidth: theme.borders.thick) }
                        .contentShape(Circle())
                }
                .buttonStyle(.plain).pointerStyle(.link)
                .help(shellString("chatChangeGroupAvatar", "Change group picture"))
                .accessibilityLabel(shellString("chatChangeGroupAvatar", "Change group picture"))
            }
        }
    }
}

/// A group's name in the info panel with, for those who may rename it, a small pencil after it. The pencil's width is
/// mirrored before the name so the name stays centred over the avatar.
/// Ported from: lib/features/chat/presentation/widgets/chat_group_edit_controls.dart (`ChatGroupTitleEditor`)
struct ChatGroupTitleEditor<Title: View>: View {
    @Environment(\.appTheme) private var theme
    let editable: Bool
    let onEdit: () -> Void
    @ViewBuilder let title: Title

    var body: some View {
        if editable {
            HStack(spacing: theme.spacing.s4) {
                Color.clear.frame(width: theme.sizes.control32 - theme.spacing.s4, height: 1)
                title
                AppIconButton("pencil", help: shellString("chatRenameGroup", "Rename group"), action: onEdit)
                    .frame(width: theme.sizes.control32 - theme.spacing.s4)
            }
        } else {
            title
        }
    }
}

/// At the bottom of a group's info panel: its owner dismisses the group for everyone, anyone else leaves it — after asking
/// (see `ChatGroupDialog.exit`).
/// Ported from: lib/features/chat/presentation/widgets/chat_group_actions.dart (`ChatGroupExitButton`)
struct ChatGroupExitButton: View {
    @Environment(\.appTheme) private var theme
    let model: ChatShellModel
    let chat: ChatConversation

    var body: some View {
        let rights = model.groupRights(chat)
        if rights.dismiss || rights.leave {
            AppButton(rights.dismiss ? shellString("chatDismissGroup", "Dismiss group") : shellString("chatLeaveGroup", "Leave group"),
                      systemImage: rights.dismiss ? "trash" : "rectangle.portrait.and.arrow.right", kind: .danger) {
                model.groupDialog = .exit(chat, dismiss: rights.dismiss)
            }
            .padding(.top, theme.spacing.s12)
        }
    }
}
