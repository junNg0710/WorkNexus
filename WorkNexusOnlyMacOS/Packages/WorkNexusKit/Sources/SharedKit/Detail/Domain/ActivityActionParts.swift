import CoreDomain
import Foundation

/// Ported from: lib/shared/detail/presentation/util/activity_action_parts.dart (+ `activityKindOf`)
/// Pure text logic for the activity timeline, kept in Domain so it is testable without UI.
public enum ActivityPartKind: Sendable { case plain, user, value }

public struct ActivityPart: Equatable, Sendable {
    public var text: String
    public var kind: ActivityPartKind
    public init(_ text: String, _ kind: ActivityPartKind) { self.text = text; self.kind = kind }
}

/// Splits an activity line into styled parts: `assigned to <user>`, `field: <value>`, or text with `@mentions`.
public func activityActionParts(_ action: String) -> [ActivityPart] {
    let ns = action as NSString
    let full = NSRange(location: 0, length: ns.length)
    if let m = try? NSRegularExpression(pattern: #"^(assigned to )(.+)$"#).firstMatch(in: action, range: full) {
        return [ActivityPart(ns.substring(with: m.range(at: 1)), .plain), ActivityPart(ns.substring(with: m.range(at: 2)), .user)]
    }
    // Lazy prefix up to the first ": " — the field name — then the value.
    if let m = try? NSRegularExpression(pattern: #"^(.*?: )(.+)$"#).firstMatch(in: action, range: full) {
        return [ActivityPart(ns.substring(with: m.range(at: 1)), .plain), ActivityPart(ns.substring(with: m.range(at: 2)), .value)]
    }
    return mentionParts(action)
}

private func mentionParts(_ action: String) -> [ActivityPart] {
    let ns = action as NSString
    var parts: [ActivityPart] = []
    var start = 0
    guard let re = try? NSRegularExpression(pattern: #"@[\w.-]*\w"#) else { return [ActivityPart(action, .plain)] }
    for m in re.matches(in: action, range: NSRange(location: 0, length: ns.length)) {
        if m.range.location > start { parts.append(ActivityPart(ns.substring(with: NSRange(location: start, length: m.range.location - start)), .plain)) }
        parts.append(ActivityPart(ns.substring(with: m.range), .user))
        start = m.range.location + m.range.length
    }
    if start < ns.length { parts.append(ActivityPart(ns.substring(from: start), .plain)) }
    return parts
}

public enum ActivityKind: Sendable { case created, assigned, edited, resolved, merged, reopened, confirmed, closed, other }

/// The kind of event from its leading verb (drives the timeline marker icon).
public func activityKindOf(_ action: String) -> ActivityKind {
    let verb = action.trimmingCharacters(in: .whitespaces).split(whereSeparator: { $0.isWhitespace || $0 == "·" || $0 == "(" }).first
        .map { $0.lowercased() } ?? ""
    switch verb {
    case "created", "opened": return .created
    case "assigned", "unassigned": return .assigned
    case "edited", "updated", "changed": return .edited
    case "resolved", "approved": return .resolved
    case "merged": return .merged
    case "activated", "reopened": return .reopened
    case "confirmed": return .confirmed
    case "closed": return .closed
    default: return .other
    }
}

/// `#12 Title` — what "Copy title" puts on the clipboard.
public func ticketTitleWithRef(_ t: Ticket) -> String { "\(ticketShortRefText(t.providerType, t.externalKey)) \(t.title)" }

func ticketShortRefText(_ p: ProviderType, _ key: String) -> String { p == .jira ? key : "#\(key)" }

/// File extensions the attachment viewer previews.
public enum AttachmentKinds {
    public static let image: Set<String> = ["png", "jpg", "jpeg", "gif", "webp", "bmp", "heic"]
    public static let video: Set<String> = ["mp4", "mov", "m4v", "webm"]
    /// Lower-cased extension of an attachment (its `extension`, else from the title).
    public static func ext(of a: TicketAttachment) -> String {
        if let e = a.extension, !e.isEmpty { return e.lowercased() }
        guard let dot = a.title.lastIndex(of: ".") else { return "" }
        return String(a.title[a.title.index(after: dot)...]).lowercased()
    }
}

/// Ported from: lib/core/domain/value_objects/repo_change.dart
public struct RepoCommit: Hashable, Sendable, Identifiable {
    public var sha: String
    public var shortSha: String
    public var title: String
    public var author: String?
    public var date: Date?
    public var id: String { sha }
    public init(sha: String, shortSha: String? = nil, title: String, author: String? = nil, date: Date? = nil) {
        self.sha = sha; self.shortSha = shortSha ?? String(sha.prefix(8)); self.title = title; self.author = author; self.date = date
    }
}

public struct RepoFileChange: Hashable, Sendable, Identifiable {
    public var path: String
    public var status: String?
    public var additions: Int
    public var deletions: Int
    public var diff: String?
    public var id: String { path }
    public init(path: String, status: String? = nil, additions: Int = 0, deletions: Int = 0, diff: String? = nil) {
        self.path = path; self.status = status; self.additions = additions; self.deletions = deletions; self.diff = diff
    }
}

/// Added / removed line counts of a unified diff (headers `+++` / `---` excluded).
public func countDiffLines(_ diff: String?) -> (additions: Int, deletions: Int) {
    guard let diff, !diff.isEmpty else { return (0, 0) }
    var adds = 0, dels = 0
    for line in diff.split(separator: "\n", omittingEmptySubsequences: false) {
        if line.hasPrefix("+") && !line.hasPrefix("+++") { adds += 1 }
        else if line.hasPrefix("-") && !line.hasPrefix("---") { dels += 1 }
    }
    return (adds, dels)
}
