/// Ported from: lib/features/chat/presentation/widgets/chat_emoji_side_panel.dart
import CoreUI
import SwiftUI

/// The emoji/sticker picker docked beside the chat (`ChatSidePanel.emoji`). Emoji go into the composer through
/// `state.pendingInsertion`; a sticker is sent right away.
public struct ChatEmojiSidePanel: View {
    @Environment(\.appTheme) private var theme
    let state: ChatThreadState

    public init(state: ChatThreadState) { self.state = state }

    public var body: some View {
        ChatEmojiTabs(state: state, onInsert: { state.pendingInsertion = $0 }, onSent: {}) {
            AppIconButton("arrow.down.right.and.arrow.up.left", help: appString("chatEmojiCollapse", "Collapse")) { state.sidePanel = nil }
        }
        .background(theme.colors.panel)
    }
}
