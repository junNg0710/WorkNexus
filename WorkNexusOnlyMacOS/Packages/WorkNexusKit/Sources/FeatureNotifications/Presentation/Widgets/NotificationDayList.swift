import CoreUI
import SwiftUI

/// Ported from: lib/features/notifications/presentation/widgets/notification_day_list.dart
/// The notifications under a heading per day, newest first.
struct NotificationDayList: View {
    @Environment(\.appTheme) private var theme
    let days: [NotificationDay]
    let model: NotificationsModel
    let dateFormat: String

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 0) {
                ForEach(days) { day in
                    NotificationDayHeading(day: day.day, count: day.items.count, dateFormat: dateFormat)
                    ForEach(day.items) { NotificationCard(notification: $0, model: model) }
                }
            }
            .padding(EdgeInsets(top: 0, leading: theme.spacing.s12, bottom: theme.spacing.s24, trailing: theme.spacing.s12))
        }
    }
}

/// "Today 4" - the day (relative when recent) and how many fell on it.
struct NotificationDayHeading: View {
    @Environment(\.appTheme) private var theme
    let day: Date?
    let count: Int
    let dateFormat: String

    var body: some View {
        AppSectionHeader(label, count: count)
            .padding(EdgeInsets(top: theme.spacing.s20, leading: theme.spacing.s12, bottom: theme.spacing.s4, trailing: theme.spacing.s12))
    }

    private var label: String {
        guard let day else { return NotificationStrings.undated }
        let calendar = Calendar.current
        let ago = calendar.dateComponents([.day], from: day, to: calendar.startOfDay(for: Date())).day ?? 0
        switch ago {
        case 0: return NotificationStrings.today
        case 1: return NotificationStrings.yesterday
        default: return AppDateFormat.format(day, style: dateFormat)
        }
    }
}
