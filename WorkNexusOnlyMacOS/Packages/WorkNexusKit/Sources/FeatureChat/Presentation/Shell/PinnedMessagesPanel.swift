import CoreDomain
import CoreUI
import SwiftUI

/// Beside the chat: every pinned message, most recently pinned first; ones older than what is loaded are fetched.
/// Ported from: lib/features/chat/presentation/widgets/pinned_messages_panel.dart
struct PinnedMessagesPanel: View {
    @Environment(\.appTheme) private var theme
    @Environment(\.chatShellLayout) private var layout
    let model: ChatShellModel
    let session: ChatThreadSession
    @State private var pinned: PinnedMessagesModel

    init(model: ChatShellModel, session: ChatThreadSession) {
        self.model = model; self.session = session
        _pinned = State(initialValue: PinnedMessagesModel(accountId: session.state.accountId, chatGid: session.state.chatGid, repository: model.repository))
    }

    var body: some View {
        let ids = Array(session.state.chat.pinnedMessageIds.reversed())
        let found = ids.compactMap { pinned.messages[$0] }
        let missing = ids.filter { pinned.messages[$0] == nil }
        ChatSidePanelFrame(title: shellString("chatPinnedMessages", "Pinned messages"),
                           onBack: { session.state.backToInfo(infoRoom: layout.infoRoom) }, onClose: { session.state.closePanel() }) {
            if ids.isEmpty {
                AppStateView(.empty(shellString("chatNoPinned", "No pinned messages")))
            } else if found.isEmpty && pinned.failed {
                AppStateView(.error(shellString("chatMembersFailed", "Couldn't load the members"))) { pinned.retry(missing) }
            } else {
                ScrollView {
                    VStack(spacing: 0) {
                        ForEach(found) { m in PinnedCard(model: model, session: session, message: m) }
                        if pinned.failed {
                            HStack {
                                AppInlineNote(shellString("stateLoadFailedTitle", "Couldn't load"), isError: true)
                                Spacer(minLength: 0)
                                AppButton(shellString("retry", "Retry"), systemImage: "arrow.clockwise", kind: .ghost) { pinned.retry(missing) }
                            }
                        } else if missing.contains(where: { !pinned.answered.contains($0) }) {
                            AppInlineSpinner()
                        }
                    }
                    .padding(theme.spacing.s12)
                }
                // Pointing anywhere on the pins shows all of them while the privacy mode hides them.
                .chatPrivacyRevealRegion()
            }
        }
        .task(id: ids) { pinned.track(ids) }
        .onDisappear { pinned.stop() }
    }
}

/// One pinned message: a card with its preview, a jump to it in the chat and, for who may pin, an unpin button.
private struct PinnedCard: View {
    @Environment(\.chatShellLayout) private var layout
    let model: ChatShellModel
    let session: ChatThreadSession
    let message: ChatMessage

    var body: some View {
        let serverId = message.serverId
        ChatMessageCard(users: model.users, message: message, label: shellString("chatPinnedLabel", "Pinned message"),
                        labelIcon: "text.bubble", onViewOriginal: serverId.map { id in {
                            // Slid over the messages, the panel would hide the one jumped to.
                            if !layout.infoRoom { session.state.closePanel() }
                            session.state.requestJump(to: id)
                        } }) {
            if session.canPin {
                AppIconButton("pin.slash", help: shellString("chatUnpin", "Unpin")) {
                    Task { if case .failure(let f) = await PinChatMessage(model.repository)(message, pinned: false) { model.report(f) } }
                }
            }
        }
    }
}
