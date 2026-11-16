/// Ported from: lib/features/chat/presentation/widgets/chat_read_only_bar.dart
import CoreUI
import SwiftUI

/// Stands in for the composer when `CanSendToChat` says the user may not send.
struct ChatReadOnlyBar: View {
    @Environment(\.appTheme) private var theme
    let adminsOnly: Bool

    var body: some View {
        HStack(spacing: theme.spacing.s8) {
            Image(systemName: "lock").font(.system(size: theme.sizes.icon14))
            Text(adminsOnly ? appString("chatReadOnlyAdmins", "Only admins can send messages in this chat")
                            : appString("chatReadOnly", "You can't send messages in this chat"))
                .font(theme.typography.paragraph)
        }
        .foregroundStyle(theme.colors.tx3)
        .frame(maxWidth: .infinity)
        .padding(.vertical, theme.spacing.s14)
        .background(theme.colors.panel)
        .overlay(alignment: .top) { Rectangle().fill(theme.colors.line).frame(height: theme.borders.hairline) }
    }
}
