import CoreDomain
import CoreUI
import SwiftUI

/// Ported from: lib/features/notifications/presentation/widgets/notification_card.dart
/// One notification, read top-down by what matters: who did what (the line to scan, bold while unread), then the
/// ticket it was done to (its number and title, quieter), with the time at the top right. Unread cards take a
/// faint accent tint, an accent border and a dot; read/unread and delete replace the time on hover so the list
/// stays calm. Tapping opens the object.
struct NotificationCard: View {
    @Environment(\.appTheme) private var theme
    let notification: ZenTaoNotification
    let model: NotificationsModel

    var body: some View {
        let n = notification
        let unread = !n.read
        let hasTitle = !(n.objectTitle ?? "").isEmpty
        HoverRegion { hovered in
            HStack(alignment: .top, spacing: theme.spacing.s12) {
                ZenTaoKindIcon(n.objectType, large: true)
                VStack(alignment: .leading, spacing: theme.spacing.s4) {
                    Text(n.summary.isEmpty && hasTitle ? (n.objectTitle ?? "") : NotificationStrings.eventText(n))
                        .font(theme.typography.bodyStrong.weight(unread ? .semibold : .medium))
                        .foregroundStyle(theme.colors.tx).lineLimit(2).multilineTextAlignment(.leading)
                    if hasTitle || n.objectId != nil { NotificationTicketLine(notification: n) }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                Group {
                    if hovered { NotificationActions(notification: n, model: model) }
                    else { NotificationTimeAndDot(notification: n) }
                }
                .frame(width: theme.sizes.control32 * 2, alignment: .topTrailing)
            }
            .padding(EdgeInsets(top: theme.spacing.s12, leading: theme.spacing.s12, bottom: theme.spacing.s12, trailing: theme.spacing.s6))
            .background(unread ? theme.colors.accent.opacity(0.07) : .clear, in: shape)
            .background(theme.colors.card, in: shape)
            .overlay(shape.stroke(unread ? theme.colors.accent.opacity(0.35) : theme.colors.line, lineWidth: theme.borders.hairline))
            .contentShape(shape)
            .onTapGesture { Task { await model.open(n) } }
            .pointerStyle(.link)
        }
        .padding(.bottom, theme.spacing.s10)
    }

    private var shape: RoundedRectangle { RoundedRectangle(cornerRadius: theme.radii.lg) }
}

/// "#6492 Feed: video autoplay…" - the ticket the event was about, its number set off in mono; the kind is the
/// icon's to show.
private struct NotificationTicketLine: View {
    @Environment(\.appTheme) private var theme
    let notification: ZenTaoNotification

    var body: some View {
        let title = notification.objectTitle ?? ""
        let number = notification.objectId.map { Text("#\($0)  ").font(theme.typography.mono).foregroundStyle(theme.colors.tx3) }
        (number ?? Text("")) + Text(title).font(theme.typography.paragraph).foregroundStyle(theme.colors.tx2)
    }
}

/// The time at the card's top right, and under it the unread dot.
private struct NotificationTimeAndDot: View {
    @Environment(\.appTheme) private var theme
    let notification: ZenTaoNotification

    var body: some View {
        VStack(alignment: .trailing, spacing: theme.spacing.s6) {
            if let at = notification.createdAt {
                Text(AppDateFormat.formatTime(hour: Calendar.current.component(.hour, from: at),
                                              minute: Calendar.current.component(.minute, from: at)))
                    .font(theme.typography.meta).foregroundStyle(theme.colors.tx3)
            }
            if !notification.read { Circle().fill(theme.colors.accent).frame(width: theme.spacing.s10, height: theme.spacing.s10) }
        }
        .padding(.top, theme.spacing.s2).padding(.trailing, theme.spacing.s6)
    }
}

private struct NotificationActions: View {
    let notification: ZenTaoNotification
    let model: NotificationsModel

    var body: some View {
        HStack(spacing: 0) {
            AppIconButton(notification.read ? "circle" : "checkmark.circle",
                          help: notification.read ? NotificationStrings.markUnread : NotificationStrings.markRead) {
                Task { notification.read ? await model.markUnread(notification) : await model.markRead(notification) }
            }
            AppIconButton("trash", help: NotificationStrings.delete) { Task { await model.delete(notification) } }
        }
    }
}
