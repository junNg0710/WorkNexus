import CoreUI
import SwiftUI

/// Ported from: lib/features/notifications/presentation/widgets/notifications_rail_button.dart
/// The notifications destination of the app rail, with the unread count. Hidden when no ZenTao account is
/// connected. Same 60x54 cell as the shell's rail buttons so the composition root can drop it in the rail.
public struct NotificationsBellButton: View {
    @Environment(\.appTheme) private var theme
    @State private var hovering = false
    private let model: NotificationsModel

    public init(model: NotificationsModel) { self.model = model }

    public var body: some View {
        if !model.accounts.isEmpty {
            let selected = model.panelOpen
            Button { model.togglePanel() } label: {
                VStack(spacing: theme.spacing.s2) {
                    Image(systemName: "bell").font(.system(size: theme.sizes.icon20))
                    Text(NotificationStrings.title).font(theme.typography.caption).lineLimit(1)
                }
                .frame(width: 60, height: 54)
                .foregroundStyle(selected ? theme.colors.accent : theme.colors.tx2)
                .background(selected ? theme.colors.sel : (hovering ? theme.colors.panel2 : .clear), in: RoundedRectangle(cornerRadius: theme.radii.lg))
                .overlay(alignment: .topTrailing) { AppCountBadge(model.unreadCount).offset(x: -theme.spacing.s6, y: theme.spacing.s4) }
            }
            .buttonStyle(.plain).onHover { hovering = $0 }
            .help(NotificationStrings.title)
        }
    }
}
