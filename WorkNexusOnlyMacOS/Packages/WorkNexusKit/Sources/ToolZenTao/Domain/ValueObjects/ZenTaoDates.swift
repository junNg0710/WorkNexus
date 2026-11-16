/// Ported from: dart:core DateTime.tryParse / toIso8601String
import Foundation

/// Mirrors Dart's `DateTime.tryParse` for the shapes ZenTao sends: `yyyy-MM-dd`, optionally followed by
/// `T`/space and `HH:mm[:ss[.fraction]]`, optionally `Z` or a `+hh[:mm]` offset. Without a zone the time is
/// local (as in Dart).
public enum ZenTaoDayParser {
    private static let pattern = try! NSRegularExpression(
        pattern: #"^([+-]?\d{4,6})-?(\d\d)-?(\d\d)(?:[ T](\d\d)(?::?(\d\d)(?::?(\d\d)(?:[.,](\d+))?)?)?( ?[zZ]| ?([-+])(\d\d)(?::?(\d\d))?)?)?$"#)

    public static func parse(_ text: String) -> Date? {
        let s = text.trimmingCharacters(in: .whitespacesAndNewlines)
        let ns = s as NSString
        guard let m = pattern.firstMatch(in: s, range: NSRange(location: 0, length: ns.length)) else { return nil }
        func group(_ i: Int) -> String? {
            let r = m.range(at: i)
            return r.location == NSNotFound ? nil : ns.substring(with: r)
        }
        guard let year = group(1).flatMap({ Int($0) }), let month = group(2).flatMap({ Int($0) }),
              let day = group(3).flatMap({ Int($0) }) else { return nil }
        let hour = group(4).flatMap { Int($0) } ?? 0
        let minute = group(5).flatMap { Int($0) } ?? 0
        let second = group(6).flatMap { Int($0) } ?? 0
        var nano = 0
        if let f = group(7) { nano = Int((Double("0.\(f)") ?? 0) * 1_000_000_000) }
        var cal = Calendar(identifier: .gregorian)
        if let zoneText = group(8) {
            if zoneText.trimmingCharacters(in: .whitespaces).lowercased() == "z" {
                cal.timeZone = TimeZone(secondsFromGMT: 0)!
            } else {
                let sign = group(9) == "-" ? -1 : 1
                let oh = group(10).flatMap { Int($0) } ?? 0, om = group(11).flatMap { Int($0) } ?? 0
                cal.timeZone = TimeZone(secondsFromGMT: sign * (oh * 3600 + om * 60)) ?? .current
            }
        } else {
            cal.timeZone = .current
        }
        let comps = DateComponents(calendar: cal, timeZone: cal.timeZone, year: year, month: month, day: day,
                                   hour: hour, minute: minute, second: second, nanosecond: nano)
        guard hour < 24, minute < 60, second < 60, comps.isValidDate(in: cal) else { return nil }
        return cal.date(from: comps)
    }

    /// Dart's `DateTime.toIso8601String()`: local times carry no zone, UTC ends in `Z`; milliseconds always shown.
    public static func iso8601(_ date: Date) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = .current
        f.dateFormat = "yyyy-MM-dd'T'HH:mm:ss.SSS"
        return f.string(from: date)
    }
}
