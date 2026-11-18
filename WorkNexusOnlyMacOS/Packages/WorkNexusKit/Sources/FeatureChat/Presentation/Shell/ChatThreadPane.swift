import CoreDomain
import CoreUI
import SwiftUI

/// The open chat: header, search bar, the message list, the composer (or the read-only bar) and the side panel host.
/// Pulls the newest page and marks the chat read when it opens (the shell keys it per chat, so this runs on every switch).
/// Ported from: lib/features/chat/presentation/widgets/thread_pane.dart
struct ChatThreadPane: View {
    @Environment(\.chatShellLayout) private var layout
    @Environment(\.chatPrivacyHidden) private var privacyHidden
    @Environment(\.chatServices) private var services
    let model: ChatShellModel
    let session: ChatThreadSession

    var body: some View {
        let state = session.state
        let panel = state.effectivePanel(infoRoom: layout.infoRoom)
        ChatSidePanelHost(infoRoom: layout.infoRoom, showsPanel: panel != nil, onDismiss: { state.closePanel() }) {
            VStack(spacing: 0) {
                // Pointing anywhere on the chat above the input shows all of it while the privacy mode hides it. Not the
                // input: the user types there.
                VStack(spacing: 0) {
                    ChatThreadHeader(model: model, session: session)
                    if session.search.isOpen { ChatThreadSearchBar(model: model, session: session) }
                    ChatAiCatchUpBanner(session: session)
                    // Dropped on the messages, files go out at once; dropped on the input, they wait there (as in Flutter).
                    MessageListView(state: state)
                        .overlay(alignment: .topLeading) { ChatFloatingVideo(model: state.video) }
                        .chatFileDrop(state: state, mode: .send)
                }
                .chatPrivacyRevealRegion()
                ChatComposerView(state: state, hint: shellString("chatMessageTo", "Type @ to mention, message {name}",
                                                                 ["name": composerName(state)]))
                    .chatFileDrop(state: state, mode: .stage)
                    // "Multiple select" covers the composer with its bar; what was being written stays underneath.
                    .overlay { if state.isSelecting { ChatSelectionBar(model: model, state: state) } }
            }
            .chatDropZones()
            .frame(maxWidth: .infinity)
            .background { ChatWallpaperView() }
            .chatStyleScope()
            .chatThreadActions(threadActions(state))
        } panel: {
            if let panel { ChatSidePanelContent(model: model, session: session, panel: panel) }
        }
        .onChange(of: state.sidePanel) { _, new in
            // Another slice asked for the search (`sidePanel = .search`): it is a bar here, not a panel.
            if new == .search { state.sidePanel = nil; session.search.isOpen = true }
        }
        .onDisappear { state.video.stop() }
        .onChange(of: state.chat.unreadCount) { _, unread in session.unreadChanged(unread) }
    }
}

extension ChatThreadPane {
    /// The chat's name in the input's hint, or dots while the privacy mode hides names (no reveal on hover: it is a hint).
    private func composerName(_ state: ChatThreadState) -> String {
        privacyHidden.contains(.identity) ? chatPrivacyMaskText : ChatShellLabels.title(state.chat, state.users)
    }

    /// What the message list asks of the rest of the chat UI: open a profile; save an image as a sticker.
    @MainActor private func threadActions(_ state: ChatThreadState) -> ChatThreadActions {
        var actions = ChatThreadActions(openProfile: { model.profileUserId = $0 },
                                        forward: { model.forwardRequest = ChatForwardRequest(messages: [$0]) })
        if let open = model.events.onCreateTicket {
            let accountId = model.accountId
            actions.createTicket = { kind, messages in
                open(ChatTicketRequest(kind: kind, accountId: accountId, seed: ChatMessageExport.seed(messages, state: state)))
            }
        }
        if let chat = services?.chat, let stickers = services?.stickers {
            let save = SaveImageAsSticker(chat, stickers)
            actions.saveAsSticker = { message in Task { _ = await save(accountId: message.accountId, content: message.content) } }
        }
        return actions
    }
}

/// The panel beside the chat: one at a time (`ChatThreadState.sidePanel`).
/// Ported from: lib/features/chat/presentation/widgets/thread_pane.dart
struct ChatSidePanelContent: View {
    let model: ChatShellModel
    let session: ChatThreadSession
    let panel: ChatSidePanel

    var body: some View {
        switch panel {
        case .info: ChatInfoPanel(model: model, session: session)
        case .members: ChatMembersPanel(model: model, session: session)
        case .pinned: PinnedMessagesPanel(model: model, session: session)
        case .files: ChatFilesPanel(model: model, session: session)
        case .thread(let rootId): ReplyThreadPanel(model: model, session: session, rootId: rootId).id(rootId)
        case .emoji, .stickers:
            ChatSidePanelFrame(title: shellString("chatEmojiPanelTitle", "Stickers & emoji"), onClose: { session.state.closePanel() }) {
                ChatEmojiSidePanel(state: session.state)
            }
        case .assistant: ChatAssistantPanel(session: session)
        case .search: EmptyView()
        }
    }
}
