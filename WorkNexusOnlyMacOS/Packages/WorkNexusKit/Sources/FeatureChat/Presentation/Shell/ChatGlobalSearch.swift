/// Not in the Flutter app (its title bar had no search).
import CoreDomain
import Foundation
import SwiftUI

/// One thing the title bar's search found in chat: a conversation or a person by name, or a stored message.
public struct ChatSearchHit: Identifiable, Hashable, Sendable {
    public enum Kind: Hashable, Sendable { case chat, person, message }
    public var id: String
    public var kind: Kind
    /// The conversation's or the person's name.
    public var title: String
    /// What the message says around the words found, the conversation's last message, or the person's account.
    public var subtitle: String
    /// Who sent the message; nil otherwise.
    public var sender: String?
    public var date: Date?
    /// `date` as the chat list writes it: the time today, "Yesterday", a weekday, else a short date.
    public var when: String
    /// The chat to open; empty for a person (their one-to-one chat is opened by `userId`).
    public var chatGid: String
    /// The message to jump to; nil for a conversation or a person.
    public var serverId: Int?
    /// The person; nil otherwise.
    public var userId: Int?
}

/// A name offered for the filter being typed: picking it completes the search with it.
public struct ChatSearchOffer: Identifiable, Hashable, Sendable {
    public var id: String
    public var title: String
    public var subtitle: String
    /// The search with the filter completed.
    public var query: String
    public var chatGid: String?
    public var userId: Int?
}

/// What a search of the Chat page found, ready to list: the first few of each kind, or all of them once asked for.
public struct ChatSearchResults: Sendable {
    public var chats: [ChatSearchHit] = []
    public var people: [ChatSearchHit] = []
    public var messages: [ChatSearchHit] = []
    /// How many match in all; more than are listed until every one is asked for.
    public var chatCount = 0
    public var peopleCount = 0
    public var messageCount = 0
    /// More messages match than the search looks at (`SearchChat.messageMax`).
    public var messagesCapped = false
    /// The words searched, to mark where they were found.
    public var terms: [String] = []
    /// While `from:` or `in:` is being typed: the names it could take.
    public var offers: [ChatSearchOffer] = []
    /// To draw a hit's chat or person: the conversations and the people, by id.
    public var conversations: [String: ChatConversation] = [:]
    public var users: [Int: ChatUser] = [:]

    public var hits: [ChatSearchHit] { chats + people + messages }
}

/// The search of the title bar on the Chat page (`SearchChat`), as rows to list: names, the line a message is found in,
/// times as the chat list writes them. Messages are searched on this Mac only, as the in-chat search is.
@MainActor
public struct ChatGlobalSearch {
    private let search: SearchChat
    private let accountId: String
    public init(repository: ChatRepository, accountId: String) { search = SearchChat(repository); self.accountId = accountId }

    public func search(_ query: String, kind: ChatSearchKind? = nil, since: Date? = nil, all: Bool = false) async -> ChatSearchResults {
        let found = await search(accountId: accountId, ChatSearchRequest(query: query, kind: kind, since: since, all: all),
                                 title: { ChatShellLabels.title($0, $1) }, said: Self.said)
        var out = listed(found)
        out.people = found.people.map { u in
            ChatSearchHit(id: "user:\(u.userId)", kind: .person, title: ChatTextLabels.userName(found.users, u.userId), subtitle: u.account,
                          sender: nil, date: nil, when: "", chatGid: "", serverId: nil, userId: u.userId)
        }
        out.messages = found.messages.map { m in
            ChatSearchHit(id: "msg:\(m.gid)", kind: .message, title: found.conversations[m.chatGid].map { ChatShellLabels.title($0, found.users) } ?? m.chatGid,
                          subtitle: SearchTerms.snippet(Self.said(m), terms: found.terms), sender: ChatTextLabels.userName(found.users, m.senderId),
                          date: m.sentAt, when: ChatShellLabels.listTime(m.sentAt), chatGid: m.chatGid, serverId: m.serverId, userId: nil)
        }
        out.offers = found.offeredPeople.map { u in
            let name = ChatTextLabels.userName(found.users, u.userId)
            return ChatSearchOffer(id: "from:\(u.userId)", title: name, subtitle: u.account, query: SearchTerms.completing(query, key: "from", with: name),
                                   chatGid: nil, userId: u.userId)
        } + found.offeredChats.map { c in
            let name = ChatShellLabels.title(c, found.users)
            return ChatSearchOffer(id: "in:\(c.gid)", title: name, subtitle: "", query: SearchTerms.completing(query, key: "in", with: name),
                                   chatGid: c.gid, userId: nil)
        }
        return out
    }

    /// Before anything is typed: the chats last active.
    public func recent() async -> ChatSearchResults { listed(await search.recent(accountId: accountId)) }

    /// A message as one line: what it says, or - for a picture, which says nothing - its file's name.
    private static func said(_ m: ChatMessage) -> String {
        if case .image(let image) = m.content, !m.deleted { return image.name }
        return ChatShellLabels.preview(m)
    }

    private func listed(_ found: ChatSearchFound) -> ChatSearchResults {
        var out = ChatSearchResults()
        out.terms = found.terms; out.conversations = found.conversations; out.users = found.users
        out.chatCount = found.chatCount; out.peopleCount = found.peopleCount
        out.messageCount = found.messageCount; out.messagesCapped = found.messagesCapped
        out.chats = found.chats.map { c in
            ChatSearchHit(id: "chat:\(c.gid)", kind: .chat, title: ChatShellLabels.title(c, found.users),
                          subtitle: c.lastMessage.map { ChatShellLabels.preview($0) } ?? "", sender: nil, date: c.lastMessage?.sentAt,
                          when: ChatShellLabels.listTime(c.lastMessage?.sentAt), chatGid: c.gid, serverId: nil, userId: nil)
        }
        return out
    }
}

/// The picture of a search hit: its chat's (the group's, or the person's in a one-to-one chat), or a person's own.
public struct ChatSearchAvatar: View {
    let chat: ChatConversation?
    let userId: Int?
    let users: [Int: ChatUser]
    let side: CGFloat
    public init(chat: ChatConversation, users: [Int: ChatUser], side: CGFloat = 28) { self.chat = chat; userId = nil; self.users = users; self.side = side }
    public init(userId: Int, users: [Int: ChatUser], side: CGFloat = 28) { chat = nil; self.userId = userId; self.users = users; self.side = side }
    public var body: some View {
        if let chat { ChatAvatarView(chat: chat, title: ChatShellLabels.title(chat, users), users: users, diameter: side) }
        else if let userId { ChatAvatarView(userId: userId, users: users, diameter: side, showPresence: false) }
    }
}
