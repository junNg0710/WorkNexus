import CoreDomain
import Foundation
import Observation

/// A file picked/pasted/dropped into the composer, not yet sent.
public struct StagedFile: Identifiable, Hashable, Sendable {
    public let id: UUID
    public var name: String
    public var data: Data
    public var mimeType: String?
    public init(id: UUID = UUID(), name: String, data: Data, mimeType: String? = nil) {
        self.id = id; self.name = name; self.data = data; self.mimeType = mimeType
    }
}

/// Which side panel is open next to the thread.
public enum ChatSidePanel: Hashable, Sendable {
    case info, members, pinned, files, search
    case thread(rootServerId: Int)
    case emoji, stickers
    /// The AI summary of the chat.
    case assistant
}

/// A request for the message list to scroll to (and flash) a message; `token` makes repeated jumps to the same id fire again.
public struct ChatJumpRequest: Equatable, Sendable { public var serverId: Int; public var token = UUID() }

/// The state one open conversation shares between its parts: header/panels (Shell), message list (Thread) and composer
/// (Composer). Owned by the shell; the other slices only read it and mutate the fields below.
@MainActor @Observable
public final class ChatThreadState {
    public let accountId: String
    public let chatGid: String
    /// The signed-in ZenTao account handle (for `CanSendToChat`/`PinChatMessage`).
    public let selfAccount: String?
    public var chat: ChatConversation
    public var users: [Int: ChatUser] = [:]
    /// The server's names for ZenTao role codes (`dev` → "Developer"), for the AI's reply ideas.
    public var roleNames: [String: String] = [:]
    public var selfUserId: Int?
    /// The message being replied to (shown above the composer, sent as `replyToId`).
    public var replyDraft: ChatMessage?
    public var jump: ChatJumpRequest?
    public var stagedFiles: [StagedFile] = []
    public var sidePanel: ChatSidePanel?
    /// Text the composer should insert at the caret (a mention picked from the list or "@name" from a profile).
    public var pendingInsertion: String?
    /// The text of a retracted message for the composer to put back as it was typed (`editAgain`): in the form it was
    /// sent in, mentions as `[@Name](@#id)`.
    public var pendingRewrite: String?
    public var searchQuery = ""
    /// The chat video playing in a message's frame (or floating over the list); at most one.
    let video = ChatVideoPlaybackModel()
    /// False while the chat is kept open behind another one (`ChatShellModel.openThreads`): nothing in it is being read,
    /// so it marks nothing read, sends no typing signal and plays nothing.
    public internal(set) var isOnScreen = true { didSet { if isOnScreen, !oldValue { onBackOnScreen?() } } }
    /// Run as the chat comes back on screen, before it is drawn: the message list takes in what it held back.
    @ObservationIgnored var onBackOnScreen: (() -> Void)?

    public init(accountId: String, chat: ChatConversation, selfAccount: String? = nil) {
        self.accountId = accountId; self.chatGid = chat.gid; self.chat = chat; self.selfAccount = selfAccount
    }

    public func requestJump(to serverId: Int) { jump = ChatJumpRequest(serverId: serverId) }

    // MARK: retracted, to write again

    /// What a message retracted here said, and what it answered.
    public struct RetractedText: Equatable, Sendable {
        public var text: String
        public var replyToId: Int?
    }

    /// The user's own text messages retracted in this chat while it is open, by message: each can be put back into the
    /// input, changed and sent again. Kept in memory only - the server no longer shows them to anyone - and only the
    /// last few.
    public private(set) var retracted: [String: RetractedText] = [:]
    @ObservationIgnored private var retractedOrder: [String] = []
    public static let retractedKept = 20

    /// `message` was just retracted: its text is kept for `editAgain`. Only a text of the user's own.
    public func keepRetracted(_ message: ChatMessage) {
        guard message.isMine, let text = message.content.asText?.text, !text.isEmpty else { return }
        retracted[message.gid] = RetractedText(text: text, replyToId: message.replyToId)
        retractedOrder.removeAll { $0 == message.gid }
        retractedOrder.append(message.gid)
        while retractedOrder.count > Self.retractedKept { retracted[retractedOrder.removeFirst()] = nil }
    }

    /// Puts the retracted message's text back into the input, answering `quoted` again when it answered a message.
    public func editAgain(_ gid: String, quoted: ChatMessage? = nil) {
        guard let kept = retracted[gid] else { return }
        if let quoted, !quoted.deleted { replyDraft = quoted }
        pendingRewrite = kept.text
    }

    // MARK: multiple select

    /// "Multiple select": nil while off; while on, the messages picked so far (in the order they were picked).
    public var selection: [ChatMessage]?
    public var isSelecting: Bool { selection != nil }
    public func isSelected(_ message: ChatMessage) -> Bool { selection?.contains { $0.gid == message.gid } ?? false }
    public func beginSelection(with message: ChatMessage) { selection = Self.canSelect(message) ? [message] : [] }
    public func endSelection() { selection = nil }
    public func toggleSelected(_ message: ChatMessage) {
        guard var picked = selection, Self.canSelect(message) else { return }
        if let at = picked.firstIndex(where: { $0.gid == message.gid }) { picked.remove(at: at) } else { picked.append(message) }
        selection = picked
    }
    /// The picked messages, oldest first.
    public var selectedInOrder: [ChatMessage] {
        (selection ?? []).sorted { ($0.sentAt, $0.serverId ?? .max) < ($1.sentAt, $1.serverId ?? .max) }
    }
    /// A message that can be picked: one the server holds, not a notice, not retracted.
    public static func canSelect(_ message: ChatMessage) -> Bool {
        !message.deleted && !message.isNotice && message.serverId != nil && message.sendState == .sent
    }
}
