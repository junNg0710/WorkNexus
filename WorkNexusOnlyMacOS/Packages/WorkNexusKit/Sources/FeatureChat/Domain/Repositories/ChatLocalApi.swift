import CoreDomain
import Foundation

/// One page further back in a chat's stored timeline: how many messages it added, and whether the timeline now holds the
/// chat's first message.
/// Ported from: lib/features/chat/domain/repositories/chat_local_api.dart
public struct ChatHistoryStep: Equatable, Sendable {
    public var loaded: Int
    public var reachesStart: Bool
    public init(loaded: Int, reachesStart: Bool) { self.loaded = loaded; self.reachesStart = reachesStart }
}

/// A message's file or image, downloaded to a local file at `path`.
public struct ChatAttachmentFile: Equatable, Sendable {
    public var path: String
    public var name: String
    public var size: Int
    public var mimeType: String?
    public var isImage: Bool
    public init(path: String, name: String, size: Int, mimeType: String?, isImage: Bool) {
        self.path = path; self.name = name; self.size = size; self.mimeType = mimeType; self.isImage = isImage
    }
}

/// What the local API does for each request, through this app's chat session.
public struct ChatLocalApiHandlers: Sendable {
    /// Sends one text message on the user's behalf.
    public var send: @Sendable (_ accountId: String, _ chatGid: String, _ text: String, _ markdown: Bool) async -> Outcome<Void>
    /// Pages a chat's stored timeline one page further back.
    public var loadOlder: @Sendable (_ accountId: String, _ chatGid: String, _ pageSize: Int) async -> Outcome<ChatHistoryStep>
    /// Downloads the file or image of server message `messageId`.
    public var attachment: @Sendable (_ accountId: String, _ chatGid: String, _ messageId: Int) async -> Outcome<ChatAttachmentFile>

    public init(send: @escaping @Sendable (String, String, String, Bool) async -> Outcome<Void>,
                loadOlder: @escaping @Sendable (String, String, Int) async -> Outcome<ChatHistoryStep>,
                attachment: @escaping @Sendable (String, String, Int) async -> Outcome<ChatAttachmentFile>) {
        self.send = send; self.loadOlder = loadOlder; self.attachment = attachment
    }
}

/// A local endpoint other programs on this computer — an AI assistant's MCP server — use chat through: sending messages,
/// loading older history and downloading attachments with the chat session this app is already signed into. Off unless
/// the user turns it on in the chat settings.
public protocol ChatLocalApi: Sendable {
    /// Starts answering requests with `handlers`. Calling it again while running only replaces `handlers`.
    func start(_ handlers: ChatLocalApiHandlers) async -> Outcome<Void>
    /// Stops answering and forgets how it was reached.
    func stop() async -> Outcome<Void>
}
