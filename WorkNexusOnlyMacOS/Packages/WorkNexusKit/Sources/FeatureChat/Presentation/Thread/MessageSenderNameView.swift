/// Ported from: lib/features/chat/presentation/widgets/message_sender_name.dart
import CoreUI
import SwiftUI

/// A message sender's name, tapping through to their profile. With `time` it is the header over a run (ZenTao): the name
/// with the run's time beside it.
struct MessageSenderNameView: View {
    @Environment(\.appTheme) private var theme
    let ctx: ThreadContext
    let userId: Int
    let name: String
    let color: ChatColor
    var labelSize: CGFloat?
    var time: Date?
    var timeColor: ChatColor?
    var timeSize: CGFloat?

    var body: some View {
        // A tap, not a `Button` (see `MessageAvatarSlot`).
        Group {
            HStack(spacing: theme.spacing.s8) {
                Text(name)
                    .font(labelSize.map { theme.typography.font(size: $0, weight: .semibold) } ?? theme.typography.label)
                    .foregroundStyle(color.color).lineLimit(1)
                if let time {
                    Text(ChatTextLabels.clock(time))
                        .font(timeSize.map { theme.typography.font(size: $0) } ?? theme.typography.caption)
                        .foregroundStyle((timeColor ?? color).color)
                }
            }
        }
        .contentShape(Rectangle())
        .onTapGesture { ctx.actions.openProfile(userId) }
        .pointerStyle(.link)
        .accessibilityAddTraits(.isButton)
    }
}
