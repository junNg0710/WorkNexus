import CoreDomain
import Foundation

/// A member action the group's owner picks from a member's "…" menu.
enum ChatMemberAction: Hashable { case makeAdmin, removeAdmin, transferOwner, remove }

/// The group and category dialog open over the chat (one at a time; the category manager may sit under it).
enum ChatGroupDialog: Hashable {
    case rename(ChatConversation)
    case settings(ChatConversation)
    case addMembers(ChatConversation, members: Set<Int>)
    /// Leave the group, or dismiss it for everyone (its owner).
    case exit(ChatConversation, dismiss: Bool)
    case member(ChatConversation, userId: Int, action: ChatMemberAction)
    /// File a chat under a category.
    case category(ChatConversation)
    case renameCategory(String)
    case deleteCategory(String)
}

/// Group management and categories: each command delegates to one use case and reports a failure as a toast; the dialogs
/// close on `true`.
/// Ported from: lib/features/chat/presentation/providers/{chat_group_controller,chat_group_providers,chat_category_providers}.dart
/// and the result handling of chat_group_actions.dart, chat_member_menu_button.dart, chat_add_members_dialog.dart,
/// chat_category_actions.dart
extension ChatShellModel {
    /// The signed-in user's account on the chat server (the ZenTao handle until the user list knows it).
    var chatSelfAccount: String { selfUserId.flatMap { users[$0]?.account } ?? selfAccount }

    func groupRights(_ chat: ChatConversation) -> ChatGroupRights {
        ChatGroupRights(chat, selfUserId: selfUserId, selfAccount: chatSelfAccount)
    }

    // MARK: categories and the list filter

    /// The account's categories, A–Z, each with its unread count.
    var categories: [ChatCategory] { ListChatCategories()(conversations) }

    /// The filter the list applies: picked categories that no longer have chats drop out.
    var listFilter: ChatListFilter {
        guard !filter.categories.isEmpty else { return filter }
        var f = filter
        f.categories = f.categories.intersection(categories.map(\.name))
        return f
    }

    func toggleCategoryFilter(_ name: String) {
        if filter.categories.remove(name) == nil { filter.categories.insert(name) }
    }

    func setCategory(_ chat: ChatConversation, _ name: String) async -> Bool {
        succeeded(await SetChatCategory(repository)(chat, name))
    }

    /// Renames a category (every chat in it is refiled); the list's filter follows it to the new name.
    func renameCategory(_ from: String, to: String) async -> Bool {
        guard succeeded(await RenameChatCategory(repository)(accountId: accountId, chats: conversations, from: from, to: to)) else { return false }
        if filter.categories.remove(from) != nil { filter.categories.insert(to.trimmingCharacters(in: .whitespacesAndNewlines)) }
        return true
    }

    /// Deletes a category: its chats stay, uncategorised.
    func deleteCategory(_ name: String) async -> Bool {
        succeeded(await RenameChatCategory(repository)(accountId: accountId, chats: conversations, from: name, to: ""))
    }

    // MARK: groups

    func renameGroup(_ chat: ChatConversation, _ name: String) async -> Bool {
        succeeded(await RenameGroupChat(repository)(chat, name))
    }

    func updateGroupSettings(_ chat: ChatConversation, isPublic: Bool, adminInvite: Bool, committers: ChatCommitters) async -> Bool {
        succeeded(await UpdateGroupSettings(repository)(chat, isPublic: isPublic, adminInvite: adminInvite, committers: committers))
    }

    func addMembers(_ chat: ChatConversation, _ userIds: [Int]) async -> Bool {
        guard succeeded(await AddGroupMembers(repository)(chat, userIds)) else { return false }
        toasts.show(shellString("chatMembersAdded", "Members added"))
        await reloadMembers(of: chat)
        return true
    }

    /// Leaves the group, or dismisses it for everyone; either way it is gone from the list, so it is closed too.
    func exitGroup(_ chat: ChatConversation, dismiss: Bool) async -> Bool {
        let result = dismiss ? await DismissGroupChat(repository)(chat, selfAccount: chatSelfAccount)
                             : await LeaveGroupChat(repository)(chat, selfAccount: chatSelfAccount)
        guard succeeded(result) else { return false }
        toasts.show(dismiss ? shellString("chatGroupDismissed", "Group dismissed") : shellString("chatLeftGroup", "You left the group"))
        if selectedGid == chat.gid { select(nil) }
        return true
    }

    func run(_ action: ChatMemberAction, on userId: Int, in chat: ChatConversation) async -> Bool {
        let me = selfUserId, account = chatSelfAccount
        let result: Outcome<Void>
        switch action {
        case .makeAdmin, .removeAdmin:
            result = await SetGroupAdmin(repository)(chat, userId, admin: action == .makeAdmin, selfUserId: me, selfAccount: account)
        case .transferOwner: result = await TransferGroupOwnership(repository)(chat, userId, selfUserId: me, selfAccount: account)
        case .remove: result = await RemoveGroupMember(repository)(chat, userId, selfUserId: me, selfAccount: account)
        }
        guard succeeded(result) else { return false }
        switch action {
        case .remove:
            toasts.show(shellString("chatMemberRemoved", "Removed from the group"))
            await reloadMembers(of: chat)
        case .transferOwner: toasts.show(shellString("chatOwnerTransferred", "Group owner changed"))
        case .makeAdmin, .removeAdmin: break
        }
        return true
    }

    /// Members are fetched on demand, not stored: ask again.
    private func reloadMembers(of chat: ChatConversation) async {
        if let thread, thread.state.chatGid == chat.gid { await thread.reloadMembers() }
    }

    private func succeeded(_ result: Outcome<Void>) -> Bool {
        if case .failure(let f) = result { report(f); return false }
        return true
    }
}
