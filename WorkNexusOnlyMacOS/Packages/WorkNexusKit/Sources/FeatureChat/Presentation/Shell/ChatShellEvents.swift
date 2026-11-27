import Foundation
import Observation

/// The host's two-way line to the chat view: it asks for a chat to be opened (a notification was clicked), says whether the
/// OS blocks notifications (drawn as a banner above the chat) and is told what the user picks there.
/// Ported from: lib/features/chat/presentation/widgets/chat_notification_banner.dart
@MainActor @Observable
public final class ChatShellEvents {
    /// A chat the view should open as soon as it can; the view clears it once it has.
    public var pendingChatGid: String?
    /// A message to show once its chat is open (a search hit); the view clears it once it has.
    public var pendingJump: ChatJumpTarget?
    /// A chat to open with its own search on these words (searching on inside a chat from a hit of the title bar's search);
    /// the view clears it once it has.
    public var pendingSearch: ChatSearchTarget?
    /// Message notifications are on in the app but blocked by the OS: shows the warning strip.
    public var notificationsBlocked = false
    /// "Turn on" in the warning strip.
    @ObservationIgnored public var onEnableNotifications: (() -> Void)?
    /// "View profile" in your own profile dialog (opens the account's page).
    @ObservationIgnored public var onViewProfile: ((_ accountId: String) -> Void)?

    /// "Create bug / task / todo" on a message: the host opens its editor started from the message (nil: not offered).
    @ObservationIgnored public var onCreateTicket: ((ChatTicketRequest) -> Void)?

    /// The user sent a message in a chat: the host closes its search, whose results hang over the chat.
    @ObservationIgnored public var onMessageSent: (() -> Void)?

    /// "Manage" in a chat's storage card: opens the app's storage page.
    @ObservationIgnored public var onOpenStorage: (() -> Void)?

    private let openStore = OpenChatBox()

    /// The chat the view has open right now (nil: none, or the chat view is not shown). Reported by the view; readable from any
    /// thread, because the notification bridge asks it for every incoming message: only that chat's notification is dropped
    /// (when the app is in front and "notify while viewing" is off) — the others still come through.
    public nonisolated var openChat: (accountId: String, chatGid: String)? { openStore.value }

    public init() {}

    /// Called by the view as the open chat changes (nil: no chat is open any more).
    func reportOpenChat(accountId: String, chatGid: String?) {
        openStore.value = chatGid.map { (accountId, $0) }
    }

    /// Opens `chatGid` in the view (what `ChatFeature.open(accountId:chatGid:)` calls).
    public func open(chatGid: String) { pendingChatGid = chatGid }

    /// Opens `chatGid` and jumps to its message `serverId` (loading it from the server when it is not stored around).
    public func open(chatGid: String, jumpTo serverId: Int) { pendingJump = ChatJumpTarget(chatGid: chatGid, serverId: serverId) }

    /// Opens `chatGid` with its search bar on `query` (which also offers to load the chat's older history).
    public func open(chatGid: String, searching query: String) { pendingSearch = ChatSearchTarget(chatGid: chatGid, query: query) }
}

public struct ChatSearchTarget: Equatable, Sendable {
    public var chatGid: String
    public var query: String
}

public struct ChatJumpTarget: Equatable, Sendable {
    public var chatGid: String
    public var serverId: Int
}


/// The open chat, guarded by a lock so the bridge may read it off the main actor.
private final class OpenChatBox: @unchecked Sendable {
    private let lock = NSLock()
    private var stored: (accountId: String, chatGid: String)?
    var value: (accountId: String, chatGid: String)? {
        get { lock.lock(); defer { lock.unlock() }; return stored }
        set { lock.lock(); stored = newValue; lock.unlock() }
    }
}
