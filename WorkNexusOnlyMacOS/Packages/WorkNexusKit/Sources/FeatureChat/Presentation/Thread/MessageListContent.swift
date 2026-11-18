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
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var model: MessageTimelineModel
    /// The list comes in a frame or two after the rest of the chat (see `ChatOpeningStage`).
    @State private var stage = ChatOpeningStage.chrome
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
            if stage.showsList {
                // Only the messages fade in as a chat opens: the header, input and panels look alike from chat to chat, and
                // fading them reads as a flicker. Only the opacity animates, never the rows coming in.
                MessageListScroll(ctx: ThreadContext(model: model, actions: actions), showSenders: showSenders, stage: stage)
                    .animation(reduceMotion ? nil : .easeOut(duration: theme.motion.base)) { $0.opacity(stage.isVisible ? 1 : 0) }
            }
            if stage.showsList && model.rows.isEmpty && !model.loadFailed {
                (model.loaded && !model.loadingOlder ? AppStateView(.empty(L.noMessages)) : AppStateView(.loading))
                    .allowsHitTesting(false)
            }
            // A jump window is never the latest, wherever it is scrolled.
            ScrollToLatestButton(visible: model.away || model.window.isAround, unseen: model.unseen) {
                if model.window.isAround { model.backToLatest() } else { model.scroll(to: .bottom) }
            }
            .padding(.trailing, theme.spacing.s24).padding(.bottom, theme.spacing.s16)
        }
        // Always the whole room between the header and the composer: before the list comes in (`ChatOpeningStage.chrome`)
        // the stack had nothing to fill it, so the chat shrank to its header and composer in the middle of the pane, with
        // no wallpaper, for the frames the opening took.
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .chatStyleScope()
        .task {
            model.report = { toasts?.show($0, kind: .error) }
            model.notify = { toasts?.show($0, kind: .success) }
            await model.run()
        }
        .task { await open() }
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

    /// Shows the list in stages, each a display frame after the one before (the frame has reached the screen by then).
    /// The newest-rows stage waits for the first page from storage, briefly, so it is not spent on an empty list.
    private func open() async {
        await NextDisplayFrame.wait()
        for _ in 0..<Self.loadWaitFrames where !model.loaded { await NextDisplayFrame.wait() }
        while stage != .all, !Task.isCancelled {
            stage = stage.next
            await NextDisplayFrame.wait()
        }
    }

    /// At most this many frames are spent waiting for the first page before the list shows anyway.
    private static let loadWaitFrames = 15
}
