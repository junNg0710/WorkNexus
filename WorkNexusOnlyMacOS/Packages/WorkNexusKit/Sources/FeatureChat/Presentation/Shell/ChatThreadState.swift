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

    public init(accountId: String, chat: ChatConversation, selfAccount: String? = nil) {
        self.accountId = accountId; self.chatGid = chat.gid; self.chat = chat; self.selfAccount = selfAccount
    }

    public func requestJump(to serverId: Int) { jump = ChatJumpRequest(serverId: serverId) }
}
