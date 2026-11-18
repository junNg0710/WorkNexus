import CoreDomain
import CoreUI
import SwiftUI

/// Presents the shell's group and category dialogs: the category manager, and over it whichever `ChatGroupDialog` is open.
/// Not in the Flutter app as such: there each dialog is shown with `showDialog` where it is asked for.
struct ChatGroupDialogHost: ViewModifier {
    @Bindable var model: ChatShellModel

    func body(content: Content) -> some View {
        content
            .appDialog(isPresented: $model.showCategoryManager) { ChatCategoryManagerDialog(model: model) }
            .appDialog(item: $model.groupDialog) { dialog in ChatGroupDialogView(model: model, dialog: dialog) }
    }
}

private struct ChatGroupDialogView: View {
    let model: ChatShellModel
    let dialog: ChatGroupDialog

    private func close() { model.groupDialog = nil }

    var body: some View {
        switch dialog {
        case .rename(let chat):
            ChatNameDialog(title: shellString("chatRenameGroup", "Rename group"), initial: chat.name,
                           hint: shellString("chatGroupName", "Group name"), onSave: { await model.renameGroup(chat, $0) }, onClose: close)
        case .settings(let chat):
            ChatGroupSettingsDialog(model: model, chat: chat, onClose: close)
        case .addMembers(let chat, let members):
            ChatAddMembersDialog(model: model, chat: chat, members: members, onClose: close)
        case .category(let chat):
            ChatCategoryPickerDialog(model: model, chat: chat, onClose: close)
        case .renameCategory(let name):
            ChatNameDialog(title: shellString("chatRenameCategory", "Rename category"), initial: name,
                           hint: shellString("chatCategoryName", "Category name, e.g. Projects"),
                           onSave: { await model.renameCategory(name, to: $0) }, onClose: close)
        case .deleteCategory(let name):
            ConfirmStep(title: shellString("chatDeleteCategory", "Delete category"),
                    message: shellString("chatDeleteCategoryConfirm", "Delete the “{name}” category? Its chats stay, just uncategorised.", ["name": name]),
                    label: nil, onClose: close) { await model.deleteCategory(name) }
        case .exit(let chat, let dismiss):
            let title = ChatShellLabels.title(chat, model.users)
            let label = dismiss ? shellString("chatDismissGroup", "Dismiss group") : shellString("chatLeaveGroup", "Leave group")
            ConfirmStep(title: label, message: dismiss
                    ? shellString("chatDismissGroupConfirm", "Dismiss “{name}” for every member? It leaves everyone's chat list and can't be undone.", ["name": title])
                    : shellString("chatLeaveGroupConfirm", "Leave “{name}”? You stop getting its messages until someone adds you back.", ["name": title]),
                    label: label, onClose: close) { await model.exitGroup(chat, dismiss: dismiss) }
        case .member(let chat, let userId, let action):
            let name = ChatShellLabels.userName(model.users, userId)
            let transfer = action == .transferOwner
            let label = transfer ? shellString("chatTransferOwner", "Make group owner") : shellString("chatRemoveMember", "Remove from group")
            ConfirmStep(title: label, message: transfer
                    ? shellString("chatTransferOwnerConfirm", "Make {name} the owner of “{group}”? You become a regular member and can no longer undo this yourself.",
                                  ["name": name, "group": chat.name])
                    : shellString("chatRemoveMemberConfirm", "Remove {name} from “{group}”? They stop seeing new messages.", ["name": name, "group": chat.name]),
                    label: label, onClose: close) { await model.run(action, on: userId, in: chat) }
        }
    }
}

/// Asks before something that cannot be undone; closes once it is done (a failure is shown by the shell's toast).
private struct ConfirmStep: View {
    let title: String
    let message: String
    let label: String?
    let onClose: () -> Void
    let run: () async -> Bool

    var body: some View {
        AppConfirmDialog(title: title, message: message, confirmLabel: label, destructive: true,
                         onConfirm: { Task { if await run() { onClose() } } }, onCancel: onClose)
    }
}
