/// Not in the Flutter app.
import CoreDomain
import Foundation

/// What kind of stored message a search is narrowed to.
public enum ChatSearchKind: String, Hashable, Sendable, CaseIterable {
    /// What people wrote: text and code.
    case messages
    /// Files sent (by their name), videos among them.
    case files
    /// Shared links, and text that holds a web address.
    case links
    /// Pictures (by their name).
    case images
}

/// A search over the messages stored on this Mac: the words (all of them, `SearchTerms`) and what narrows it. Without
/// words it lists what the rest lets through, newest first - a chat's files, what one person sent.
public struct ChatMessageSearch: Hashable, Sendable {
    public var query: String
    /// Only these chats; nil: every chat.
    public var chatGids: [String]?
    /// Only what these people sent; nil: anyone.
    public var senderIds: [Int]?
    /// nil: everything but pictures, which have only a file name to go by.
    public var kind: ChatSearchKind?
    public var since: Date?
    public var limit: Int?

    public init(query: String = "", chatGids: [String]? = nil, senderIds: [Int]? = nil, kind: ChatSearchKind? = nil, since: Date? = nil, limit: Int? = nil) {
        self.query = query; self.chatGids = chatGids; self.senderIds = senderIds; self.kind = kind; self.since = since; self.limit = limit
    }

    /// Nothing typed and nothing narrowing it: there is nothing to look for.
    public var asksNothing: Bool { SearchTerms.parse(query).isEmpty && chatGids == nil && senderIds == nil && kind == nil }
}
