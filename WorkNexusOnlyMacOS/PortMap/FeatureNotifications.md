# Port map - FeatureNotifications

Paths: Dart under `lib/`, Swift under `Packages/WorkNexusKit/Sources/FeatureNotifications/`. Public entry point:
`NotificationsFeature.makeModel(services:hooks:)` (+ `NotificationsBellButton`, `NotificationsPanel`, `NotificationsHooks`).
The `zenTaoNotifications` table / repository stay in ToolZenTao and are reached through the hoisted
`ZenTaoNotificationRepository` (CoreDomain, `AppServices.zentaoMessages`). No migration registrar.

| Area | Dart | Swift |
|---|---|---|
| Notification entity | features/notifications/domain/entities/zentao_notification.dart | CoreDomain/Entities/ZenTaoNotification.swift (hoisted) |
| Repository interface (+ realnames stream) | features/notifications/domain/repositories/notification_repository.dart | CoreDomain/Repositories/ZenTaoFeatureRepositories.swift (hoisted); GRDB impl in ToolZenTao/Data/Local/GRDBZenTaoNotificationRepository.swift |
| Action enum | domain/value_objects/notification_action.dart | Domain/ValueObjects/NotificationAction.swift |
| Parse "who did what" (en + zh-cn) | domain/usecases/parse_notification_event.dart | Domain/UseCases/ParseNotificationEvent.swift |
| Hide the user's own actions | domain/usecases/filter_self_notifications.dart | Domain/UseCases/FilterSelfNotifications.swift |
| New-since-last-list (desktop alerts) | domain/usecases/find_new_notifications.dart | Domain/UseCases/FindNewNotifications.swift |
| Group by local day | domain/usecases/group_notifications_by_day.dart | Domain/UseCases/GroupNotificationsByDay.swift |
| Refresh several accounts | domain/usecases/refresh_notifications.dart | Domain/UseCases/RefreshNotifications.swift |
| "One each, or one counting them" rule (max 3) | presentation/widgets/notification_alerts.dart | Domain/UseCases/PlanDesktopAlerts.swift |
| Alert payload `{"zn","a"}` | presentation/widgets/notification_alerts.dart | Data/Models/NotificationAlertPayload.swift |
| 2-minute poll (`Timer.periodic`) | presentation/providers/notification_providers.dart | Data/Services/NotificationPoller.swift (Task-based, injectable sleep) |
| Providers (accounts, realnames, filtered list, unread count, tab, refresh controller), commands, open, alerts, tap | presentation/providers/notification_providers.dart, util/notification_actions.dart, widgets/notification_alerts.dart | Presentation/Providers/NotificationsModel.swift (`@Observable`) |
| App-level side effects (open ticket, browser, toast, window focus) | core/navigation/open_zentao_ticket.dart, DesktopWindowService, showAppSnack | Presentation/Support/NotificationsHooks.swift |
| Event text / l10n | presentation/util/notification_event_text.dart | Presentation/Support/NotificationStrings.swift |
| Card | presentation/widgets/notification_card.dart | Presentation/Widgets/NotificationCard.swift |
| Day list + heading | presentation/widgets/notification_day_list.dart | Presentation/Widgets/NotificationDayList.swift |
| Header (mark all / delete read / refresh / close, Unread / All tabs) | presentation/widgets/notifications_header.dart | Presentation/Widgets/NotificationsHeader.swift |
| Panel (scrim, slide-in, Escape, states) | presentation/widgets/notifications_panel.dart | Presentation/Widgets/NotificationsPanel.swift |
| Rail bell with unread count | presentation/widgets/notifications_rail_button.dart | Presentation/Widgets/NotificationsBellButton.swift |
| Desktop notification / Dock badge | core/platform/desktop_notifier.dart, app_icon_badge.dart | CoreUI/Platform `DesktopNotifying` / `DockBadging` (injected) |

## Deviations
- `watchAccountRealnames()` was added to the hoisted `ZenTaoNotificationRepository` (default empty stream; GRDB impl reads `zenTaoProfiles`).
- The ICU `notificationAction` select cannot live in the xcstrings catalog (its converted value is unusable), so the verb table (en / vi) is in `NotificationStrings`, picked by the main bundle's preferred localization.
- Dart's `Timer.periodic` first tick is after 2 min; the first fetch happens as soon as a ZenTao account appears (as `build()` did).
- The Dock badge defaults to the unread count (`showDockBadge: false` / `dockBadge: nil` to disable) - the Flutter app only badged chat; the composition root may want to sum both.
- Package.swift: FeatureNotifications now also depends on CoreTools (`AppServices`).

## Tests (Tests/FeatureNotificationsTests)
| Dart test | Swift test |
|---|---|
| test/domain/{parse_notification_event,filter_self_notifications,find_new_notifications,notification_usecases}_test.dart | NotificationUseCaseTests.swift |
| (model: poll, optimistic commands, open, alerts, tap) | NotificationsModelTests.swift (fake repository / workspaces / notifier) |
| test/widget/notification_card_test.dart (layout) | RenderSmokeTests.swift (PNGs in /tmp/wn-feat-render/notifications-*.png) |
