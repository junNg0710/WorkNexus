import CoreDomain
import Foundation

/// Who may send, as xxd stores it (`$ALL`, `$ADMINS`, or a comma list of ids/accounts); owners and admins always may.
/// Ported from: lib/features/chat/domain/usecases/can_send_to_chat.dart
public struct CanSendToChat: Sendable {
    public init() {}
    public func callAsFunction(_ chat: ChatConversation, selfUserId: Int?, selfAccount: String?) -> Bool {
        let committers = chat.committers.trimmingCharacters(in: .whitespacesAndNewlines)
        if committers.isEmpty || committers == "$ALL" { return true }
        let isOwner = selfAccount != nil && selfAccount == chat.ownerAccount
        let isAdmin = selfUserId.map { chat.adminIds.contains($0) } ?? false
        if committers == "$ADMINS" { return isOwner || isAdmin }
        let allowed = Set(committers.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) })
        return isOwner || (selfUserId.map { allowed.contains("\($0)") } ?? false) || (selfAccount.map { allowed.contains($0) } ?? false)
    }
}

/// Ported from: lib/features/chat/domain/usecases/count_badge_unread.dart
public struct CountBadgeUnread: Sendable {
    public init() {}
    public func callAsFunction(_ chats: [ChatConversation]) -> Int {
        chats.filter { !$0.hidden && !$0.archived && !$0.muted }.reduce(0) { $0 + $1.unreadCount }
    }
}

/// Ported from: lib/features/chat/domain/usecases/count_tab_unread.dart
public struct CountTabUnread: Sendable {
    public init() {}
    public func callAsFunction(_ chats: [ChatConversation], _ tab: ChatListTab) -> Int {
        chats.filter { !$0.hidden && !$0.archived && tab.matches($0) }.reduce(0) { $0 + $1.unreadCount }
    }
}

/// Ported from: lib/features/chat/domain/usecases/resolve_chat_title.dart
public struct ResolveChatTitle: Sendable {
    public init() {}
    /// The title to show, or nil while it is unknown (a one-to-one chat whose peer is not loaded yet).
    public func callAsFunction(_ chat: ChatConversation, _ usersById: [Int: ChatUser]) -> String? {
        if chat.type == .one2one {
            guard let peerId = chat.peerUserId, let peer = usersById[peerId] else { return nil }
            return peer.realname.isEmpty ? peer.account : peer.realname
        }
        let name = chat.name.trimmingCharacters(in: .whitespacesAndNewlines)
        return name.isEmpty ? nil : name
    }
}

/// Ported from: lib/features/chat/domain/usecases/order_chat_roles.dart
public struct OrderChatRoles: Sendable {
    public init() {}
    private static let known: [ChatRole] = [.top, .td, .pd, .qd, .pm, .po, .dev, .qa, .others]
    public func callAsFunction(_ codes: [String?]) -> [String] {
        let present = Set(codes.map { $0?.trimmingCharacters(in: .whitespaces) ?? "" })
        var out = Self.known.map(\.rawValue).filter(present.contains)
        out += present.filter { !$0.isEmpty && ChatRole.from(code: $0) == nil }.sorted()
        if present.contains("") { out.append("") }
        return out
    }
}

/// Ported from: lib/features/chat/domain/usecases/should_notify_chat_message.dart
public struct ShouldNotifyChatMessage: Sendable {
    public init() {}
    public func callAsFunction(_ message: ChatMessage, enabled: Bool, appFocused: Bool,
                               visibleChat: (accountId: String, chatGid: String)?, conversation: ChatConversation? = nil,
                               whileViewing: Bool = false, reactions: Bool = true) -> Bool {
        if !enabled || message.isMine || message.deleted || (reactions && message.isReaction) { return false }
        if let c = conversation, c.hidden || c.archived || c.muted { return false }
        if whileViewing { return true }
        let looking = appFocused && visibleChat?.accountId == message.accountId && visibleChat?.chatGid == message.chatGid
        return !looking
    }
}

/// Ported from: lib/features/chat/domain/usecases/pin_chat_message.dart
public struct PinChatMessage: Sendable {
    private let repository: ChatRepository
    public init(_ repository: ChatRepository) { self.repository = repository }

    public func canPin(_ chat: ChatConversation, selfUserId: Int?, selfAccount: String?) -> Bool {
        chat.type == .one2one || (selfUserId.map { chat.adminIds.contains($0) } ?? false)
            || (selfAccount != nil && selfAccount == chat.ownerAccount)
    }

    public func callAsFunction(_ m: ChatMessage, pinned: Bool) async -> Outcome<Void> {
        guard let serverId = m.serverId, !m.deleted else { return .failure(.unexpected("Only delivered messages can be pinned")) }
        return await repository.setMessagePinned(accountId: m.accountId, chatGid: m.chatGid, serverId: serverId, pinned: pinned)
    }
}
