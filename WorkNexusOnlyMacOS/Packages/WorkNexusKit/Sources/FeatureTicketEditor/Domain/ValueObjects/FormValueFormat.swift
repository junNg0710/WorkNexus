import Foundation

/// Ported from: lib/features/ticket_editor/presentation/widgets/{editor_date_input,task_progress_fields,task_form_fields}.dart
/// How ZenTao form values are shown and read: dates as `yyyy-MM-dd` (empty for none) and hours without a `.0`.
public enum FormValueFormat {
    private static func formatter() -> DateFormatter {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd"
        return f
    }
    public static func date(_ value: String) -> Date? { value.isEmpty ? nil : formatter().date(from: value) }
    public static func dateText(_ day: Date?) -> String { day.map { formatter().string(from: $0) } ?? "" }

    /// Hours as the inputs show them: blank for none, no `.0` on whole hours.
    public static func hoursText(_ h: Double) -> String {
        h == 0 ? "" : (h == h.rounded() ? "\(Int(h))" : "\(h)")
    }
    public static func parseHours(_ text: String) -> Double { Double(text) ?? 0 }

    /// A form-session id like ZenTao's own (`uniqid()`-style hex).
    public static func newFormUid() -> String { String(Int(Date().timeIntervalSince1970 * 1_000_000), radix: 16) }

    /// Longest draft title a menu shows whole, so a long one does not stretch the menu across the window.
    public static let draftTitleLength = 40
    public static func shortDraftTitle(_ title: String) -> String {
        let t = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard t.count > draftTitleLength else { return t }
        return String(t.prefix(draftTitleLength)).trimmingCharacters(in: .whitespaces) + "…"
    }
}
