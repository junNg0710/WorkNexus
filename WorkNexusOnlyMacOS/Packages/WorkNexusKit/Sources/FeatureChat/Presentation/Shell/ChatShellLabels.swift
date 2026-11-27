import CoreDomain
import CoreUI
import Foundation

/// A localized string with its placeholders filled in. The catalog holds `%1$@`-style positionals (numbered in the
/// order the placeholders appear in the English text, which `fallback` mirrors); `{name}` is filled too, for fallbacks.
func shellString(_ key: String, _ fallback: String, _ vars: [String: String] = [:]) -> String {
    var s = appString(key, fallback)
    var order: [String] = []
    var rest = Substring(fallback)
    while let open = rest.firstIndex(of: "{"), let close = rest[open...].firstIndex(of: "}") {
        let name = String(rest[rest.index(after: open)..<close])
        if vars[name] != nil, !order.contains(name) { order.append(name) }
        rest = rest[rest.index(after: close)...]
    }
    order += vars.keys.filter { !order.contains($0) }.sorted()
    for (i, name) in order.enumerated() { s = s.replacingOccurrences(of: "%\(i + 1)$@", with: vars[name] ?? "") }
    for (k, v) in vars { s = s.replacingOccurrences(of: "{\(k)}", with: v) }
    return s
}

/// A chat's avatar as drawn: a picture, a text on a colour (groups that set one) or a glyph (My Cloud); nil fields fall
/// back to the title's initials.
struct ChatAvatarStyle: Equatable {
    var imageUrl: String?
    var label: String?
    /// `0xRRGGBB`.
    var background: UInt32?
    var systemIcon: String?
}

/// Text helpers for the shell: titles, names, previews, times. Pure, so they are unit-tested.
/// Ported from: lib/features/chat/presentation/widgets/chat_labels.dart
enum ChatShellLabels {
    // MARK: names

    /// A conversation's title, with a localized fallback.
    static func title(_ chat: ChatConversation, _ users: [Int: ChatUser]) -> String {
        if chat.isMyCloud { return shellString("chatMyCloud", "My Cloud") }
        if let resolved = ResolveChatTitle()(chat, users) { return resolved }
        if let peer = chat.peerUserId { return shellString("chatUnknownUser", "User #{id}", ["id": "\(peer)"]) }
        return shellString("chatUntitled", "Untitled chat")
    }

    /// A user's display name, with a localized fallback (xxd's bot is user 0).
    static func userName(_ users: [Int: ChatUser], _ id: Int) -> String {
        if id == 0 { return shellString("chatBotName", "Xuanbot") }
        guard let u = users[id] else { return shellString("chatUnknownUser", "User #{id}", ["id": "\(id)"]) }
        return u.realname.isEmpty ? u.account : u.realname
    }

    /// Up to two initials for an avatar.
    static func initials(_ name: String) -> String {
        let words = name.split(whereSeparator: { $0.isWhitespace || $0 == "_" || $0 == "-" })
        let letters = words.prefix(2).compactMap { $0.first.map { String($0).uppercased() } }.joined()
        return letters.isEmpty ? "?" : letters
    }

    static func avatarUrl(_ users: [Int: ChatUser], _ id: Int?) -> String? { id.flatMap { users[$0]?.avatarUrl } }

    static func presence(_ users: [Int: ChatUser], _ id: Int?) -> ChatPresence? {
        guard let id, let status = users[id]?.status else { return nil }
        return ChatPresence.from(status: status)
    }

    static func presenceLabel(_ p: ChatPresence) -> String {
        switch p {
        case .online: shellString("chatOnline", "Online")
        case .away: shellString("chatAway", "Away")
        case .busy: shellString("chatBusy", "Busy")
        case .meeting: shellString("chatInMeeting", "In meeting")
        case .offline: shellString("chatOffline", "Offline")
        }
    }

    /// The chat's avatar: My Cloud a glyph, a direct chat the peer's picture, a group its own avatar.
    static func avatarStyle(_ chat: ChatConversation, _ users: [Int: ChatUser]) -> ChatAvatarStyle {
        if chat.isMyCloud { return ChatAvatarStyle(systemIcon: "icloud") }
        if chat.type == .one2one { return ChatAvatarStyle(imageUrl: avatarUrl(users, chat.peerUserId)) }
        switch ChatGroupAvatar.from(json: chat.avatarJson) {
        case .image(let url): return ChatAvatarStyle(imageUrl: url)
        case .text(let text, let color): return ChatAvatarStyle(label: text, background: hexColor(color))
        case nil: return ChatAvatarStyle()
        }
    }

    /// `#RRGGBB` from the server as `0xRRGGBB`; nil unless it is exactly six hex digits.
    static func hexColor(_ hex: String) -> UInt32? {
        let digits = hex.hasPrefix("#") ? String(hex.dropFirst()) : hex
        return digits.count == 6 ? UInt32(digits, radix: 16) : nil
    }

