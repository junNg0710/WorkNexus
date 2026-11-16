import CoreDomain
import Foundation

/// One row of the chat list: the chat with its resolved title.
struct ListedChat: Equatable, Identifiable {
    var chat: ChatConversation
    var title: String
    var id: String { chat.gid }
}

/// What the chat list shows: hidden and archived chats are left out, the tab and the search text filter, pinned chats
/// come first and then the most recently active.
/// Ported from: lib/features/chat/presentation/widgets/conversation_list_pane.dart
enum ChatListing {
    static func visible(_ chats: [ChatConversation], users: [Int: ChatUser], tab: ChatListTab, query: String) -> [ListedChat] {
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let listed = chats.enumerated()
            .filter { !$0.element.hidden && !$0.element.archived && tab.matches($0.element) }
            .map { (index: $0.offset, row: ListedChat(chat: $0.element, title: ChatShellLabels.title($0.element, users))) }
            .filter { q.isEmpty || $0.row.title.lowercased().contains(q) }
        // Stable: chats the repository already ordered keep their order within the same rank.
        return listed.sorted { a, b in
            if a.row.chat.starred != b.row.chat.starred { return a.row.chat.starred }
            let ta = a.row.chat.lastActiveAt ?? .distantPast, tb = b.row.chat.lastActiveAt ?? .distantPast
            return ta != tb ? ta > tb : a.index < b.index
        }.map(\.row)
    }

    /// The gid highlighted after stepping `step` through `listed` from `current`; from the top (↓) or the bottom (↑) when
    /// nothing listed is highlighted yet.
    static func moved(_ current: String?, step: Int, in listed: [ListedChat]) -> String? {
        guard !listed.isEmpty else { return current }
        guard let at = listed.firstIndex(where: { $0.id == current }) else { return (step > 0 ? listed.first : listed.last)?.id }
        return listed[min(max(at + step, 0), listed.count - 1)].id
    }

    /// The chat Enter opens: the highlighted one, else the first listed.
    static func picked(_ highlighted: String?, in listed: [ListedChat]) -> String? {
        listed.first { $0.id == highlighted }?.id ?? listed.first?.id
    }

    /// Unread messages under `tab` (hidden and archived chats do not count).
    static func unread(_ chats: [ChatConversation], tab: ChatListTab) -> Int { CountTabUnread()(chats, tab) }
}

/// Who the new-chat picker offers.
/// Ported from: lib/features/chat/presentation/widgets/new_chat_people.dart
enum ChatPeople {
    static func name(_ u: ChatUser) -> String { u.realname.isEmpty ? u.account : u.realname }

    /// Everyone but yourself and deleted accounts.
    static func everyone(_ users: [Int: ChatUser], selfId: Int?) -> [ChatUser] {
        users.values.filter { $0.userId != selfId && !$0.deleted }.sorted { $0.userId < $1.userId }
    }

    /// The people under a role tab (nil: all) matching `query` in name or account, by name.
    static func filtered(_ people: [ChatUser], role: String?, query: String) -> [ChatUser] {
        let q = query.trimmingCharacters(in: .whitespaces).lowercased()
        return people.filter {
            ChatShellLabels.roleMatches(role, $0.role) && (q.isEmpty || $0.realname.lowercased().contains(q) || $0.account.lowercased().contains(q))
        }
        .sorted { name($0).lowercased() < name($1).lowercased() }
    }

    /// "An, Bình, Chi" when the user leaves the group name empty.
    static func defaultGroupName(_ selected: [Int], users: [Int: ChatUser]) -> String {
        selected.prefix(4).map { id in users[id].map(name) ?? "#\(id)" }.joined(separator: ", ")
    }
}
