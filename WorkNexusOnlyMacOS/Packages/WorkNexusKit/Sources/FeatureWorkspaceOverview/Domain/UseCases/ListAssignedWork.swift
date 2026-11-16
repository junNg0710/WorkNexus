import CoreDomain
import Foundation

/// Ported from: lib/features/workspace_overview/domain/usecases/list_assigned_work.dart
/// Pure use case: (tickets, accounts of the active workspace, now) -> sorted open items.
/// - Assigned: ticket.assignee equals the owning account's handle (case-insensitive).
/// - Reviewer: handle is one of the PR/MR reviewers.
/// - Open: status not done and raw status not in the finished set (a merged GitHub PR is finished too).
/// - Sort: overdue first, then due ascending, then most recently updated.
public struct ListAssignedWork: Sendable {
    public init() {}

    private static let finishedStatuses: Set<String> = ["done", "closed", "cancel", "resolved", "merged"]

    public static func isOpen(_ t: Ticket) -> Bool {
        if t.status == .done { return false }
        if finishedStatuses.contains(t.providerStatus.trimmingCharacters(in: .whitespaces).lowercased()) { return false }
        if case .githubItem(let gh)? = t.providerEntity, gh.merged == true { return false }
        return true
    }

    public static func formatDisplayKey(_ t: Ticket) -> String {
        let key = t.externalKey
        let type = t.externalType?.trimmingCharacters(in: .whitespaces).lowercased()
        switch t.providerType {
        case .zentao:
            switch type { case "bug": return "BUG-\(key)"; case "task": return "TASK-\(key)"; case "story": return "STORY-\(key)"; default: return key }
        case .gitlab: return type == "mergerequest" ? "!\(key)" : "#\(key)"
        case .github: return "#\(key)"
        case .jira: return key
        }
    }

    public static func extractDue(_ t: Ticket) -> Date? {
        if case .zentaoBug(let bug)? = t.providerEntity, let deadline = bug.deadline, let due = parseDue(deadline) { return due }
        for l in t.labels {
            let raw: String? = l.hasPrefix("deadline:") ? String(l.dropFirst(9)) : l.hasPrefix("due:") ? String(l.dropFirst(4)) : nil
            if let raw, let due = parseDue(raw) { return due }
        }
        return nil
    }

    /// `raw` as a due moment, or nil for none. ZenTao writes "no deadline" as `0000-00-00` (a date in year 0, always
    /// overdue), so it is dropped. A bare date is due by the end of that day, not at its first second.
    static func parseDue(_ raw: String, calendar: Calendar = .current) -> Date? {
        let text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let parsed = DueDateParser.parse(text, calendar: calendar), calendar.component(.year, from: parsed) >= 1 else { return nil }
        if text.contains(":") { return parsed }
        let day = calendar.startOfDay(for: parsed)
        return calendar.date(byAdding: .day, value: 1, to: day).map { $0.addingTimeInterval(-1) }
    }

    public func callAsFunction(tickets: [Ticket], accounts: [Account], now: Date = Date()) -> [AssignedWorkItem] {
        let byId = Dictionary(accounts.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        var items: [AssignedWorkItem] = []
        for ticket in tickets {
            guard Self.isOpen(ticket), let account = byId[ticket.accountId] else { continue }
            let handle = account.handle.trimmingCharacters(in: .whitespaces).lowercased()
            if handle.isEmpty { continue }
            let isAssignee = ticket.assignee?.trimmingCharacters(in: .whitespaces).lowercased() == handle
            let isReviewer: Bool
            switch ticket.providerEntity {
            // Logins, as the account knows its user; items stored before they were kept only have display names.
            case .githubItem(let gh)?:
                isReviewer = (gh.reviewerLogins.isEmpty ? gh.reviewers : gh.reviewerLogins).contains { $0.trimmingCharacters(in: .whitespaces).lowercased() == handle }
            case .gitlabItem(let gl)?:
                isReviewer = gl.reviewers.contains { $0.trimmingCharacters(in: .whitespaces).lowercased() == handle }
            default: isReviewer = false
            }
            guard isAssignee || isReviewer else { continue }
            items.append(AssignedWorkItem(
                ticketId: ticket.id, provider: ticket.providerType, displayKey: Self.formatDisplayKey(ticket), title: ticket.title,
                status: ticket.status, statusLabel: ticket.providerStatus, reason: isAssignee ? .assignee : .reviewer,
                due: Self.extractDue(ticket), updatedAt: ticket.updatedAt))
        }
        return items.sorted { Self.compare($0, $1, now) < 0 }
    }

    private static func compare(_ a: AssignedWorkItem, _ b: AssignedWorkItem, _ now: Date) -> Int {
        let aOverdue = a.due.map { $0 < now } ?? false, bOverdue = b.due.map { $0 < now } ?? false
        if aOverdue != bOverdue { return aOverdue ? -1 : 1 }
        if let ad = a.due, let bd = b.due {
            if ad != bd { return ad < bd ? -1 : 1 }
            return compareUpdated(a, b)
        }
        if a.due != nil { return -1 }
        if b.due != nil { return 1 }
        return compareUpdated(a, b)
    }

    private static func compareUpdated(_ a: AssignedWorkItem, _ b: AssignedWorkItem) -> Int {
        if let au = a.updatedAt, let bu = b.updatedAt {
            if au != bu { return bu < au ? -1 : 1 }
        } else if a.updatedAt != nil { return -1 }
        else if b.updatedAt != nil { return 1 }
        return a.ticketId == b.ticketId ? 0 : (a.ticketId < b.ticketId ? -1 : 1)
    }
}

/// `DateTime.tryParse` for the shapes ZenTao and the labels use: `2026-10-12`, `2026-10-12 08:30:00`,
/// `2026-10-12T08:30:00`, optionally with fractional seconds / a zone designator.
enum DueDateParser {
    static func parse(_ text: String, calendar: Calendar) -> Date? {
        guard text.range(of: #"^\d{4}-\d{2}-\d{2}"#, options: .regularExpression) != nil else { return nil }
        let iso = ISO8601DateFormatter()
        for options: ISO8601DateFormatter.Options in [[.withInternetDateTime], [.withInternetDateTime, .withFractionalSeconds]] {
            iso.formatOptions = options
            if let d = iso.date(from: text.replacingOccurrences(of: " ", with: "T")) { return d }
        }
        for pattern in ["yyyy-MM-dd'T'HH:mm:ss", "yyyy-MM-dd HH:mm:ss", "yyyy-MM-dd'T'HH:mm", "yyyy-MM-dd HH:mm", "yyyy-MM-dd"] {
            let f = DateFormatter()
            f.calendar = calendar; f.timeZone = calendar.timeZone; f.locale = Locale(identifier: "en_US_POSIX")
            f.isLenient = false; f.dateFormat = pattern
            if let d = f.date(from: text) { return d }
        }
        return nil
    }
}
