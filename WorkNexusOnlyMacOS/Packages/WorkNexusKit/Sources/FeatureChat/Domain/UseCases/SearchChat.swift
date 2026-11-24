/// Not in the Flutter app.
import CoreDomain
import Foundation

/// What the Chat page's search is asked: what was typed - words, and the filters `from:` (who sent it), `in:` (which
/// chat) and `has:` (file, image, link, code) - with what the search's own controls narrow it to.
public struct ChatSearchRequest: Hashable, Sendable {
    public var query: String
    /// The kind picked in the search's tabs; nil: all. It wins over a `has:` typed.
    public var kind: ChatSearchKind?
    public var since: Date?
    /// Every match instead of the first few.
    public var all: Bool
    public init(query: String, kind: ChatSearchKind? = nil, since: Date? = nil, all: Bool = false) {
        self.query = query; self.kind = kind; self.since = since; self.all = all
    }
}

/// What it found. The first few of each kind are listed until every one is asked for.
public struct ChatSearchFound: Sendable {
    /// The words searched (the filters taken out).
    public var terms: [String] = []
    public var chats: [ChatConversation] = []
    public var chatCount = 0
    public var people: [ChatUser] = []
    public var peopleCount = 0
    /// Best first: the words as typed, then each a word of its own, then the rest; newest first within each.
    public var messages: [ChatMessage] = []
    public var messageCount = 0
    /// More messages match than the search looks at (`SearchChat.messageMax`).
    public var messagesCapped = false
    /// While a filter is being typed (`from:mi`, `in:wal`): its key, and who or what it could name.
    public var typing: String?
    public var offeredPeople: [ChatUser] = []
    public var offeredChats: [ChatConversation] = []
    public var conversations: [String: ChatConversation] = [:]
    public var users: [Int: ChatUser] = [:]
    public init() {}
}

/// The search of the Chat page: chats and people by name, and the messages stored on this Mac. Every word typed has to be
/// there, in any order, without case or diacritics; words in "quotes" stay together (`SearchTerms`).
@MainActor
public struct SearchChat {
    public static let filterKeys: Set<String> = ["from", "in", "has"]
    /// How many are listed at first...
    public static let chatLimit = 6
    public static let peopleLimit = 4
    public static let messageLimit = 30
    /// ...the most messages one search looks at, and the most names offered for a filter being typed.
    public static let messageMax = 300
    public static let offerLimit = 8
    /// The chats offered before anything is typed.
    public static let recentChats = 5

    private let repository: ChatRepository
    public init(_ repository: ChatRepository) { self.repository = repository }

