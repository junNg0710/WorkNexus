import Foundation

/// Who may do what to a group, as the official ZenTao client decides it (the server has the final say). A dismissed group
/// (`archived`) and anything but a group allow nothing.
/// Ported from: the `can…` checks of lib/features/chat/domain/usecases/{rename_group_chat,dismiss_group_chat,
/// add_group_members,remove_group_member,leave_group_chat,update_group_settings,set_group_admin,transfer_group_ownership}.dart
public enum ChatGroupPolicy {
    static func live(_ chat: ChatConversation) -> Bool { chat.type == .group && !chat.archived }

    static func isOwner(_ chat: ChatConversation, selfAccount: String?) -> Bool {
        selfAccount != nil && selfAccount == chat.ownerAccount
    }

    static func isOwnerOrAdmin(_ chat: ChatConversation, selfUserId: Int?, selfAccount: String?) -> Bool {
        (selfUserId.map { chat.adminIds.contains($0) } ?? false) || isOwner(chat, selfAccount: selfAccount)
    }

    /// Owner and admins rename.
    public static func canRename(_ chat: ChatConversation, selfUserId: Int?, selfAccount: String?) -> Bool {
        live(chat) && isOwnerOrAdmin(chat, selfUserId: selfUserId, selfAccount: selfAccount)
    }

    /// Only the owner dismisses.
    public static func canDismiss(_ chat: ChatConversation, selfAccount: String?) -> Bool {
        live(chat) && isOwner(chat, selfAccount: selfAccount)
    }

    /// The owner and admins add people; so does anyone allowed to post, unless the group keeps inviting to admins
    /// (`adminInvite`) and is not public.
    public static func canAddMembers(_ chat: ChatConversation, selfUserId: Int?, selfAccount: String?) -> Bool {
        guard live(chat) else { return false }
        if isOwnerOrAdmin(chat, selfUserId: selfUserId, selfAccount: selfAccount) { return true }
        return CanSendToChat()(chat, selfUserId: selfUserId, selfAccount: selfAccount) && (!chat.adminInvite || chat.isPublic)
    }

    /// Only the owner removes people (never themself).
    public static func canRemoveMembers(_ chat: ChatConversation, selfAccount: String?) -> Bool {
        live(chat) && isOwner(chat, selfAccount: selfAccount)
    }

    /// Everyone but the owner leaves (the owner dismisses instead: nobody would own it otherwise).
    public static func canLeave(_ chat: ChatConversation, selfAccount: String?) -> Bool {
        live(chat) && selfAccount != nil && !isOwner(chat, selfAccount: selfAccount)
    }

    /// Owner and admins change the settings.
    public static func canEditSettings(_ chat: ChatConversation, selfUserId: Int?, selfAccount: String?) -> Bool {
        canRename(chat, selfUserId: selfUserId, selfAccount: selfAccount)
    }

    /// Admins and ownership are both the owner's alone.
    public static func canManageAdmins(_ chat: ChatConversation, selfAccount: String?) -> Bool {
        live(chat) && isOwner(chat, selfAccount: selfAccount)
    }
}

/// What the signed-in user may do to a group as a whole; all false for anything but a live group.
/// Ported from: lib/features/chat/presentation/providers/chat_group_providers.dart (`ChatGroupRights`)
public struct ChatGroupRights: Hashable, Sendable {
    public var rename = false, dismiss = false, addMembers = false, removeMembers = false
    public var leave = false, editSettings = false, manageAdmins = false

    public init() {}

    public init(_ chat: ChatConversation, selfUserId: Int?, selfAccount: String?) {
        rename = ChatGroupPolicy.canRename(chat, selfUserId: selfUserId, selfAccount: selfAccount)
        dismiss = ChatGroupPolicy.canDismiss(chat, selfAccount: selfAccount)
        addMembers = ChatGroupPolicy.canAddMembers(chat, selfUserId: selfUserId, selfAccount: selfAccount)
        removeMembers = ChatGroupPolicy.canRemoveMembers(chat, selfAccount: selfAccount)
        leave = ChatGroupPolicy.canLeave(chat, selfAccount: selfAccount)
        editSettings = ChatGroupPolicy.canEditSettings(chat, selfUserId: selfUserId, selfAccount: selfAccount)
        manageAdmins = ChatGroupPolicy.canManageAdmins(chat, selfAccount: selfAccount)
    }

    /// Whether a member's row offers any action.
    public var managesMembers: Bool { manageAdmins || removeMembers }
}
