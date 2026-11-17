/// Not in the Flutter app.
import Foundation

/// Date formatters made once and kept, by what they print. Creating a `DateFormatter` costs far more than formatting with
/// one; list rows that made a new one on every redraw (chat list times, message clocks, board and overview dates) were a
/// share of the work behind stuttering scrolls. Formatting with a shared formatter is thread-safe.
public enum CachedDateFormatter {
    private final class Store: @unchecked Sendable {
        let lock = NSLock()
        var formatters: [String: DateFormatter] = [:]
    }
    private static let store = Store()
    public static let posix = Locale(identifier: "en_US_POSIX")

    /// `date` in the fixed `format` (e.g. `HH:mm`, `yyyy-MM-dd`).
    public static func string(_ date: Date, format: String, locale: Locale = posix, timeZone: TimeZone = .current,
                              calendar: Calendar? = nil) -> String {
        formatter(kind: "f", pattern: format, locale: locale, timeZone: timeZone, calendar: calendar).string(from: date)
    }

    /// `date` in the user's own order for `template` (e.g. `MMMd` → "Oct 12" / "12 thg 10").
    public static func string(_ date: Date, template: String, locale: Locale = .current, timeZone: TimeZone = .current,
                              calendar: Calendar? = nil) -> String {
        formatter(kind: "t", pattern: template, locale: locale, timeZone: timeZone, calendar: calendar).string(from: date)
    }

    /// The date `text` holds in the fixed `format`, read strictly (nil for anything else).
    public static func date(from text: String, format: String, locale: Locale = posix, timeZone: TimeZone = .current) -> Date? {
        formatter(kind: "p", pattern: format, locale: locale, timeZone: timeZone, calendar: nil).date(from: text)
    }

    private static func formatter(kind: String, pattern: String, locale: Locale, timeZone: TimeZone, calendar: Calendar?) -> DateFormatter {
        let key = "\(kind)|\(pattern)|\(locale.identifier)|\(timeZone.identifier)|\(calendar.map { "\($0.identifier)" } ?? "-")"
        return store.lock.withLock {
            if let kept = store.formatters[key] { return kept }
            let f = DateFormatter()
            if let calendar { f.calendar = calendar }
            f.locale = locale; f.timeZone = timeZone
            if kind == "t" { f.setLocalizedDateFormatFromTemplate(pattern) } else { f.dateFormat = pattern }
            if kind == "p" { f.isLenient = false }
            store.formatters[key] = f
            return f
        }
    }
}
