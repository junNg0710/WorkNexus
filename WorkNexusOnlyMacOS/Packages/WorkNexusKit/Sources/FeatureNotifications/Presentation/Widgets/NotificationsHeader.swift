import CoreUI
import SwiftUI

/// Ported from: lib/features/notifications/presentation/widgets/notifications_header.dart
/// The panel's top: title, the list-wide actions (mark all read, delete read, refresh) and close, over the
/// Unread / All tabs - like ZenTao's bell menu.
struct NotificationsHeader: View {
    @Environment(\.appTheme) private var theme
    let model: NotificationsModel
    @State private var confirmDeleteRead = false

    var body: some View {
        VStack(alignment: .leading, spacing: theme.spacing.s12) {
            HStack(spacing: 0) {
                Text(NotificationStrings.title).font(theme.typography.title).foregroundStyle(theme.colors.tx).lineLimit(1)
                Spacer(minLength: theme.spacing.s8)
                AppIconButton("checklist.checked", help: NotificationStrings.markAllRead) { Task { await model.markAllRead() } }
                    .opacity(model.unreadCount == 0 ? 0.4 : 1).allowsHitTesting(model.unreadCount > 0)
                AppIconButton("trash", help: NotificationStrings.deleteRead) { confirmDeleteRead = true }
                if model.isRefreshing { AppInlineSpinner().frame(width: theme.sizes.control32, height: theme.sizes.control32) }
                else { AppIconButton("arrow.clockwise", help: NotificationStrings.refresh) { Task { await model.refresh() } } }
                AppIconButton("xmark", help: NotificationStrings.close) { model.closePanel() }
            }
            AppSegmentedTabs([
                AppSegmentedTab(label: NotificationStrings.unreadTab, active: model.unreadOnly, count: model.unreadCount) { model.unreadOnly = true },
                AppSegmentedTab(label: NotificationStrings.all, active: !model.unreadOnly) { model.unreadOnly = false },
            ])
        }
        .padding(EdgeInsets(top: theme.spacing.s12, leading: theme.spacing.s20, bottom: theme.spacing.s16, trailing: theme.spacing.s6))
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(theme.colors.card)
        .overlay(alignment: .bottom) { Rectangle().fill(theme.colors.line).frame(height: theme.borders.hairline) }
        .appConfirmDialog(isPresented: $confirmDeleteRead, title: NotificationStrings.deleteRead,
                          message: NotificationStrings.deleteReadConfirm, confirmLabel: NotificationStrings.delete, destructive: true) {
            Task { await model.deleteRead() }
        }
    }
}
