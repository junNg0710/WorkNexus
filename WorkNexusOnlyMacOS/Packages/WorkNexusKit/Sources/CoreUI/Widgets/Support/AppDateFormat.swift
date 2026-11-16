import Foundation

/// Ported from: lib/core/util/relative_time.dart (`formatDate`) — the app-wide date format.
public enum AppDateFormat {
    /// `style` is `AppSettings.dateFormat`: "iso" (`2026-05-26`), "dmy" (`26/05/2026`) or "long" (localised
    /// `May 26, 2026`); `withTime` appends the 24h `HH:mm`.
    public static func format(_ date: Date, style: String = "iso", withTime: Bool = false,
                              locale: Locale = .current, calendar: Calendar = .current) -> String {
        func fmt(_ pattern: String?, long: Bool = false) -> String {
            let f = DateFormatter()
            f.calendar = calendar; f.timeZone = calendar.timeZone; f.locale = long ? locale : Locale(identifier: "en_US_POSIX")
            if long { f.setLocalizedDateFormatFromTemplate("yMMMd") } else { f.dateFormat = pattern }
            return f.string(from: date)
        }
        let day: String
        switch style {
        case "dmy": day = fmt("dd/MM/yyyy")
        case "long": day = fmt(nil, long: true)
        default: day = fmt("yyyy-MM-dd")
        }
        return withTime ? "\(day) \(fmt("HH:mm"))" : day
    }

    /// `HH:mm` (24-hour) → minutes since midnight; nil when not a valid time.
    public static func parseTime(_ text: String) -> (hour: Int, minute: Int)? {
        let parts = text.trimmingCharacters(in: .whitespaces).split(separator: ":", omittingEmptySubsequences: false)
        guard parts.count == 2, let h = Int(parts[0]), let m = Int(parts[1]), (0..<24).contains(h), (0..<60).contains(m),
              parts[1].count == 2 else { return nil }
        return (h, m)
    }

    public static func formatTime(hour: Int, minute: Int) -> String { String(format: "%02d:%02d", hour, minute) }
}
