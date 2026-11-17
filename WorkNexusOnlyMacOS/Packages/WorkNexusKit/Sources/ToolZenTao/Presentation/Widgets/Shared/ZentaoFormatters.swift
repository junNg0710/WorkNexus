/// Ported from: lib/tools/zentao/presentation/widgets/zentao_formatters.dart
import CoreDomain
import Foundation

/// Formatter and extraction utilities for ZenTao tickets and bugs.
public enum ZentaoFormatters {
    /// The target deadline from ticket metadata, labels, or the bug / task entity.
    public static func extractDeadline(_ t: Ticket) -> Date? { extractZenTaoDeadline(t) }

    /// "Delay 45 days" when the deadline has passed.
    public static func delayText(_ deadline: Date?, now: Date = Date()) -> String? {
        guard let deadline, deadline < now else { return nil }
        let days = max(Int(now.timeIntervalSince(deadline) / 86_400), 1)
        return "Delay \(days) \(days == 1 ? "day" : "days")"
    }

    /// Splits "[Module] Title" into the clean title and the module tag.
    public static func extractModule(_ raw: String) -> (title: String, module: String?) {
        guard let m = raw.range(of: #"^(\[[^\]]+(?:\]\[[^\]]+)*\])\s*(.*)$"#, options: .regularExpression) else { return (raw, nil) }
        let whole = String(raw[m])
        guard let close = whole.range(of: #"^(\[[^\]]+\])+"#, options: .regularExpression) else { return (raw, nil) }
        let tag = String(whole[close])
        return (String(whole[close.upperBound...]).trimmingCharacters(in: .whitespaces), tag)
    }

    /// Splits "[Discovery][Change Request] Title" (or "[Mobile] [SocialFi] Title") into the title and its leading
    /// bracketed tags, without the brackets. A title that is nothing but tags keeps them.
    public static func extractTags(_ raw: String) -> (title: String, tags: [String]) {
        var tags: [String] = []
        var rest = Substring(raw.trimmingCharacters(in: .whitespacesAndNewlines))
        while let m = rest.range(of: #"^\[([^\]]*)\]\s*"#, options: .regularExpression) {
            let inner = rest[m].drop(while: { $0 == "[" }).prefix(while: { $0 != "]" }).trimmingCharacters(in: .whitespaces)
            if !inner.isEmpty { tags.append(inner) }
            rest = rest[m.upperBound...]
        }
        if rest.isEmpty { return (raw.trimmingCharacters(in: .whitespacesAndNewlines), []) }
        return (String(rest), tags)
    }

    /// `YYYY-MM-DD`.
    public static func formatDeadline(_ d: Date) -> String { AppDateFormatBridge.iso(d) }
}

enum AppDateFormatBridge {
    static func iso(_ d: Date) -> String {
        CachedDateFormatter.string(d, format: "yyyy-MM-dd")
    }
}
