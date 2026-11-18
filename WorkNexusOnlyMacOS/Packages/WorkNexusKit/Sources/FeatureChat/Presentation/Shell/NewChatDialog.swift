import CoreDomain
import CoreUI
import SwiftUI

/// Starts a chat: pick one person for a direct chat (opened, or created on the server) or several for a group, which then
/// needs a name.
/// Ported from: lib/features/chat/presentation/widgets/new_chat_dialog.dart
struct NewChatDialog: View {
    @Environment(\.appTheme) private var theme
    let model: ChatShellModel
    @State private var search = ""
    @State private var groupName = ""
    @State private var selected: [Int] = []
    @State private var busy = false
    /// The group being made is public: anyone may find and join it.
    @State private var isPublic = false
    /// The directory load's outcome; nil while it runs.
    @State private var directoryLoaded: Bool?

    var body: some View {
        let group = selected.count > 1
        AppDialogFrame(title: shellString("chatNewChat", "New chat"), maxWidth: theme.sizes.dialogMd, onClose: { model.showNewChat = false }) {
            VStack(alignment: .leading, spacing: theme.spacing.s12) {
                Text(shellString("chatNewChatHint", "Pick one person for a direct chat, or several for a group."))
                    .font(theme.typography.paragraph).foregroundStyle(theme.colors.tx2)
                if group {
                    TextField("\(shellString("chatGroupName", "Group name")) · \(ChatPeople.defaultGroupName(selected, users: model.users))", text: $groupName)
                        .textFieldStyle(.roundedBorder).onSubmit(start)
                    ChatSettingsCard {
                        ChatSwitchRow(label: shellString("chatPublicGroup", "Public group"),
                                      hint: shellString("chatPublicGroupHint", "Anyone can find this group and join it"), isOn: $isPublic)
                    }
                }
                NewChatPeople(model: model, search: $search, selected: $selected, loading: directoryLoaded == nil,
                              failed: directoryLoaded == false) { Task { await loadDirectory() } }
            }
            .padding(.horizontal, theme.spacing.s24).padding(.bottom, theme.spacing.s12)
            .frame(height: theme.sizes.dialogLg)
        } actions: {
            Spacer(minLength: 0)
            AppButton(shellString("chatCancel", "Cancel"), kind: .ghost) { model.showNewChat = false }
            AppButton(group ? shellString("chatCreateGroup", "Create group") : shellString("chatSendMessage", "Message"), kind: .primary, action: start)
                .disabled(selected.isEmpty || busy)
        }
        .task { await loadDirectory() }
    }

    /// Only users seen in chats are cached: load the whole directory.
    private func loadDirectory() async {
        directoryLoaded = nil
        if case .success = await model.repository.refreshUsers(accountId: model.accountId) { directoryLoaded = true } else { directoryLoaded = false }
    }

    private func start() {
        guard !selected.isEmpty, !busy else { return }
        busy = true
        Task {
            let ok = selected.count == 1
                ? await model.openDirectChat(userId: selected[0])
                : await model.createGroup(name: groupName.trimmingCharacters(in: .whitespaces).isEmpty
                                          ? ChatPeople.defaultGroupName(selected, users: model.users) : groupName, memberIds: selected,
                                          isPublic: isPublic)
            busy = false
            if ok { model.showNewChat = false }
        }
    }
}
