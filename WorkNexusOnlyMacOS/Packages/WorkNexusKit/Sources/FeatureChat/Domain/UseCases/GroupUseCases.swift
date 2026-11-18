import CoreDomain
import Foundation

/// Renames a group: owner and admins, while it is not dismissed (the server checks too).
/// Ported from: lib/features/chat/domain/usecases/rename_group_chat.dart
public struct RenameGroupChat: Sendable {
    private let repository: ChatRepository
    public init(_ repository: ChatRepository) { self.repository = repository }

    public func callAsFunction(_ chat: ChatConversation, _ name: String) async -> Outcome<Void> {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return .failure(.unexpected("A group needs a name")) }
        // Nothing to send; the dialog just closes.
        if trimmed == chat.name { return .success(()) }
        return await repository.renameGroupChat(accountId: chat.accountId, chatGid: chat.gid, name: trimmed)
    }
}

/// Dismisses (disbands) a group for everyone; only its owner may. xxd keeps the group and its history but marks it
/// dismissed, so it leaves every member's chat list.
/// Ported from: lib/features/chat/domain/usecases/dismiss_group_chat.dart
public struct DismissGroupChat: Sendable {
    private let repository: ChatRepository
    public init(_ repository: ChatRepository) { self.repository = repository }

    public func callAsFunction(_ chat: ChatConversation, selfAccount: String?) async -> Outcome<Void> {
        guard ChatGroupPolicy.canDismiss(chat, selfAccount: selfAccount) else {
            return .failure(.unexpected("Only the owner can dismiss this group"))
        }
        return await repository.dismissGroupChat(accountId: chat.accountId, chatGid: chat.gid)
    }
}

/// Leaves a group; its owner cannot (they dismiss it instead).
/// Ported from: lib/features/chat/domain/usecases/leave_group_chat.dart
public struct LeaveGroupChat: Sendable {
    private let repository: ChatRepository
    public init(_ repository: ChatRepository) { self.repository = repository }

    public func callAsFunction(_ chat: ChatConversation, selfAccount: String?) async -> Outcome<Void> {
        guard ChatGroupPolicy.canLeave(chat, selfAccount: selfAccount) else { return .failure(.unexpected("The owner cannot leave the group")) }
        return await repository.leaveGroupChat(accountId: chat.accountId, chatGid: chat.gid)
    }
}

/// Adds people to a group (see `ChatGroupPolicy.canAddMembers` for who may), each once.
/// Ported from: lib/features/chat/domain/usecases/add_group_members.dart
public struct AddGroupMembers: Sendable {
    private let repository: ChatRepository
    public init(_ repository: ChatRepository) { self.repository = repository }

    public func callAsFunction(_ chat: ChatConversation, _ userIds: [Int]) async -> Outcome<Void> {
        var seen = Set<Int>(), ids: [Int] = []
        for id in userIds where seen.insert(id).inserted { ids.append(id) }
        guard !ids.isEmpty else { return .failure(.unexpected("Pick someone to add")) }
        return await repository.addGroupMembers(accountId: chat.accountId, chatGid: chat.gid, userIds: ids)
    }
}

/// Removes someone from a group: only its owner, and never themself.
/// Ported from: lib/features/chat/domain/usecases/remove_group_member.dart
public struct RemoveGroupMember: Sendable {
    private let repository: ChatRepository
    public init(_ repository: ChatRepository) { self.repository = repository }

    public func callAsFunction(_ chat: ChatConversation, _ userId: Int, selfUserId: Int?, selfAccount: String?) async -> Outcome<Void> {
        guard ChatGroupPolicy.canRemoveMembers(chat, selfAccount: selfAccount), userId != selfUserId else {
            return .failure(.unexpected("Only the owner can remove other members"))
        }
        return await repository.removeGroupMembers(accountId: chat.accountId, chatGid: chat.gid, userIds: [userId])
    }
}

/// Changes a group's settings: public or not, whether only its owner and admins add people, and who may post.
/// Ported from: lib/features/chat/domain/usecases/update_group_settings.dart
public struct UpdateGroupSettings: Sendable {
    private let repository: ChatRepository
    public init(_ repository: ChatRepository) { self.repository = repository }

    public func callAsFunction(_ chat: ChatConversation, isPublic: Bool, adminInvite: Bool, committers: ChatCommitters) async -> Outcome<Void> {
        if committers.scope == .selected && committers.userIds.isEmpty { return .failure(.unexpected("Pick who may post")) }
        // Anyone may join a public group, so keeping invites to admins would mean nothing (the official client clears it too).
        return await repository.setGroupSettings(accountId: chat.accountId, chatGid: chat.gid, isPublic: isPublic,
                                                 adminInvite: !isPublic && adminInvite, committers: committers.encode())
    }
}

/// Makes a member an admin of a group, or a plain member again: only the owner, and not for themself.
/// Ported from: lib/features/chat/domain/usecases/set_group_admin.dart
public struct SetGroupAdmin: Sendable {
    private let repository: ChatRepository
    public init(_ repository: ChatRepository) { self.repository = repository }

    public func callAsFunction(_ chat: ChatConversation, _ userId: Int, admin: Bool, selfUserId: Int?, selfAccount: String?) async -> Outcome<Void> {
        guard ChatGroupPolicy.canManageAdmins(chat, selfAccount: selfAccount), userId != selfUserId else {
            return .failure(.unexpected("Only the owner can change who are admins"))
        }
        return await repository.setGroupAdmins(accountId: chat.accountId, chatGid: chat.gid, userIds: [userId], admin: admin)
    }
}

/// Hands a group over to another member, its new owner; only the current owner may.
/// Ported from: lib/features/chat/domain/usecases/transfer_group_ownership.dart
public struct TransferGroupOwnership: Sendable {
    private let repository: ChatRepository
    public init(_ repository: ChatRepository) { self.repository = repository }

    public func callAsFunction(_ chat: ChatConversation, _ userId: Int, selfUserId: Int?, selfAccount: String?) async -> Outcome<Void> {
        guard ChatGroupPolicy.canManageAdmins(chat, selfAccount: selfAccount), userId != selfUserId else {
            return .failure(.unexpected("Only the owner can hand the group over"))
        }
        return await repository.transferGroupOwnership(accountId: chat.accountId, chatGid: chat.gid, userId: userId)
    }
}
