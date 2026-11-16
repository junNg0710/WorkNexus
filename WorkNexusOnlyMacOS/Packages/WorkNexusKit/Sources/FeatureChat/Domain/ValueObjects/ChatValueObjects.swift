import Foundation

/// The square of a picture to keep as an avatar, in the picture's own pixels.
public struct ChatAvatarCrop: Hashable, Sendable {
    public var left: Double, top: Double, side: Double
    public init(left: Double, top: Double, side: Double) { self.left = left; self.top = top; self.side = side }
}

/// Connection state of one account's chat, as the UI needs it.
/// Ported from: lib/features/chat/domain/value_objects/chat_connection_status.dart
public enum ChatConnectionStatus: Hashable, Sendable {
    case offline
    case connecting
    case online(selfUserId: Int)
    /// Lost the connection; retrying automatically after `retryIn`.
    case reconnecting(retryIn: TimeInterval, reason: String)
    /// The server's certificate is self-signed or unknown; the user must confirm `fingerprint` first (TOFU).
    case needsTrust(host: String, fingerprint: String, subject: String, issuer: String)
    /// Stopped and not retrying: bad credentials, missing password, or `kicked` because the account signed in elsewhere.
    case signedOut(message: String, kicked: Bool = false)
}

/// How much of a chat's history is stored on this device while it downloads.
public struct ChatHistoryProgress: Hashable, Sendable {
    public var stored: Int
    public var total: Int
    public var complete: Bool
    public init(stored: Int, total: Int, complete: Bool = false) { self.stored = stored; self.total = total; self.complete = complete }
    /// 0–1; nil while the total is unknown.
    public var fraction: Double? { complete ? 1 : total > 0 ? min(1, max(0, Double(stored) / Double(total))) : nil }
}

/// The tabs above the chat list, each a slice of the conversations.
public enum ChatListTab: String, CaseIterable, Hashable, Sendable {
    case all, direct, groups, bots
    public func matches(_ chat: ChatConversation) -> Bool {
        switch self {
        case .all: true
        case .direct: chat.type == .one2one
        case .groups: chat.type == .group
        case .bots: chat.type == .bot || chat.type == .system
        }
    }
}

/// What kind of attachment a message carries, for storage breakdowns.
public enum ChatMediaKind: String, Hashable, Sendable { case image, video, file }

private let videoExtensions: Set<String> = ["mp4", "mov", "m4v", "webm", "mkv", "avi"]

/// Whether `name` has a video file's extension.
public func isVideoName(_ name: String) -> Bool {
    guard let dot = name.lastIndex(of: ".") else { return false }
    return videoExtensions.contains(name[name.index(after: dot)...].lowercased())
}

/// Whether a file message holds a video (by MIME type or extension).
public func isVideoFile(_ f: FileContent) -> Bool { (f.mimeType?.hasPrefix("video/") ?? false) || isVideoName(f.name) }

/// The kind of `content`'s attachment; nil when it has none.
public func chatMediaKind(of content: MessageContent) -> ChatMediaKind? {
    switch content {
    case .image: .image
    case .file(let f): isVideoFile(f) ? .video : .file
    default: nil
    }
}

/// Whether `message` is drawn bare — an image, a large emoji or a video — rather than inside a bubble. An own video still
/// uploading counts too, so it keeps one look from send to sent.
public func chatShowsAsMedia(_ m: ChatMessage) -> Bool {
    if m.deleted { return false }
    switch m.content {
    case .image, .emoji: return true
    case .file(let f): return isVideoFile(f) && (f.fileId > 0 || m.sendState != .sent)
    default: return false
    }
}

/// Whether a chat user is around, from xxd's user `status`.
public enum ChatPresence: String, Hashable, Sendable {
    case online, busy, meeting, away, offline
    public static func from(status: String?) -> ChatPresence {
        switch status { case "online": .online; case "busy": .busy; case "meeting": .meeting; case "away": .away; default: .offline }
    }
    /// The presences a user can pick for themselves, in menu order.
    public static let selectable: [ChatPresence] = [.busy, .meeting, .away, .online]
    public var status: String { rawValue }
    public var isAround: Bool { self != .offline }
}

/// A ZenTao user's role (`zt_user.role`). A role describes the job and orders user lists; it grants no rights.
public enum ChatRole: String, CaseIterable, Hashable, Sendable {
    case dev, qa, pm, po, td, pd, qd, top, others

    public static func from(code: String?) -> ChatRole? {
        guard let key = code?.trimmingCharacters(in: .whitespaces) else { return nil }
        return ChatRole(rawValue: key)
    }