    // MARK: roles

    private static let extraRoleNames: [String: (String, String)] = [
        "ui": ("chatRoleUi", "Designer"), "designer": ("chatRoleUi", "Designer"), "ux": ("chatRoleUx", "UX Designer"),
        "op": ("chatRoleOp", "Operations"), "ops": ("chatRoleOp", "Operations"), "opm": ("chatRoleOpm", "Operations Manager"),
        "ba": ("chatRoleBa", "Business Analyst"), "devops": ("chatRoleDevops", "DevOps Engineer"),
    ]

    /// A ZenTao role's name: ours for default and common codes, else the server's (`serverNames`), else the code.
    static func roleLabel(_ code: String, serverNames: [String: String] = [:]) -> String {
        let key = code.trimmingCharacters(in: .whitespaces)
        switch ChatRole.from(code: key) {
        case .dev: return shellString("chatRoleDev", "Developer")
        case .qa: return shellString("chatRoleQa", "Test Engineer")
        case .pm: return shellString("chatRolePm", "Project Manager")
        case .po: return shellString("chatRolePo", "Product Owner")
        case .td: return shellString("chatRoleTd", "Technical Manager")
        case .pd: return shellString("chatRolePd", "Product Manager")
        case .qd: return shellString("chatRoleQd", "Test Manager")
        case .top: return shellString("chatRoleTop", "Senior Manager")
        case .others: return shellString("chatRoleOthers", "Others")
        case nil:
            if let (k, f) = extraRoleNames[key.lowercased()] { return shellString(k, f) }
            return serverNames[key] ?? code
        }
    }

    /// Whether a user with `role` shows under the role tab `filter` (nil: all).
    static func roleMatches(_ filter: String?, _ role: String?) -> Bool {
        filter == nil || (role?.trimmingCharacters(in: .whitespaces) ?? "") == filter
    }

    // MARK: previews and times

    /// One-line preview of a message for the chat list. With `reactions` on, an emoji reply reads "Reacted 👍".
    static func preview(_ m: ChatMessage, reactions: Bool = false) -> String {
        if m.deleted { return shellString("chatRetracted", "Message retracted") }
        if reactions, let emoji = m.reactionEmoji { return shellString("chatReacted", "Reacted {emoji}", ["emoji": emoji]) }
        switch m.content {
        case .text(let text, let markdown): return cachedLine(text, markdown: markdown)
        case .emoji(let e): return e
        case .notification(let n): return oneLine(n.title ?? stripMarkdown(n.text))
        // A sticker is not a photo: the row says which of the two was sent.
        case .image(let i): return IsStickerImage()(i) ? shellString("chatSticker", "Sticker") : shellString("chatImage", "Image")
        case .file(let f): return "\(shellString("chatFile", "File")): \(f.name)"
        case .link(let url, let title): return title ?? url
        case .code(let code, _, let name):
            let first = code.trimmingCharacters(in: .whitespacesAndNewlines).split(separator: "\n").first.map(String.init) ?? ""
            return "\(shellString("chatCode", "Code")): \(name ?? first.trimmingCharacters(in: .whitespaces))"
        case .unsupported(let type): return shellString("chatUnsupportedMessage", "Unsupported message ({type})", ["type": type])
        }
    }

    /// Every chat row in the list asks for its preview on each redraw; the regex passes are kept per text.
    nonisolated(unsafe) private static let lineCache: NSCache<NSString, NSString> = { let c = NSCache<NSString, NSString>(); c.countLimit = 1000; return c }()

    private static func cachedLine(_ text: String, markdown: Bool) -> String {
        let key = "\(markdown ? 1 : 0)\(text)" as NSString
        if let hit = lineCache.object(forKey: key) { return hit as String }
        let line = oneLine(markdown ? stripMarkdown(text) : text)
        lineCache.setObject(line as NSString, forKey: key)
        return line
    }

