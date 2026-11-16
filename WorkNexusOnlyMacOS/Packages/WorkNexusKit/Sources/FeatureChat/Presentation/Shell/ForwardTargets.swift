import CoreDomain
import Foundation

/// The chats a message can be forwarded to: listed (not hidden or archived) and open to the user's posts, in the chat
/// list's order, optionally narrowed by a title search.
/// Ported from: lib/features/chat/presentation/widgets/forward_message_dialog.dart (`_targets` + the search filter)
enum ForwardTargets {
    static func chats(_ conversations: [ChatConversation], users: [Int: ChatUser], selfUserId: Int?, query: String = "") -> [ListedChat] {
        let account = selfUserId.flatMap { users[$0]?.account }
        let listed = ChatListing.visible(conversations, users: users, tab: .all, query: "")
            .filter { CanSendToChat()($0.chat, selfUserId: selfUserId, selfAccount: account) }
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return q.isEmpty ? listed : listed.filter { $0.title.lowercased().contains(q) }
    }
}
