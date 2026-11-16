import Foundation

/// A one-click narrowing a team leader applies on top of the board's own filters. Not in the Flutter app.
public enum ZenTaoQuickFilter: String, CaseIterable, Sendable, Hashable, Codable {
    /// Open and past its deadline day.
    case overdue
    /// Open and due today or within `ZenTaoLeaderFilter.soonDays` days.
    case dueSoon
    case dueThisWeek
    /// Open with no deadline at all.
    case noDeadline
    /// Nobody holds it.
    case unassigned
    /// Priority 1 or 2 (urgent / high).
    case highPriority
    /// Open and untouched for `ZenTaoLeaderFilter.staleDays` days.
    case stale
    /// A task with no estimate.
    case noEstimate

    /// The chips about time are alternatives to each other (overdue *or* due soon); every other chip narrows further.
    public var isAboutTime: Bool { self == .overdue || self == .dueSoon || self == .dueThisWeek || self == .noDeadline }
}

/// What a team leader picked on a ZenTao board: whose work to show, which quick filters apply and a typed keyword.
/// Everything is combined with AND, except the time chips among themselves (see `ZenTaoQuickFilter.isAboutTime`).
public struct ZenTaoLeaderFilter: Hashable, Sendable {
    public static let soonDays = 3
    public static let staleDays = 7

    /// Logins of the people whose tickets to show.
    public var people: Set<String> = []
    public var quick: Set<ZenTaoQuickFilter> = []
    public var keyword: String = ""

    public init(people: Set<String> = [], quick: Set<ZenTaoQuickFilter> = [], keyword: String = "") {
        self.people = people; self.quick = quick; self.keyword = keyword
    }

    public var trimmedKeyword: String { keyword.trimmingCharacters(in: .whitespacesAndNewlines) }
    public var isActive: Bool { !people.isEmpty || !quick.isEmpty || !trimmedKeyword.isEmpty }

    public func toggled(_ chip: ZenTaoQuickFilter) -> ZenTaoLeaderFilter {
        var f = self
        if f.quick.contains(chip) { f.quick.remove(chip) } else { f.quick.insert(chip) }
        return f
    }

    public func toggled(person login: String) -> ZenTaoLeaderFilter {
        var f = self
        if f.people.contains(login) { f.people.remove(login) } else { f.people.insert(login) }
        return f
    }

    public func clearedAll() -> ZenTaoLeaderFilter { ZenTaoLeaderFilter() }
}
