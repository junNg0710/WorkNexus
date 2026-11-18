import CoreDomain
import CoreUI
import SwiftUI

/// On a member's row, for the group's owner: a "…" menu to make them an admin (or a plain member again), hand them the
/// group, or remove them — the last two after asking. Nothing for anyone else.
/// Ported from: lib/features/chat/presentation/widgets/chat_member_menu_button.dart
struct ChatMemberMenuButton: View {
    let model: ChatShellModel
    let chat: ChatConversation
    let userId: Int
    let rights: ChatGroupRights

    var body: some View {
        AppIconButton("ellipsis", help: shellString("chatMemberActions", "Member actions")) {
            AppNativeMenu.popUp(Self.items(chat: chat, userId: userId, rights: rights).map { action in
                AppNativeMenu.Item(Self.label(action), icon: Self.icon(action), destructive: action == .remove,
                                   dividerBefore: action == .remove) { pick(action) }
            })
        }
    }

    private func pick(_ action: ChatMemberAction) {
        switch action {
        case .makeAdmin, .removeAdmin: Task { _ = await model.run(action, on: userId, in: chat) }
        case .transferOwner, .remove: model.groupDialog = .member(chat, userId: userId, action: action)
        }
    }

    /// What the owner may do to `userId`: admins and ownership with `manageAdmins`, removing with `removeMembers`.
    static func items(chat: ChatConversation, userId: Int, rights: ChatGroupRights) -> [ChatMemberAction] {
        var out: [ChatMemberAction] = []
        if rights.manageAdmins { out += [chat.adminIds.contains(userId) ? .removeAdmin : .makeAdmin, .transferOwner] }
        if rights.removeMembers { out.append(.remove) }
        return out
    }

    static func label(_ action: ChatMemberAction) -> String {
        switch action {
        case .makeAdmin: shellString("chatMakeAdmin", "Make admin")
        case .removeAdmin: shellString("chatRemoveAdmin", "Remove as admin")
        case .transferOwner: shellString("chatTransferOwner", "Make group owner")
        case .remove: shellString("chatRemoveMember", "Remove from group")
        }
    }

    static func icon(_ action: ChatMemberAction) -> String {
        switch action {
        case .makeAdmin: "shield"
        case .removeAdmin: "shield.slash"
        case .transferOwner: "crown"
        case .remove: "person.badge.minus"
        }
    }
}
