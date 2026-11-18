/// Not in the Flutter app: share a link (a ticket's) into chats from the detail panel.
import CoreDomain
import CoreUI
import SwiftUI

/// Picks one or more chats of `accountId` (those the user may post in) and sends them `text` - a ticket's "#12 Title" and
/// link - so it can be passed on without opening the chat and pasting it.
public struct ChatShareDialog: View {
    @Environment(\.appTheme) private var theme
    @Environment(\.toasts) private var toasts
    let accountId: String
    let services: ChatServices
    let text: String
    let onClose: () -> Void
    @State private var conversations: [ChatConversation] = []
    @State private var users: [Int: ChatUser] = [:]
    @State private var selfUserId: Int?
    @State private var search = ""
    @State private var selected: [String] = []
    @State private var busy = false
    @State private var error: String?

    public init(accountId: String, services: ChatServices, text: String, onClose: @escaping () -> Void) {
        self.accountId = accountId; self.services = services; self.text = text; self.onClose = onClose
    }

    public var body: some View {
        let shown = ForwardTargets.chats(conversations, users: users, selfUserId: selfUserId, query: search)
        AppDialogFrame(title: shellString("chatShareTitle", "Share in chat"), leadingIcon: "paperplane", maxWidth: theme.sizes.dialogSm, onClose: onClose) {
            VStack(alignment: .leading, spacing: theme.spacing.s12) {
                Text(text).font(theme.typography.meta).foregroundStyle(theme.colors.tx2).lineLimit(3)
                AppSearchField(text: $search, hint: shellString("chatSearch", "Search"), autofocus: true)
                if shown.isEmpty {
                    AppStateView(conversations.isEmpty ? .loading : .empty(shellString("chatNoMatches", "No matches")))
                } else {
                    ScrollView {
                        LazyVStack(spacing: 0) {
                            ForEach(shown) { row in
                                ForwardChatRow(chat: row, users: users, picked: selected.contains(row.id)) { toggle(row.id) }
                            }
                        }
                    }
                }
                if let error { Text(error).font(theme.typography.caption).foregroundStyle(theme.colors.red) }
            }
            // A fixed height: searching must not make the dialog grow and shrink.
            .padding(.horizontal, theme.spacing.s24).padding(.bottom, theme.spacing.s12).frame(height: theme.sizes.dialogMd)
        } actions: {
            Spacer(minLength: 0)
            AppButton(shellString("chatCancel", "Cancel"), kind: .ghost, action: onClose)
            AppButton(label, kind: .primary) { Task { await share() } }.disabled(selected.isEmpty || busy)
        }
        .task { await watch() }
    }

    private var label: String {
        selected.count > 1 ? shellString("chatShareTo", "Send to {count} chats", ["count": "\(selected.count)"]) : shellString("chatShareSend", "Send")
    }

    private func toggle(_ gid: String) { if let at = selected.firstIndex(of: gid) { selected.remove(at: at) } else { selected.append(gid) } }

    private func watch() async {
        let repo = services.chat, id = accountId
        await withTaskGroup(of: Void.self) { group in
            group.addTask { @MainActor in for await list in repo.watchConversations(accountId: id) { conversations = list } }
            group.addTask { @MainActor in for await list in repo.watchUsers(accountId: id) { users = Dictionary(list.map { ($0.userId, $0) }, uniquingKeysWith: { a, _ in a }) } }
            group.addTask { @MainActor in for await me in repo.watchSelfUserId(accountId: id) { selfUserId = me } }
        }
    }

    private func share() async {
        busy = true; error = nil
        let count = selected.count
        switch await ShareTextToChats(services.chat)(accountId: accountId, chatGids: selected, text: text) {
        case .success:
            toasts?.show(count == 1 ? shellString("chatSharedOne", "Sent") : shellString("chatShared", "Sent to {count} chats", ["count": "\(count)"]))
            onClose()
        case .failure(let f):
            busy = false; error = f.message
        }
    }
}
