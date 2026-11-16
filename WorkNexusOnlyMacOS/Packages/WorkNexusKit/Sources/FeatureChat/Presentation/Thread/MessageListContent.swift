/// Ported from: lib/features/chat/presentation/widgets/message_list.dart (MessageList)
import CoreDomain
import CoreUI
import SwiftUI

/// The messages of one chat, newest at the bottom. Earlier messages load on their own as the user scrolls near the top —
/// and, in a window jumped to far back, later ones near the bottom. New messages are marked read once they are on screen:
/// right away at the bottom, or when the user scrolls back down from older ones.
struct MessageListContent: View {
    @Environment(\.chatSettings) private var settings
    @Environment(\.appTheme) private var theme
    @Environment(\.toasts) private var toasts
    @State private var model: MessageTimelineModel
    let actions: ChatThreadActions

    init(state: ChatThreadState, services: ChatServices, actions: ChatThreadActions) {
        _model = State(initialValue: MessageTimelineModel(state: state, services: services))
        self.actions = actions
    }

    var body: some View {
        let state = model.state
        // Group chats show sender names; one-to-one chats do not.
        let showSenders = state.chat.type != .one2one
        ZStack(alignment: .bottomTrailing) {
            MessageListScroll(ctx: ThreadContext(model: model, actions: actions), showSenders: showSenders)
            if model.rows.isEmpty && !model.loadFailed {
                (model.loaded && !model.loadingOlder ? AppStateView(.empty(L.noMessages)) : AppStateView(.loading))
                    .allowsHitTesting(false)
            }
            // A jump window is never the latest, wherever it is scrolled.
            ScrollToLatestButton(visible: model.away || model.window.isAround, unseen: model.unseen) {
                if model.window.isAround { model.backToLatest() } else { model.scroll(to: .bottom) }
            }
            .padding(.trailing, theme.spacing.s24).padding(.bottom, theme.spacing.s16)
        }
        .chatStyleScope()
        .task {
            model.report = { toasts?.show($0, kind: .error) }
            model.notify = { toasts?.show($0, kind: .success) }
            await model.run()
        }
        .onChange(of: settings.reactions, initial: true) { _, on in model.reactionsOn = on }
        .onChange(of: settings.appearance, initial: true) { _, a in
            model.markerGap = ChatStyle.resolve(a, theme: theme).separatorGap
        }
        // A jump asked for while shown, or before the list existed (tapping a notification opens the chat first): taken once.
        .onChange(of: state.jump, initial: true) { _, request in
            guard let request else { return }
            state.jump = nil
            Task { await model.jump(to: request.serverId) }
        }
    }
}
