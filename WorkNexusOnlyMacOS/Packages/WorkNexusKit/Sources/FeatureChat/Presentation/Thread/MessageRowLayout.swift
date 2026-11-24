/// Ported from: lib/features/chat/presentation/widgets/message_row.dart
import SwiftUI

/// A message laid out beside its sender's avatar column: `avatar` on the start side, or on the end side for `alignEnd`,
/// when there is one. With `name` the sender's name goes over the avatar and bubble together, so the avatar lines up with
/// the bubble; it is indented to the bubble's edge (past the avatar and the tail's room).
struct MessageRowLayout<Avatar: View, NameView: View, Content: View>: View {
    @Environment(\.appTheme) private var theme
    let hasAvatar: Bool
    let alignEnd: Bool
    /// The chat style: avatar size and placement, and the tail's room.
    let style: ChatStyle
    let name: NameView?
    @ViewBuilder let avatar: Avatar
    @ViewBuilder let content: Content

    var body: some View {
        let gap = theme.spacing.s8
        // The avatar sits by the run's last bubble (Telegram) or its first. One pass each (`ChatRowLayouts`), not stacks.
        let row = ChatRowSides(hasAvatar: hasAvatar, alignEnd: alignEnd, gap: gap, bottom: style.avatar == .lastOfRun) {
            if hasAvatar { avatar }
            content
        }
        if let name {
            let tailRoom = style.tail == nil ? 0 : BubbleTail.width
            let indent = tailRoom + (hasAvatar ? style.avatarSize + gap : 0)
            ChatColumn(trailing: alignEnd) {
                name.padding(.leading, alignEnd ? 0 : indent).padding(.trailing, alignEnd ? indent : 0).padding(.bottom, theme.spacing.s4)
                row
            }
        } else {
            row
        }
    }
}
