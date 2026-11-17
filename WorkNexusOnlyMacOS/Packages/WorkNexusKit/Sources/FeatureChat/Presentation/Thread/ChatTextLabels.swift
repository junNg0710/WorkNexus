/// Ported from: lib/features/chat/presentation/widgets/chat_text_labels.dart + chat_labels.dart
import CoreDomain
import CoreUI
import Foundation

/// A piece of plain message text: words, a `[@Name](@#id)` mention, or a web address.
enum ChatTextToken: Hashable {
    case text(String)
    case mention(name: String, userId: Int)
    case url(String)
}

/// Text helpers for chat: mentions, web addresses, Markdown detection and one-line previews.
enum ChatTextLabels {
    private static let urlPattern =
        #"https?://(?:\[[^\s<>()\[\]]*\]|[^\s<>()\[\]])*(?:\[[^\s<>()\[\]]*\]|[^\s<>()\[\].,;:!?'"])"#
    private static let token = RX(#"\[@([^\]]+)\]\(@#(\d+)\)|"# + urlPattern)
    private static let url = RX(urlPattern)
    private static let mentionLink = RX(#"^@#(\d+)$"#)
    private static let mentionPattern = RX(#"\[@([^\]]+)\]\(@#(\d+)\)"#)
    private static let whitespace = RX(#"\s+"#)
    private static let markdownEscape = RX(#"\\([\\`*_{}\[\]()#+\-.!])"#)
    private static let codeFence = RX(#"```[\s\S]*?```"#)
    private static let lineMarker = RX(#"(?m)^\s{0,3}(#{1,6}|[-*+]|\d+\.|>)\s+"#)
    private static let plainLink = RX(#"\[([^\]@][^\]]*)\]\((?!@#)[^)]*\)"#)
    private static let emphasis = RX(#"(\*\*|__|\*|~~|`)"#)
    private static let markdownSignal = RX(
        #"(?m)^\s{0,3}(#{1,6}\s|[-*+]\s+\S|\d+\.\s+\S|>\s|```|\|.*\|)|\*\*[^*\n]+\*\*|__[^_\n]+__|`[^`\n]+`|~~[^~\n]+~~|\[[^\]@][^\]]*\]\(https?://"#)

    /// The user id of a mention link target (`@#24`), else nil.
    static func mentionUserId(_ url: String) -> Int? {
        mentionLink.first(url.trimmingCharacters(in: .whitespacesAndNewlines)).flatMap { $0[1] }.flatMap(Int.init)
    }

    /// Plain text split into words, mentions and web addresses. Adjacent tokens get a space between them.
    static func tokens(_ text: String) -> [ChatTextToken] {
        let ns = text as NSString
        var out: [ChatTextToken] = []
        var at = 0
        for m in token.matches(text) {
            if m.start > at { out.append(.text(ns.substring(with: NSRange(location: at, length: m.start - at)))) }
            else if !out.isEmpty { out.append(.text(" ")) }
            if let name = m[1], let id = m[2].flatMap(Int.init) { out.append(.mention(name: name, userId: id)) }
            else { out.append(.url(m.whole)) }
            at = m.end
        }
        if at < ns.length { out.append(.text(ns.substring(from: at))) }
        return out
    }

    /// First web address in a text, for a link preview.
    static func firstUrl(_ text: String) -> String? { url.first(text)?.whole }

    /// Every web address in `text`, in order, without repeats: one written twice (as plain text and as a Markdown link,
    /// say) is one address, also when only a trailing slash or a `#fragment` tells the two apart.
    static func urls(_ text: String) -> [String] {
        var seen = Set<String>()
        return url.matches(text).map(\.whole).filter { seen.insert(sameAddress($0)).inserted }
    }

    private static func sameAddress(_ address: String) -> String {
        guard let c = URLComponents(string: address) else { return address }
        var path = c.percentEncodedPath
        if path.hasSuffix("/"), path.count > 1 { path.removeLast() }
        let host = c.host?.lowercased() ?? ""
        let port = c.port.map { ":\($0)" } ?? ""
        return "\(c.scheme ?? "")://\(host)\(port)\(path)\(c.percentEncodedQuery.map { "?\($0)" } ?? "")"
    }

    /// Whether plain text is evidently Markdown — people paste it into `plain` messages too — so it can be rendered formatted.
    static func looksLikeMarkdown(_ text: String) -> Bool { markdownSignal.hasMatch(text) }

    /// Many clients send everything as Markdown (`text`); a message without any of its syntax skips the far costlier renderer.
    static func rendersMarkdown(_ text: String, markdown: Bool) -> Bool { (markdown || looksLikeMarkdown(text)) && hasMarkdownSyntax(text) }

    /// Whether a message renders as code or formatted Markdown — content that reads better given more width than a chat line.
    static func showsWide(_ m: ChatMessage) -> Bool {
        if m.deleted { return false }
        switch m.content {
        case .code: return true
        case .text(let t, let md): return rendersMarkdown(t, markdown: md)
        default: return false
        }
    }

    /// Markdown reduced to its words for one-line previews (mention links are kept for the mention pattern).
    static func stripMarkdown(_ text: String) -> String {
        var t = codeFence.replace(text) { _ in " " }
        t = lineMarker.replace(t) { _ in "" }
        t = plainLink.replace(t) { $0[1] ?? "" }
        return emphasis.replace(t) { _ in "" }
    }

    private static func collapse(_ s: String) -> String { whitespace.replace(s) { _ in " " }.trimmingCharacters(in: .whitespaces) }
    private static func mentionsAsAt(_ s: String) -> String { mentionPattern.replace(s) { "@\($0[1] ?? "")" } }

    /// The text of a server notice with its mentions kept: the server writes it as Markdown (a chat name links to the chat, `_` comes escaped).
    static func noticeText(_ text: String, markdown: Bool) -> String {
        markdown ? markdownEscape.replace(stripMarkdown(text)) { $0[1] ?? "" } : text
    }

    /// Text copied from a message: its mentions as `@Name`.
    static func copyText(_ text: String) -> String { mentionsAsAt(text) }

    /// One-line preview of a message. With `reactions` on, an emoji reply previews as "Reacted 👍".
    static func preview(_ m: ChatMessage, reactions: Bool = false) -> String {
        // A retracted message keeps no content; say so rather than show nothing.
        if m.deleted { return L.retracted }
        if reactions, let e = m.reactionEmoji { return L.reacted(e) }
        switch m.content {
        case .text(let t, let md): return collapse(mentionsAsAt(md ? stripMarkdown(t) : t))
        case .emoji(let e): return e
        case .notification(let n): return collapse(n.title ?? stripMarkdown(n.text))
        case .image: return L.image
        case .file(let f): return "\(L.file): \(f.name)"
        case .link(let u, let title): return title ?? u
        case .code(let code, _, let name):
            return "\(L.code): \(name ?? code.trimmingCharacters(in: .whitespacesAndNewlines).components(separatedBy: "\n").first.map { $0.trimmingCharacters(in: .whitespaces) } ?? "")"
        case .unsupported(let type): return L.unsupported(type)
        }
    }

    /// A user's display name, with a localized fallback (xxd's bot, ZenTao notifications, is user 0).
    static func userName(_ users: [Int: ChatUser], _ id: Int) -> String {
        if id == 0 { return L.botName }
        guard let u = users[id] else { return L.unknownUser(id) }
        return u.realname.isEmpty ? u.account : u.realname
    }

    /// The host of a URL, for link cards.
    static func linkHost(_ url: String) -> String { URL(string: url)?.host ?? url }

    /// Upper-case file extension for the file tile badge (max 4 chars).
    static func fileBadge(_ name: String) -> String {
        guard let dot = name.lastIndex(of: "."), name.index(after: dot) != name.endIndex else { return "FILE" }
        return String(name[name.index(after: dot)...].uppercased().prefix(4))
    }

    /// Day separator label: today / yesterday / a localized date.
    static func dayLabel(_ day: Date, now: Date = Date(), calendar: Calendar = .current) -> String {
        let today = calendar.startOfDay(for: now), d = calendar.startOfDay(for: day)
        if d == today { return L.today }
        if let y = calendar.date(byAdding: .day, value: -1, to: today), d == y { return L.yesterday }
        return CachedDateFormatter.string(d, template: calendar.component(.year, from: d) == calendar.component(.year, from: today) ? "MMMMd" : "yMMMMd")
    }

    /// `HH:mm`.
    static func clock(_ date: Date) -> String {
        CachedDateFormatter.string(date, format: "HH:mm")
    }

    /// Compact time for the chat list: 10:05 today, "Yesterday", a weekday within the week, else a short date.
    static func listTime(_ t: Date, now: Date = Date(), calendar: Calendar = .current) -> String {
        let today = calendar.startOfDay(for: now), day = calendar.startOfDay(for: t)
        let age = calendar.dateComponents([.day], from: day, to: today).day ?? 0
        if age == 0 { return clock(t) }
        if age == 1 { return L.yesterday }
        if age < 7 { return CachedDateFormatter.string(t, template: "E") }
        return CachedDateFormatter.string(t, format: calendar.component(.year, from: t) == calendar.component(.year, from: today) ? "dd/MM" : "dd/MM/yy",
                                          locale: .current)
    }

    /// Human-readable byte size.
    static func fileSize(_ bytes: Int) -> String {
        if bytes >= 1 << 30 {
            let gb = Double(bytes) / Double(1 << 30)
            return "\(gb == gb.rounded() ? String(format: "%.0f", gb) : String(format: "%.1f", gb)) GB"
        }
        if bytes >= 1 << 20 { return String(format: "%.1f MB", Double(bytes) / Double(1 << 20)) }
        if bytes >= 1 << 10 { return String(format: "%.0f KB", Double(bytes) / 1024) }
        return "\(bytes) B"
    }

    /// How long ago `t` was, compactly: "just now", "5m ago", "2h ago", "3d ago", then the date.
    static func ago(_ t: Date, now: Date = Date()) -> String {
        let secs = Int(now.timeIntervalSince(t))
        if secs < 60 { return L.justNow }
        if secs < 3600 { return L.minutesAgo(secs / 60) }
        if secs < 86400 { return L.hoursAgo(secs / 3600) }
        if secs < 30 * 86400 { return L.daysAgo(secs / 86400) }
        return CachedDateFormatter.string(t, template: "yMMMd")
    }
}
