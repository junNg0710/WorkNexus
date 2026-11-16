import CoreDomain
import CoreTools
import CoreUI
import Foundation

/// Public entry point of FeatureNotifications: ZenTao's web notifications (the bell menu) as a local-first feed.
///
/// ### What the composition root wires
/// - **Model**: `makeModel(services:hooks:)` builds the one `NotificationsModel`; keep it alive for the whole app
///   run and call `start()` once the shell is up (it watches the stored list, the ZenTao accounts and their
///   realnames, polls ZenTao every 2 minutes through a Task-based scheduler, raises desktop notifications for new
///   unread ones and mirrors the unread count on the Dock badge). Returns nil when `AppServices.zentaoMessages`
///   is not wired.
/// - **Views**: `NotificationsBellButton(model:)` (rail destination with the unread count; hides itself without a
///   ZenTao account) and `NotificationsPanel(model:leftInset:dateFormat:)` (slide-over panel; put it in an overlay
///   above the shell content, under the detail slide-over).
/// - **Hooks**: `NotificationsHooks(openTicket: nav.openTicket, toast: ...)` - the app-level side effects.
/// - **Database**: none. The `zenTaoNotifications` table and its repository belong to ToolZenTao (reached through
///   the hoisted `ZenTaoNotificationRepository` in CoreDomain); no migration registrar here.
public enum NotificationsFeature {
    public static let name = "FeatureNotifications"

    /// - Parameters:
    ///   - notifier: desktop notification sink (pass nil to disable alerts).
    ///   - dockBadge / showDockBadge: the Dock icon badge showing the unread count (the real `DockBadge` unless
    ///     `showDockBadge` is false, e.g. when the app badges something else).
    ///   - poller: the 2-minute refresh scheduler.
    @MainActor
    public static func makeModel(services: AppServices, hooks: NotificationsHooks,
                                 notifier: DesktopNotifying? = DesktopNotifier(), dockBadge: DockBadging? = nil, showDockBadge: Bool = true,
                                 poller: NotificationPoller = NotificationPoller()) -> NotificationsModel? {
        guard let repository = services.zentaoMessages else { return nil }
        let tickets = services.zentaoTickets
        return NotificationsModel(
            repository: repository, workspaces: services.workspaces,
            resolveTicket: tickets.map { svc in { host, type, id in await svc.fetchZenTaoTicket(host: host, type: type, id: id) } },
            notifier: notifier, dockBadge: dockBadge ?? (showDockBadge ? DockBadge() : nil), hooks: hooks, poller: poller)
    }
}
