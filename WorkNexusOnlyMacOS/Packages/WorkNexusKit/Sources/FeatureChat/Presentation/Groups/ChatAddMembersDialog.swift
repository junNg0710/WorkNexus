import CoreDomain
import CoreUI
import SwiftUI

/// Picks people to add to a group, with the new-chat dialog's people picker (its current members left out).
/// Ported from: lib/features/chat/presentation/widgets/chat_add_members_dialog.dart
struct ChatAddMembersDialog: View {
    @Environment(\.appTheme) private var theme
    let model: ChatShellModel
    let chat: ChatConversation
    let members: Set<Int>
    let onClose: () -> Void
    @State private var search = ""
    @State private var selected: [Int] = []
    @State private var busy = false
    /// The directory load's outcome; nil while it runs.
    @State private var directoryLoaded: Bool?

    var body: some View {
        AppDialogFrame(title: shellString("chatAddMembers", "Add members"), maxWidth: theme.sizes.dialogMd, onClose: onClose) {
            NewChatPeople(model: model, search: $search, selected: $selected, loading: directoryLoaded == nil,
                          failed: directoryLoaded == false, onRetry: { Task { await loadDirectory() } }, excluded: members)
                .padding(.horizontal, theme.spacing.s24).padding(.bottom, theme.spacing.s12)
                // A fixed height, so searching does not make the dialog jump.
                .frame(height: theme.sizes.dialogLg)
        } actions: {
            Spacer(minLength: 0)
            AppButton(shellString("chatCancel", "Cancel"), kind: .ghost, action: onClose)
            AppButton(shellString("chatAdd", "Add"), kind: .primary, action: add).disabled(selected.isEmpty || busy)
        }
        .task { await loadDirectory() }
    }

    /// Only users seen in chats are cached: load the whole directory.
    private func loadDirectory() async {
        directoryLoaded = nil
        if case .success = await model.repository.refreshUsers(accountId: model.accountId) { directoryLoaded = true } else { directoryLoaded = false }
    }

    private func add() {
        guard !selected.isEmpty, !busy else { return }
        busy = true
        Task {
            let ok = await model.addMembers(chat, selected)
            busy = false
            if ok { onClose() }
        }
    }
}
