/// Ported from: lib/features/chat/presentation/widgets/message_list.dart, message_list_view.dart
import SwiftUI

/// The message list of one open conversation: reversed (newest at the bottom), paging older messages near the top,
/// jumping to a message on `state.jump`, with bubbles drawn in the user's chat style. Needs `.chatServices(_:)` (and
/// `.chatSettings(_:)`, `.appTheme`) in the environment; the Shell sets `.chatThreadActions(_:)` (or passes `actions`) for what
/// lives in other slices (profile dialog, forward picker, sticker store). Put `ChatWallpaperView()` behind it.
public struct MessageListView: View {
    @Environment(\.chatServices) private var services
    @Environment(\.chatThreadActions) private var environmentActions
    let state: ChatThreadState
    let actions: ChatThreadActions?

    /// `actions` default to the ones set with `.chatThreadActions(_:)` in the environment.
    public init(state: ChatThreadState, actions: ChatThreadActions? = nil) {
        self.state = state; self.actions = actions
    }

    public var body: some View {
        if let services {
            // A new conversation starts a new timeline.
            MessageListContent(state: state, services: services, actions: actions ?? environmentActions).id(ObjectIdentifier(state))
        } else {
            Color.clear
        }
    }
}