    private static func oneLine(_ s: String) -> String {
        s.replacingOccurrences(of: #"\[@([^\]]+)\]\(@#\d+\)"#, with: "@$1", options: .regularExpression)
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Markdown reduced to its words (mention links stay for `oneLine`).
    static func stripMarkdown(_ text: String) -> String {
        text.replacingOccurrences(of: #"(?s)```.*?```"#, with: " ", options: .regularExpression)
            .replacingOccurrences(of: #"(?m)^\s{0,3}(#{1,6}|[-*+]|\d+\.|>)\s+"#, with: "", options: .regularExpression)
            .replacingOccurrences(of: #"\[([^\]@][^\]]*)\]\((?!@#)[^)]*\)"#, with: "$1", options: .regularExpression)
            .replacingOccurrences(of: #"(\*\*|__|\*|~~|`)"#, with: "", options: .regularExpression)
    }

    /// Compact time for the chat list: 10:05 today, "Yesterday", a weekday within the week, else a short date.
    static func listTime(_ t: Date?, now: Date = Date(), calendar: Calendar = .current, locale: Locale = .current) -> String {
        guard let t else { return "" }
        let age = calendar.dateComponents([.day], from: calendar.startOfDay(for: t), to: calendar.startOfDay(for: now)).day ?? 0
        func format(_ pattern: String) -> String {
            CachedDateFormatter.string(t, format: pattern, locale: locale, timeZone: calendar.timeZone, calendar: calendar)
        }
        if age == 0 { return format("HH:mm") }
        if age == 1 { return shellString("chatYesterday", "Yesterday") }
        if age > 1 && age < 7 { return format("EEE") }
        return calendar.component(.year, from: t) == calendar.component(.year, from: now) ? format("dd/MM") : format("dd/MM/yy")
    }

    /// "An is typing…", "An and Bình are typing…", "An and 3 others are typing…".
    static func typingLabel(_ users: [Int: ChatUser], _ typing: [Int]) -> String {
        func name(_ id: Int) -> String { userName(users, id) }
        switch typing.count {
        case 0: return ""
        case 1: return shellString("chatTypingOne", "{name} is typing…", ["name": name(typing[0])])
        case 2: return shellString("chatTypingTwo", "{first} and {second} are typing…", ["first": name(typing[0]), "second": name(typing[1])])
        default: return shellString("chatTypingMany", "{name} and {count} others are typing…", ["name": name(typing[0]), "count": "\(typing.count - 1)"])
        }
    }

    static func memberCount(_ n: Int) -> String {
        shellString("chatMembers", n == 1 ? "1 member" : "{count} members", ["count": "\(n)"])
    }

    // MARK: sizes, files

    /// Human-readable byte size.
    static func fileSize(_ bytes: Int) -> String {
        if bytes >= 1 << 30 {
            let gb = Double(bytes) / Double(1 << 30)
            return (gb == gb.rounded() ? String(format: "%.0f", gb) : String(format: "%.1f", gb)) + " GB"
        }
        if bytes >= 1 << 20 { return String(format: "%.1f MB", Double(bytes) / Double(1 << 20)) }
        if bytes >= 1 << 10 { return String(format: "%.0f KB", Double(bytes) / 1024) }
        return "\(bytes) B"
    }

    /// Upper-case extension for a file badge (max 4 characters).
    static func fileBadge(_ name: String) -> String {
        guard let dot = name.lastIndex(of: "."), name.index(after: dot) != name.endIndex else { return "FILE" }
        return String(name[name.index(after: dot)...].uppercased().prefix(4))
    }

    /// Splits a chat's attachment messages into media (images, videos) and other files. Stickers are in neither: they
    /// are reactions, not photos (`stickerNames`: the stickers this Mac knows, for `IsStickerImage`).
    static func splitAttachments(_ messages: [ChatMessage], stickerNames: Set<String> = []) -> (media: [ChatMessage], files: [ChatMessage]) {
        var media: [ChatMessage] = [], files: [ChatMessage] = []
        let isSticker = IsStickerImage()
        for m in messages {
            switch m.content {
            case .image(let i): if !isSticker(i, knownNames: stickerNames) { media.append(m) }
            case .file(let f) where f.fileId > 0: if isVideoFile(f) { media.append(m) } else { files.append(m) }
            default: break
            }
        }
        return (media, files)
    }

    // MARK: certificate

    /// `fingerprint` (`AB:CD:…`) broken into lines of `perLine` bytes.
    static func fingerprintLines(_ fingerprint: String, perLine: Int = 8) -> String {
        let bytes = fingerprint.split(separator: ":", omittingEmptySubsequences: false)
        return stride(from: 0, to: bytes.count, by: perLine)
            .map { bytes[$0..<min($0 + perLine, bytes.count)].joined(separator: ":") }.joined(separator: "\n")
    }

    /// The common name in a distinguished name (`/C=VN/CN=host` or `CN=host, O=…`), else the whole name.
    static func certificateName(_ dn: String) -> String {
        guard let r = dn.range(of: #"CN=([^/,]+)"#, options: .regularExpression) else { return dn }
        return String(dn[r].dropFirst(3)).trimmingCharacters(in: .whitespaces)
    }

    static func searchPeriodLabel(_ p: ChatSearchPeriod) -> String {
        switch p {
        case .all: shellString("chatSearchPeriodAll", "Any time")
        case .week: shellString("chatSearchPeriodWeek", "Past 7 days")
        case .month: shellString("chatSearchPeriodMonth", "Past 30 days")
        case .quarter: shellString("chatSearchPeriodQuarter", "Past 3 months")
        case .year: shellString("chatSearchPeriodYear", "Past year")
        }
    }

    static func failureText(_ f: Failure) -> String {
        if case .expired = f { return shellString("chatReactionRemoveExpired", "A reaction can only be taken back within 2 minutes") }
        return shellString("chatActionFailed", "Couldn't complete that: {reason}", ["reason": f.message])
    }
}
