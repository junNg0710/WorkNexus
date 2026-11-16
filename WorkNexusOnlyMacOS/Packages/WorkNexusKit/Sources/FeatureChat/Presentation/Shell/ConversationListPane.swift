import CoreDomain
import CoreUI
import SwiftUI

/// Left pane of the chat view: your avatar, search, My Cloud, new chat, the tabs and the chat list.
/// Ported from: lib/features/chat/presentation/widgets/conversation_list_pane.dart
struct ConversationListPane: View {
    @Environment(\.appTheme) private var theme
    @Environment(\.chatPanelVisibility) private var visibility
    let model: ChatShellModel
    let compact: Bool

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: theme.spacing.s8) {
                ChatSelfAvatarButton(model: model)
                AppSearchField(text: Binding(get: { model.searchText }, set: { model.setSearch($0) }),
                               hint: shellString("chatSearch", "Search chats"),
                               onSubmit: { model.openHighlighted() }, onMove: { model.moveHighlight($0) })
                AppIconButton("icloud", help: shellString("chatMyCloud", "My Cloud")) {
                    if let me = model.selfUserId { Task { await model.openDirectChat(userId: me) } }
                }
                .disabled(model.selfUserId == nil)
                AppIconButton("square.and.pencil", help: shellString("chatNewChat", "New chat")) { model.showNewChat = true }
                AppIconButton("sidebar.left", help: shellString("chatHideList", "Hide chat list")) { visibility.listHidden = true }
            }
            .padding(.horizontal, compact ? theme.spacing.s12 : theme.spacing.s20).padding(.vertical, theme.spacing.s12)
            Divider().overlay(theme.colors.line)
            ChatListTabs(model: model).padding(.vertical, theme.spacing.s6)
            Divider().overlay(theme.colors.line)
            ListBody(model: model, compact: compact)
        }
        .background(theme.colors.panel)
        .overlay(alignment: .trailing) { Rectangle().fill(theme.colors.line).frame(width: theme.borders.hairline) }
    }
}

private struct ListBody: View {
    let model: ChatShellModel
    let compact: Bool

    var body: some View {
        let listed = model.listed
        if !model.conversationsLoaded {
            AppStateView(.loading)
        } else if listed.isEmpty {
            AppStateView(.empty(model.isSearching ? shellString("chatNoMatches", "No chat matches")
                                : shellString("chatNoConversations", "No conversations yet")))
        } else {
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(listed) { item in ConversationRow(model: model, item: item, compact: compact).id(item.id) }
                    }
                }
                .onChange(of: model.highlightedGid) { _, gid in if let gid { proxy.scrollTo(gid) } }
            }
        }
    }
}
