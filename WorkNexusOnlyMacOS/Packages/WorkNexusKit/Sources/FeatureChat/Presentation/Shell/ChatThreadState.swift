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
    public var searchQuery = ""
    /// The chat video playing in a message's frame (or floating over the list); at most one.
    let video = ChatVideoPlaybackModel()
    /// False while the chat is kept open behind another one (`ChatShellModel.openThreads`): nothing in it is being read,
    /// so it marks nothing read, sends no typing signal and plays nothing.
    public internal(set) var isOnScreen = true

    public init(accountId: String, chat: ChatConversation, selfAccount: String? = nil) {
        self.accountId = accountId; self.chatGid = chat.gid; self.chat = chat; self.selfAccount = selfAccount
    }

    public func requestJump(to serverId: Int) { jump = ChatJumpRequest(serverId: serverId) }

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
