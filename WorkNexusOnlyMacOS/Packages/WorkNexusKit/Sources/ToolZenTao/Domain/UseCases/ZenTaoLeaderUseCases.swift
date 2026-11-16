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
        chips.isEmpty || ZenTaoLeaderFacts(t, now: now, calendar: calendar).matches(all: chips)
    }

    public static func matches(_ t: Ticket, _ chip: ZenTaoQuickFilter, now: Date = Date(), calendar: Calendar = .current) -> Bool {
        ZenTaoLeaderFacts(t, now: now, calendar: calendar).matches(chip)
    }
}

/// What the leader's chips ask of one ticket, worked out once: its deadline is parsed a single time however many chips,
/// counts and workload rows then read it.
public struct ZenTaoLeaderFacts: Sendable {
    public let open: Bool
    public let deadline: ZenTaoDeadlineState
    public let dueThisWeek: Bool
    public let unassigned: Bool
    public let highPriority: Bool
    public let stale: Bool
    public let noEstimate: Bool
    public let hoursLeft: Double

    public init(_ t: Ticket, now: Date = Date(), calendar: Calendar = .current) {
        let open = zentaoIsOpen(t)
        self.open = open
        let due = open ? extractZenTaoDeadline(t) : nil
        if !open { deadline = .finished }
        else if let due {
            let days = calendar.dateComponents([.day], from: calendar.startOfDay(for: now), to: calendar.startOfDay(for: due)).day ?? 0
            deadline = days < 0 ? .overdue(days: -days) : (days == 0 ? .today : .upcoming(days: days))
        } else { deadline = .none }
        dueThisWeek = due.map { IsDueThisWeek()($0, now: now) } ?? false
        unassigned = open && (t.assignee ?? "").isEmpty
        highPriority = open && t.priority.level <= Priority.high.level
        if open, let updated = t.updatedAt {
            let idle = calendar.dateComponents([.day], from: calendar.startOfDay(for: updated), to: calendar.startOfDay(for: now)).day ?? 0
            stale = idle >= ZenTaoLeaderFilter.staleDays
        } else { stale = false }
        if case .zentaoTask(let task)? = t.providerEntity {
            noEstimate = open && (task.estimate ?? 0) <= 0
            hoursLeft = open ? (task.left ?? 0) : 0
        } else { noEstimate = false; hoursLeft = 0 }
    }

    public func matches(_ chip: ZenTaoQuickFilter) -> Bool {
        switch chip {
        case .overdue: deadline.isOverdue
        case .dueSoon:
            switch deadline {
            case .today: true
            case .upcoming(let days): days <= ZenTaoLeaderFilter.soonDays
            default: false
            }
        case .dueThisWeek: dueThisWeek
        case .noDeadline: deadline == .none
        case .unassigned: unassigned
        case .highPriority: highPriority
        case .stale: stale
        case .noEstimate: noEstimate
        }
    }

    /// The chips about time are alternatives to each other; every other chip narrows further.
    public func matches(all chips: Set<ZenTaoQuickFilter>) -> Bool {
        var anyTime = false, timeHit = false
        for chip in chips {
            if chip.isAboutTime { anyTime = true; if !timeHit && matches(chip) { timeHit = true } }
            else if !matches(chip) { return false }
        }
        return !anyTime || timeHit
    }
}

/// How many of `tickets` each chip would keep: what the leader sees on the chip before clicking it.
public struct CountQuickFilters: Sendable {
    public init() {}
    public func callAsFunction(_ tickets: [Ticket], now: Date = Date(), calendar: Calendar = .current) -> [ZenTaoQuickFilter: Int] {
        var out = Dictionary(uniqueKeysWithValues: ZenTaoQuickFilter.allCases.map { ($0, 0) })
        for t in tickets {
            let facts = ZenTaoLeaderFacts(t, now: now, calendar: calendar)
            for chip in ZenTaoQuickFilter.allCases where facts.matches(chip) { out[chip, default: 0] += 1 }
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
        for t in tickets {
            let facts = ZenTaoLeaderFacts(t, now: now, calendar: calendar)
            guard facts.open else { continue }
            let login = t.assignee ?? ""
            var row = rows[login] ?? ZenTaoWorkload(login: login)
            row.open += 1
            if facts.matches(.overdue) { row.overdue += 1 }
            if facts.matches(.dueSoon) { row.dueSoon += 1 }
            if facts.highPriority { row.highPriority += 1 }
            row.hoursLeft += facts.hoursLeft
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
