import CoreDomain
import Foundation

/// Where a ticket stands against its deadline, counted in whole calendar days (ZenTao's deadlines are days).
public enum ZenTaoDeadlineState: Equatable, Sendable {
    /// Closed, done or cancelled: a deadline no longer matters.
    case finished
    case none
    case overdue(days: Int)
    case today
    case upcoming(days: Int)

    public var isOverdue: Bool { if case .overdue = self { true } else { false } }
}

/// Whether a ZenTao bug or task still needs someone: a bug until it is closed (a resolved one waits for its
/// verification), a task until it is done, closed or cancelled.
public func zentaoIsOpen(_ ticket: Ticket) -> Bool {
    let raw = ticket.providerStatus.trimmingCharacters(in: .whitespaces).lowercased()
    if raw == "closed" || raw == "cancel" { return false }
    if (ticket.externalType ?? "").lowercased() == "task", raw == "done" { return false }
    return ticket.status != .done
}

public func zentaoDeadlineState(_ ticket: Ticket, now: Date = Date(), calendar: Calendar = .current) -> ZenTaoDeadlineState {
    guard zentaoIsOpen(ticket) else { return .finished }
    guard let deadline = extractZenTaoDeadline(ticket) else { return .none }
    let today = calendar.startOfDay(for: now), due = calendar.startOfDay(for: deadline)
    let days = calendar.dateComponents([.day], from: today, to: due).day ?? 0
    if days < 0 { return .overdue(days: -days) }
    return days == 0 ? .today : .upcoming(days: days)
}

private func isTask(_ ticket: Ticket) -> Bool {
    if case .zentaoTask? = ticket.providerEntity { return true }
    return (ticket.externalType ?? "").lowercased() == "task"
}

/// Narrows tickets by a leader's filter. `names` maps a login to the name the person goes by, so a keyword finds a
/// ticket by who holds it however they are written.
public struct ApplyLeaderFilter: Sendable {
    public init() {}

    public func callAsFunction(_ tickets: [Ticket], _ filter: ZenTaoLeaderFilter, names: [String: String] = [:],
                               now: Date = Date(), calendar: Calendar = .current) -> [Ticket] {
        guard filter.isActive else { return tickets }
        let keyword = filter.trimmedKeyword.lowercased()
        return tickets.filter { t in
            if !filter.people.isEmpty, !filter.people.contains(t.assignee ?? "") { return false }
            if !keyword.isEmpty {
                let holder = t.assignee ?? ""
                let hay = [t.title, t.externalKey, "#" + t.externalKey, holder, names[holder] ?? ""].joined(separator: " ").lowercased()
                if !hay.contains(keyword) { return false }
            }
            return Self.matchesQuick(t, filter.quick, now: now, calendar: calendar)
        }
    }

    static func matchesQuick(_ t: Ticket, _ chips: Set<ZenTaoQuickFilter>, now: Date, calendar: Calendar) -> Bool {
        if chips.isEmpty { return true }
        let time = chips.filter(\.isAboutTime)
        if !time.isEmpty, !time.contains(where: { matches(t, $0, now: now, calendar: calendar) }) { return false }
        return chips.filter { !$0.isAboutTime }.allSatisfy { matches(t, $0, now: now, calendar: calendar) }
    }

    public static func matches(_ t: Ticket, _ chip: ZenTaoQuickFilter, now: Date = Date(), calendar: Calendar = .current) -> Bool {
        switch chip {
        case .overdue:
            if case .overdue = zentaoDeadlineState(t, now: now, calendar: calendar) { return true }
            return false
        case .dueSoon:
            switch zentaoDeadlineState(t, now: now, calendar: calendar) {
            case .today: return true
            case .upcoming(let days): return days <= ZenTaoLeaderFilter.soonDays
            default: return false
            }
        case .dueThisWeek:
            guard zentaoIsOpen(t), let d = extractZenTaoDeadline(t) else { return false }
            return IsDueThisWeek()(d, now: now)
        case .noDeadline:
            return zentaoDeadlineState(t, now: now, calendar: calendar) == .none
        case .unassigned:
            return zentaoIsOpen(t) && (t.assignee ?? "").isEmpty
        case .highPriority:
            return zentaoIsOpen(t) && t.priority.level <= Priority.high.level
        case .stale:
            guard zentaoIsOpen(t), let updated = t.updatedAt else { return false }
            let days = calendar.dateComponents([.day], from: calendar.startOfDay(for: updated), to: calendar.startOfDay(for: now)).day ?? 0
            return days >= ZenTaoLeaderFilter.staleDays
        case .noEstimate:
            guard zentaoIsOpen(t), case .zentaoTask(let task)? = t.providerEntity else { return false }
            return (task.estimate ?? 0) <= 0
        }
    }
}

/// How many of `tickets` each chip would keep: what the leader sees on the chip before clicking it.
public struct CountQuickFilters: Sendable {
    public init() {}
    public func callAsFunction(_ tickets: [Ticket], now: Date = Date(), calendar: Calendar = .current) -> [ZenTaoQuickFilter: Int] {
        var out: [ZenTaoQuickFilter: Int] = [:]
        for chip in ZenTaoQuickFilter.allCases {
            out[chip] = tickets.reduce(0) { $0 + (ApplyLeaderFilter.matches($1, chip, now: now, calendar: calendar) ? 1 : 0) }
        }
        return out
    }
}

/// One person's load: what they hold that is still open.
public struct ZenTaoWorkload: Equatable, Sendable, Identifiable {
    /// The login; empty for the work nobody holds.
    public var login: String
    public var open = 0
    public var overdue = 0
    public var dueSoon = 0
    public var highPriority = 0
    /// Hours still to do on the open tasks that say so.
    public var hoursLeft = 0.0
    public var id: String { login }
    public var isUnassigned: Bool { login.isEmpty }
    public init(login: String) { self.login = login }
}

/// The load of each person in `tickets`, the busiest (most overdue, then most open) first and the unassigned row last.
/// `roster` lists people to show even when they hold nothing (the members of the execution).
public struct SummarizeWorkload: Sendable {
    public init() {}

    public func callAsFunction(_ tickets: [Ticket], roster: [String] = [], now: Date = Date(), calendar: Calendar = .current) -> [ZenTaoWorkload] {
        var rows: [String: ZenTaoWorkload] = [:]
        for login in roster where !login.isEmpty { rows[login] = ZenTaoWorkload(login: login) }
        for t in tickets where zentaoIsOpen(t) {
            let login = t.assignee ?? ""
            var row = rows[login] ?? ZenTaoWorkload(login: login)
            row.open += 1
            if ApplyLeaderFilter.matches(t, .overdue, now: now, calendar: calendar) { row.overdue += 1 }
            if ApplyLeaderFilter.matches(t, .dueSoon, now: now, calendar: calendar) { row.dueSoon += 1 }
            if t.priority.level <= Priority.high.level { row.highPriority += 1 }
            if isTask(t), case .zentaoTask(let task)? = t.providerEntity { row.hoursLeft += task.left ?? 0 }
            rows[login] = row
        }
        return rows.values.sorted { a, b in
            if a.isUnassigned != b.isUnassigned { return !a.isUnassigned }
            if a.overdue != b.overdue { return a.overdue > b.overdue }
            if a.open != b.open { return a.open > b.open }
            return a.login < b.login
        }
    }
}