    /// How senior the role is, for the "verified" check beside the avatar; nil for engineers and "others".
    public var rank: ChatRoleRank? {
        switch self {
        case .dev, .qa, .others: nil
        case .pm, .po: .lead
        case .td, .pd, .qd: .manager
        case .top: .executive
        }
    }
}

/// Seniority of a leading role, lowest first.
public enum ChatRoleRank: Int, Comparable, Hashable, Sendable {
    case lead, manager, executive
    public static func < (a: Self, b: Self) -> Bool { a.rawValue < b.rawValue }
}

/// Role codes admins often add beyond ZenTao's defaults, with their rank (nil: no "verified" check).
public let kExtraRoleRanks: [(code: String, rank: ChatRoleRank?)] = [
    ("opm", .manager), ("ui", nil), ("designer", nil), ("ux", nil), ("op", nil), ("ops", nil), ("ba", nil), ("devops", nil),
]

/// The rank of any role code — a default role or a common added one; nil for no check.
public func chatRoleRank(of code: String?) -> ChatRoleRank? {
    let key = code?.trimmingCharacters(in: .whitespaces).lowercased() ?? ""
    if let r = ChatRole.from(code: key)?.rank { return r }
    return kExtraRoleRanks.first { $0.code == key }?.rank
}

/// The role codes holding `rank`, defaults' order then the added ones.
public func chatRoleCodes(of rank: ChatRoleRank) -> [String] {
    ChatRole.allCases.filter { $0.rank == rank }.map(\.rawValue) + kExtraRoleRanks.filter { $0.rank == rank }.map(\.code)
}

/// How far back message search looks, counted back from now.
public enum ChatSearchPeriod: Hashable, Sendable, CaseIterable {
    case all, week, month, quarter, year
    public var span: TimeInterval? {
        switch self { case .all: nil; case .week: 7 * 86400; case .month: 30 * 86400; case .quarter: 90 * 86400; case .year: 365 * 86400 }
    }
    /// The oldest send time searched as of `now`; nil for `.all`.
    public func since(_ now: Date) -> Date? { span.map { now.addingTimeInterval(-$0) } }
}

/// How far back a chat's stored timeline — the run of history that reaches the newest message — goes.
public struct ChatTimelineExtent: Hashable, Sendable {
    public var count: Int
    public var oldestServerId: Int?
    public var oldestSentAt: Date?
    /// Whether it holds the chat's very first message.
    public var reachesStart: Bool
    public init(count: Int, oldestServerId: Int? = nil, oldestSentAt: Date? = nil, reachesStart: Bool = false) {
        self.count = count; self.oldestServerId = oldestServerId; self.oldestSentAt = oldestSentAt; self.reachesStart = reachesStart
    }
    /// Whether it goes back as far as `since` — or, with no `since`, to the chat's first message.
    public func reaches(_ since: Date?) -> Bool {
        if reachesStart { return true }
        guard let since, let oldest = oldestSentAt else { return false }
        return oldest <= since
    }
}

/// A chat peer started (`typing`) or stopped typing in `chatGid`. Live only — never stored.
public struct ChatTypingSignal: Hashable, Sendable {
    public var chatGid: String
    public var userId: Int
    public var typing: Bool
    public init(chatGid: String, userId: Int, typing: Bool) { self.chatGid = chatGid; self.userId = userId; self.typing = typing }
}

/// A formatting the composer's Markdown toolbar applies to the selection.
public enum MarkdownFormat: String, CaseIterable, Hashable, Sendable {
    case bold, italic, underline, strikethrough, code, heading, quote, bulletList, numberedList, indent, outdent, clear
}

/// A group's avatar: an uploaded image, or a short text on a colour.
public enum ChatGroupAvatar: Hashable, Sendable {
    case image(url: String)
    /// `text`: a few characters (may be empty: initials are used). `color`: `#RRGGBB` (may be empty).
    case text(text: String, color: String)

    /// Parses xxd's `{type: image|text, data: {...}}` (nil when absent or unusable).
    public static func from(json: String?) -> ChatGroupAvatar? {
        guard let json, !json.isEmpty, let d = json.data(using: .utf8),
              let raw = try? JSONSerialization.jsonObject(with: d) else { return nil }
        return from(map: raw)
    }

    public static func from(map raw: Any?) -> ChatGroupAvatar? {
        guard let m = raw as? [String: Any], let data = m["data"] as? [String: Any] else { return nil }
        switch m["type"] as? String {
        case "image": if let u = data["imgUrl"] as? String, !u.isEmpty { return .image(url: u) }; return nil
        case "text": return .text(text: (data["customText"] as? String) ?? "", color: (data["bgColor"] as? String) ?? "")
        default: return nil
        }
    }
}
