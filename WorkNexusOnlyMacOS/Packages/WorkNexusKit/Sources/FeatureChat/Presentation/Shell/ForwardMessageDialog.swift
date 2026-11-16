import CoreDomain
import CoreUI
import SwiftUI

/// Picks one or more chats of the message's account and forwards the message to them. Lists only chats the user may post in.
/// Ported from: lib/features/chat/presentation/widgets/forward_message_dialog.dart
struct ForwardMessageDialog: View {
    @Environment(\.appTheme) private var theme
    let model: ChatShellModel
    let message: ChatMessage
    @State private var search = ""
    @State private var selected: [String] = []
    @State private var busy = false

    var body: some View {
        let shown = ForwardTargets.chats(model.conversations, users: model.users, selfUserId: model.selfUserId, query: search)
        AppDialogFrame(title: shellString("chatForwardTitle", "Forward to…"), leadingIcon: "arrowshape.turn.up.right",
                       maxWidth: theme.sizes.dialogSm, onClose: close) {
            VStack(alignment: .leading, spacing: theme.spacing.s12) {
                Text(ChatShellLabels.preview(message)).font(theme.typography.meta).foregroundStyle(theme.colors.tx2).lineLimit(2)
                AppSearchField(text: $search, hint: shellString("chatSearch", "Search"), autofocus: true)
                if shown.isEmpty {
                    AppStateView(.empty(shellString("chatNoMatches", "No matches")))
                } else {
                    ScrollView {
                        LazyVStack(spacing: 0) {
                            ForEach(shown) { row in
                                ForwardChatRow(chat: row, users: model.users, picked: selected.contains(row.id)) { toggle(row.id) }
                            }
                        }
                    }
                }
            }
            // A fixed height: searching must not make the dialog grow and shrink.
            .padding(.horizontal, theme.spacing.s24).padding(.bottom, theme.spacing.s12).frame(height: theme.sizes.dialogMd)
        } actions: {
            Spacer(minLength: 0)
            AppButton(shellString("chatCancel", "Cancel"), kind: .ghost, action: close)
            AppButton(label, kind: .primary) { Task { await forward() } }.disabled(selected.isEmpty || busy)
        }
    }

    private var label: String {
        selected.count > 1 ? shellString("chatForwardTo", "Forward to {count} chats", ["count": "\(selected.count)"]) : shellString("chatForward", "Forward")
    }

    private func close() { model.forwardMessage = nil }
    private func toggle(_ gid: String) { if let at = selected.firstIndex(of: gid) { selected.remove(at: at) } else { selected.append(gid) } }

    private func forward() async {
        busy = true
        let count = selected.count
        if await model.forward(message, to: selected) {
            model.toasts.show(count == 1 ? shellString("chatForwarded", "Forwarded", ["count": "1"])
                              : shellString("chatForwarded", "Forwarded to {count} chats", ["count": "\(count)"]))
            close()
        } else { busy = false }
    }
}