    /// - Parameters:
    ///   - title: a chat's name as shown (a one-to-one chat is named after the other person).
    ///   - said: a message as one line of text, to rank it by.
    public func callAsFunction(accountId: String, _ request: ChatSearchRequest, title: (ChatConversation, [Int: ChatUser]) -> String,
                               said: (ChatMessage) -> String) async -> ChatSearchFound {
        var out = await base(accountId)
        let parsed = SearchTerms.filters(in: request.query, keys: Self.filterKeys)
        let terms = SearchTerms.parse(parsed.text)
        out.terms = terms
        let people = out.users.values.filter { !$0.deleted }.sorted { $0.realname.localizedCaseInsensitiveCompare($1.realname) == .orderedAscending }
        let chats = out.conversations.values.filter { !$0.archived }.sorted(by: Self.lastActiveFirst)
        func named(_ value: String, _ user: ChatUser) -> Bool { SearchTerms.allFound(SearchTerms.parse(value), in: "\(user.realname) \(user.account)") }
        func named(_ value: String, _ chat: ChatConversation) -> Bool { SearchTerms.allFound(SearchTerms.parse(value), in: title(chat, out.users)) }

        // A filter still being typed offers who or what it could name, and does not narrow anything yet.
        if let typing = parsed.typing, typing.key == "from" || typing.key == "in" {
            out.typing = typing.key
            if typing.key == "from" { out.offeredPeople = Array(people.filter { named(typing.value, $0) }.prefix(Self.offerLimit)) }
            else { out.offeredChats = Array(chats.filter { named(typing.value, $0) }.prefix(Self.offerLimit)) }
        }
        let from = (parsed.filters["from"] ?? []).filter { !$0.isEmpty && !(out.typing == "from" && $0 == parsed.typing?.value) }
        let within = (parsed.filters["in"] ?? []).filter { !$0.isEmpty && !(out.typing == "in" && $0 == parsed.typing?.value) }
        let senders = from.isEmpty ? nil : people.filter { p in from.contains { named($0, p) } }.map(\.userId)
        let scope = within.isEmpty ? nil : chats.filter { c in within.contains { named($0, c) } }.map(\.gid)
        let kind = request.kind ?? (parsed.filters["has"] ?? []).compactMap(Self.kind).first
        let narrowed = senders != nil || scope != nil || kind != nil

        if !terms.isEmpty, !narrowed {
            let found = chats.filter { SearchTerms.allFound(terms, in: title($0, out.users)) }
            out.chatCount = found.count
            out.chats = Array(found.prefix(request.all ? found.count : Self.chatLimit))
            let who = people.filter { SearchTerms.allFound(terms, in: "\($0.realname) \($0.account)") }
            out.peopleCount = who.count
            out.people = Array(who.prefix(request.all ? who.count : Self.peopleLimit))
        }
        // A filter that names nobody (or no chat) finds nothing, rather than everything.
        if senders?.isEmpty == true || scope?.isEmpty == true { return out }
        let search = ChatMessageSearch(query: parsed.text, chatGids: scope, senderIds: senders, kind: kind, since: request.since, limit: Self.messageMax + 1)
        guard !search.asksNothing else { return out }
        let stored = (await PerformanceLog.measure("chat: search stored messages", slowerThan: 0.15) {
            await repository.searchMessages(accountId: accountId, matching: search)
        }).value ?? []
        // One not on the server yet cannot be jumped to.
        let found = stored.filter { $0.serverId != nil }
        out.messagesCapped = found.count > Self.messageMax
        out.messageCount = min(found.count, Self.messageMax)
        let looked = Array(found.prefix(Self.messageMax))
        // The store gives them newest first, which holds within each rank.
        let ranks = terms.isEmpty ? [] : looked.map { SearchTerms.rank(terms, in: said($0)) }
        let best = terms.isEmpty ? looked : (0...2).flatMap { rank in zip(looked, ranks).filter { $0.1 == rank }.map(\.0) }
        out.messages = Array(best.prefix(request.all ? Self.messageMax : Self.messageLimit))
        return out
    }

    /// Before anything is typed: the chats last active.
    public func recent(accountId: String) async -> ChatSearchFound {
        var out = await base(accountId)
        let chats = out.conversations.values.filter { !$0.archived && !$0.hidden }.sorted(by: Self.lastActiveFirst)
        out.chatCount = chats.count
        out.chats = Array(chats.prefix(Self.recentChats))
        return out
    }

    /// What `has:` asks for; nil for a word it does not know.
    static func kind(_ word: String) -> ChatSearchKind? {
        switch word.lowercased() {
        case "file", "files", "video", "videos": .files
        case "image", "images", "photo", "photos", "picture", "pictures": .images
        case "link", "links", "url": .links
        case "text", "message", "messages", "code": .messages
        default: nil
        }
    }

    /// The chat last active first; by its id between two that were never active, so the order is the same each time.
    private static func lastActiveFirst(_ a: ChatConversation, _ b: ChatConversation) -> Bool {
        let ta = a.lastActiveAt ?? .distantPast, tb = b.lastActiveAt ?? .distantPast
        return ta != tb ? ta > tb : a.gid < b.gid
    }

    private func base(_ accountId: String) async -> ChatSearchFound {
        var chatsIt = repository.watchConversations(accountId: accountId).makeAsyncIterator()
        var usersIt = repository.watchUsers(accountId: accountId).makeAsyncIterator()
        var out = ChatSearchFound()
        out.conversations = Dictionary((await chatsIt.next() ?? []).map { ($0.gid, $0) }, uniquingKeysWith: { a, _ in a })
        out.users = Dictionary((await usersIt.next() ?? []).map { ($0.userId, $0) }, uniquingKeysWith: { a, _ in a })
        return out
    }
}
