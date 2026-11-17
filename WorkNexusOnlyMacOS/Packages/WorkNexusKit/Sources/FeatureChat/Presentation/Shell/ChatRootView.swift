import CoreDomain
import CoreUI
import SwiftUI

/// The feature's single public view: connection banner, conversation list, the open thread and its side panels for one
/// ZenTao account. Reads `\.chatServices`, `\.chatSettings` and `\.appTheme` from the environment.
///
/// Open a chat from outside (a notification click) with a `ChatShellEvents` (`events.open(chatGid:)`) or an `openChat` binding.
/// Ported from: lib/features/chat/presentation/pages/chat_page.dart
public struct ChatRootView: View {
    @Environment(\.chatServices) private var services
    let account: Account
    let events: ChatShellEvents?
    let openChat: Binding<String?>?

    public init(account: Account) { self.account = account; events = nil; openChat = nil }
    public init(account: Account, events: ChatShellEvents) { self.account = account; self.events = events; openChat = nil }
    /// `openChat` holds a chat gid to open; the view clears it once it has.
    public init(account: Account, openChat: Binding<String?>) { self.account = account; events = nil; self.openChat = openChat }

    public var body: some View {
        if account.providerType != .zentao {
            AppStateView(.empty(shellString("chatNoZentaoAccount", "Connect a ZenTao account in Integrations to use chat.")))
        } else if let services {
            ChatShellView(account: account, services: services, events: events, openChat: openChat).id(account.id)
        } else {
            AppStateView(.empty(shellString("chatUnavailable", "Chat isn't available right now.")))
        }
    }
}

/// Owns the shell's view-model for one account and lays the list, thread and dialogs out.
struct ChatShellView: View {
    @Environment(\.appTheme) private var theme
    @State private var model: ChatShellModel
    @State private var layouts = ChatShellLayouts(width: ChatShellLayout.listWidth + ChatShellLayout.messagesMinWidth + ChatShellLayout.panelRoom)
    private let visibility = ChatPanelVisibility.shared
    let openChat: Binding<String?>?

    init(account: Account, services: ChatServices, events: ChatShellEvents?, openChat: Binding<String?>?) {
        let m = ChatShellModel(accountId: account.id, selfAccount: account.handle, repository: services.chat, events: events ?? ChatShellEvents())
        m.openURL = { services.openURL($0) }
        _model = State(initialValue: m)
        self.openChat = openChat
    }

    var body: some View {
        @Bindable var model = model
        VStack(spacing: 0) {
            ChatStatusBanner(model: model)
            ChatNotificationBanner(events: model.events)
            if let trust = model.needsTrust {
                ChatTrustGate(model: model, host: trust.host)
            } else {
                let layout = layouts.pick(listHidden: visibility.listHidden, infoHidden: visibility.infoHidden)
                HStack(spacing: 0) {
                    if !visibility.listHidden {
                        ConversationListPane(model: model, compact: layout.compactList)
                            .frame(width: layout.compactList ? ChatShellLayout.listCompactWidth : ChatShellLayout.listWidth)
                            .transition(.move(edge: .leading))
                    }
                    ChatThreadArea(model: model).environment(\.chatShellLayout, layout)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .animation(.easeOut(duration: theme.motion.base), value: visibility.listHidden)
                // Only a change of layout redraws the shell, not every point of a window resize.
                .onGeometryChange(for: ChatShellLayouts.self) { ChatShellLayouts(width: $0.size.width) } action: { layouts = $0 }
            }
        }
        .background(theme.colors.bg)
        .environment(\.chatPanelVisibility, visibility)
        .toastHost(model.toasts)
        .appDialog(isPresented: Binding(get: { model.showTrust && model.needsTrust != nil }, set: { model.showTrust = $0 })) {
            if let trust = model.needsTrust { ChatTrustDialog(model: model, request: trust) }
        }
        .appDialog(isPresented: $model.showNewChat) { NewChatDialog(model: model) }
        .appDialog(item: $model.profileUserId) { ChatUserProfileDialog(model: model, userId: $0) }
        .appDialog(item: $model.groupAvatarChat) { chat in
            ChatGroupAvatarDialog(model: model, chat: chat, title: ChatShellLabels.title(chat, model.users))
        }
        .appDialog(item: $model.forwardRequest) { ForwardMessageDialog(model: model, request: $0) }
        .task { model.start() }
        .onDisappear { model.stop() }
        .onChange(of: model.events.pendingChatGid, initial: true) { _, gid in
            guard let gid else { return }
            model.select(gid); model.events.pendingChatGid = nil
        }
        .onChange(of: model.events.pendingJump, initial: true) { _, target in
            guard let target else { return }
            model.select(target.chatGid)
            model.thread?.state.requestJump(to: target.serverId)
            model.events.pendingJump = nil
        }
        .onChange(of: openChat?.wrappedValue, initial: true) { _, gid in
            guard let gid else { return }
            model.select(gid); openChat?.wrappedValue = nil
        }
    }
}

/// Right of the list: the open chat, a spinner while its conversation is not known yet, or the "select" hint.
private struct ChatThreadArea: View {
    @Environment(\.appTheme) private var theme
    let model: ChatShellModel

    var body: some View {
        Group {
            if let thread = model.thread {
                ChatThreadPane(model: model, session: thread).id(thread.state.chatGid)
            } else if model.selectedGid != nil && !model.conversationsLoaded {
                AppStateView(.loading)
            } else {
                AppInlineNote(shellString("chatSelectConversation", "Select a conversation"))
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(theme.colors.bg)
    }
}
