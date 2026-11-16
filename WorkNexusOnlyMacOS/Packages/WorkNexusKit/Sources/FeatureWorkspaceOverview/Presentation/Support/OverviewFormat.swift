/// Ported from: lib/features/workspace_overview/presentation/util/{short_when,my_work_status,dashboard_status_color}.dart
import CoreDomain
import CoreUI
import Foundation
import SwiftUI

/// A compact age for dense rows: "5m ago", "3h ago", "4d ago", then the date.
func shortWhen(_ t: Date?, now: Date = Date(), locale: Locale = .current) -> String {
    guard let t else { return "" }
    let diff = now.timeIntervalSince(t)
    let minutes = Int(diff / 60), hours = Int(diff / 3600), days = Int(diff / 86400)
    if minutes < 1 { return OL.justNow }
    if hours < 1 { return OL.minutesAgo(minutes) }
    if days < 1 { return OL.hoursAgo(hours) }
    if days < 7 { return OL.daysAgo(days) }
    return monthDay(t, locale: locale)
}

/// "Oct 12" in the user's locale.
func monthDay(_ date: Date, locale: Locale = .current) -> String {
    let f = DateFormatter()
    f.locale = locale
    f.setLocalizedDateFormatFromTemplate("MMMd")
    return f.string(from: date)
}

/// A ZenTao date field (`2026-10-12`), or nil for its empty forms (`""`, `0000-00-00`).
func parseZenTaoDate(_ raw: String?) -> Date? {
    let text = raw?.trimmingCharacters(in: .whitespaces) ?? ""
    guard text.count >= 10, let year = Int(text.prefix(4)), year >= 2000 else { return nil }
    let f = DateFormatter()
    f.locale = Locale(identifier: "en_US_POSIX"); f.dateFormat = "yyyy-MM-dd"; f.isLenient = false
    return f.date(from: String(text.prefix(10)))
}

/// Colour for a ZenTao status code across bugs, tasks, stories, todos and executions. Only `active` differs by
/// kind: an open bug is a problem, an active story is just in progress.
func dashboardStatusColor(_ c: AppPalette, _ status: String?, bug: Bool = false) -> Color {
    switch status {
    case "active" where bug: c.red
    case "delay": c.red
    case "active", "doing", "reviewing", "changing": c.accent
    case "confirmed", "pause", "suspended", "postponed": c.amber
    case "resolved", "done": c.green
    default: c.tx3
    }
}

/// ZenTao's own word for where a bug or task stands. The unified status already encodes it (a confirmed bug is
/// `todo`, a paused task `blocked`), so rows, section headers and pills all read the same.
func myWorkStatusLabel(_ status: UnifiedStatus, bug: Bool) -> String {
    if bug {
        switch status {
        case .inbox: return OL.statusUnconfirmed
        case .review: return OL.statusResolved
        case .done: return OL.statusClosed
        default: return OL.statusToFix
        }
    }
    switch status {
    case .inprogress: return OL.statusDoing
    case .blocked: return OL.statusPaused
    case .review: return OL.statusDone
    case .done: return OL.statusClosed
    default: return OL.statusWaiting
    }
}

/// Labels of the ZenTao status codes an execution / todo carries, for when the server sends none.
func zentaoStatusWord(_ status: String, execution: Bool) -> String {
    switch status {
    case "wait": OL.statusWaiting
    case "doing": OL.statusDoing
    case "suspended" where execution: OL.statusPaused
    case "done" where !execution: OL.statusDone
    case "closed": OL.statusClosed
    default: status
    }
}

/// Fixed design measurements of the overview (the Dart sizes / breakpoints that are not theme tokens).
enum OverviewLayout {
    static let pageMaxWidth: CGFloat = 1000
    static let workPageMaxWidth: CGFloat = 1600
    static let stateMessageMax: CGFloat = 360
    static let stateTile: CGFloat = 48
    static let toolCardMinWidth: CGFloat = 260
    static let threeColumnsWidth: CGFloat = 840
    static let twoColumnsWidth: CGFloat = 560
    static let dashboardTwoColumnWidth: CGFloat = 900
    static let workTwoColumnsWidth: CGFloat = 960
    static let keyColumn: CGFloat = 80
    static let timeColumn: CGFloat = 100
    /// Keeps the progress bars of a list the same length whatever the percentages read.
    static let percentColumn: CGFloat = 40
    static let factNameMax: CGFloat = 200
    static let rowsPerGroup = 5
    static let activityRows = 5
    static let assignedCap = 20
    static let progressHeight: CGFloat = 6
    static let dotSize: CGFloat = 8
}
