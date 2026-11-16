import Foundation

/// The user's notification preferences, read fresh for every message.
public struct ChatNotificationPreferences: Sendable, Equatable {
    public var enabled: Bool
    public var whileViewing: Bool
    public var reactions: Bool
    public init(enabled: Bool = true, whileViewing: Bool = true, reactions: Bool = false) {
        self.enabled = enabled; self.whileViewing = whileViewing; self.reactions = reactions
    }
}

/// Fixed phrases used in notification previews; the host overrides them with its localized strings.
public struct ChatNotificationTexts: Sendable {
    public var photo = "Photo", file = "File", code = "Code", link = "Link", notification = "Notification", message = "New message"
    public init() {}
}

/// Raises a notification for each new message the user is not already looking at (`ShouldNotifyChatMessage`), naming the chat
/// and sender from the locally stored conversations and users. The host implements `ChatNotificationSink`.
/// Ported from: lib/features/chat/presentation/widgets/chat_notification_listener.dart
public final class ChatNotificationBridge: @unchecked Sendable {
    private struct Directory { var chats: [String: ChatConversation] = [:]; var users: [Int: ChatUser] = [:] }

    private let repository: ChatRepository
    private let sink: ChatNotificationSink
    private let preferences: @Sendable () -> ChatNotificationPreferences
    private let visibleChat: @Sendable () -> (accountId: String, chatGid: String)?
    private let texts: ChatNotificationTexts
    private let lock = NSLock()
    private var directories: [String: Directory] = [:]
    private var tasks: [Task<Void, Never>] = []

    public init(repository: ChatRepository, sink: ChatNotificationSink, texts: ChatNotificationTexts = ChatNotificationTexts(),
                preferences: @escaping @Sendable () -> ChatNotificationPreferences,
                visibleChat: @escaping @Sendable () -> (accountId: String, chatGid: String)?) {
        self.repository = repository; self.sink = sink; self.texts = texts; self.preferences = preferences; self.visibleChat = visibleChat
    }

    /// Starts watching the given accounts' incoming messages (keeps their chats and users loaded for naming).
    public func start(accountIds: [String]) {
        stop()
        var started: [Task<Void, Never>] = []
        started.append(Task { [self] in for await m in repository.watchIncoming() { handle(m) } })
        for id in accountIds {
            started.append(Task { [self] in for await chats in repository.watchConversations(accountId: id) { update(id) { $0.chats = Dictionary(chats.map { ($0.gid, $0) }, uniquingKeysWith: { a, _ in a }) } } })
            started.append(Task { [self] in for await users in repository.watchUsers(accountId: id) { update(id) { $0.users = Dictionary(users.map { ($0.userId, $0) }, uniquingKeysWith: { a, _ in a }) } } })
        }
        lock.lock(); tasks = started; lock.unlock()
    }

    public func stop() {
        lock.lock(); let t = tasks; tasks = []; lock.unlock()
        t.forEach { $0.cancel() }
    }

    private func update(_ accountId: String, _ change: (inout Directory) -> Void) {
        lock.lock(); defer { lock.unlock() }
        var d = directories[accountId] ?? Directory()
        change(&d)
        directories[accountId] = d
    }

    private func handle(_ m: ChatMessage) {
        lock.lock(); let dir = directories[m.accountId] ?? Directory(); lock.unlock()
        let prefs = preferences()
        let chat = dir.chats[m.chatGid]
        guard ShouldNotifyChatMessage()(m, enabled: prefs.enabled, appFocused: sink.appIsFocused, visibleChat: visibleChat(), conversation: chat,
                                        whileViewing: prefs.whileViewing, reactions: prefs.reactions) else { return }
        let sender = name(dir.users[m.senderId])
        let direct = chat == nil || chat?.type == .one2one
        let title: String = {
            guard let chat else { return sender }
            if chat.type == .one2one { return name(chat.peerUserId.flatMap { dir.users[$0] }, fallback: chat.name) }
            return chat.name.isEmpty ? sender : chat.name
        }()
        sink.deliver(ChatNotification(accountId: m.accountId, chatGid: m.chatGid, messageGid: m.gid, title: title, subtitle: direct ? nil : sender,
                                      body: Self.preview(m.content, texts)))
    }

    private func name(_ u: ChatUser?, fallback: String = "") -> String {
        guard let u else { return fallback }
        return u.realname.isEmpty ? u.account : u.realname
    }

    /// A one-line summary of a message.
    public static func preview(_ content: MessageContent, _ t: ChatNotificationTexts = ChatNotificationTexts()) -> String {
        switch content {
        case .text(let s, _):
            let plain = s.replacingOccurrences(of: #"\[@([^\]]+)\]\(@#\d+\)"#, with: "@$1", options: .regularExpression)
                .replacingOccurrences(of: #"[*~`]"#, with: "", options: .regularExpression)
            return plain.split(whereSeparator: \.isNewline).first.map(String.init) ?? plain
        case .image: return t.photo
        case .file(let f): return "\(t.file): \(f.name)"
        case .emoji(let e): return e
        case .code(_, _, let name): return name.map { "\(t.code): \($0)" } ?? t.code
        case .link(_, let title): return title ?? t.link
        case .notification(let n): return n.title ?? (n.text.isEmpty ? t.notification : n.text)
        case .unsupported: return t.message
        }
    }
}
