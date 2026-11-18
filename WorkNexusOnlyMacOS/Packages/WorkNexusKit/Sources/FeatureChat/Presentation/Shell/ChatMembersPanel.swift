import CoreDomain
import CoreUI
import SwiftUI

/// Beside the chat, opened from its info: the group's members (owner first), with role tabs above the list; for those who may,
/// "Add members" above them and, for the owner, each member's actions.
/// Ported from: lib/features/chat/presentation/widgets/chat_members_panel.dart + chat_member_list.dart
struct ChatMembersPanel: View {
    @Environment(\.appTheme) private var theme
    @Environment(\.chatShellLayout) private var layout
    let model: ChatShellModel
    let session: ChatThreadSession
    @State private var role: String?

    var body: some View {
        ChatSidePanelFrame(title: shellString("chatMembersTitle", "Members"),
                           onBack: { session.state.backToInfo(infoRoom: layout.infoRoom) },
                           onClose: { session.state.closePanel() }) {
            if let ids = session.memberIds {
                let users = model.users, chat = session.state.chat
                let rights = model.groupRights(chat)
                let ordered = Self.ownerFirst(ids, users: users, owner: chat.ownerAccount)
                VStack(spacing: 0) {
                    if rights.addMembers {
                        AppButton(shellString("chatAddMembers", "Add members"), systemImage: "person.badge.plus") {
                            model.groupDialog = .addMembers(chat, members: Set(ids))
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, theme.spacing.s12).padding(.top, theme.spacing.s8)
                    }
                    ChatRoleTabs(roles: ids.map { users[$0]?.role }, serverNames: model.roleNames, selected: $role)
                    ScrollView {
                        LazyVStack(spacing: 0) {
                            ForEach(ordered.filter { ChatShellLabels.roleMatches(role, users[$0]?.role) }, id: \.self) { id in
                                let owner = Self.isOwner(id, users, chat.ownerAccount)
                                MemberRow(model: model, id: id, owner: owner, admin: chat.adminIds.contains(id),
                                          menu: !owner && id != model.selfUserId && rights.managesMembers ? (chat, rights) : nil)
                            }
                        }
                        .padding(theme.spacing.s12)
                    }
                }
            } else if session.membersFailed {
                AppStateView(.error(shellString("chatMembersFailed", "Couldn't load the members"))) { Task { await session.loadMembers() } }
            } else {
                AppStateView(.loading)
            }
        }
        .task { await session.loadMembers() }
    }

    static func isOwner(_ id: Int, _ users: [Int: ChatUser], _ owner: String?) -> Bool { owner != nil && users[id]?.account == owner }

    /// The owner first, then the others in their order.
    static func ownerFirst(_ ids: [Int], users: [Int: ChatUser], owner: String?) -> [Int] {
        ids.filter { isOwner($0, users, owner) } + ids.filter { !isOwner($0, users, owner) }
    }
}

/// A member: avatar, name, account and role, an owner / admin pill and the owner's "…" menu; a tap opens their profile.
private struct MemberRow: View {
    @Environment(\.appTheme) private var theme
    let model: ChatShellModel
    let id: Int
    let owner: Bool
    let admin: Bool
    /// The group and the owner's rights, when the row offers the member's actions.
    let menu: (chat: ChatConversation, rights: ChatGroupRights)?

    /// "@account · Role".
    private var subtitle: String? {
        guard let user = model.users[id] else { return nil }
        var parts = ["@" + user.account]
        if let role = user.role?.trimmingCharacters(in: .whitespaces), !role.isEmpty {
            parts.append(ChatShellLabels.roleLabel(role, serverNames: model.roleNames))
        }
        return parts.joined(separator: " · ")
    }

    var body: some View {
        HoverSurface(onTap: { model.profileUserId = id }) {
            HStack(spacing: theme.spacing.s12) {
                ChatAvatarView(userId: id, users: model.users)
                VStack(alignment: .leading, spacing: 0) {
                    Text(ChatShellLabels.userName(model.users, id)).font(theme.typography.bodyStrong).foregroundStyle(theme.colors.tx).lineLimit(1)
                    if let subtitle { Text(subtitle).font(theme.typography.caption).foregroundStyle(theme.colors.tx2).lineLimit(1) }
                }
                Spacer(minLength: 0)
                if owner { TintedPill(shellString("chatOwner", "Owner"), tint: theme.colors.accent) }
                else if admin { TintedPill(shellString("chatAdminBadge", "Admin"), tint: theme.colors.violet) }
                if let menu { ChatMemberMenuButton(model: model, chat: menu.chat, userId: id, rights: menu.rights) }
            }
            .padding(.vertical, theme.spacing.s6).padding(.horizontal, theme.spacing.s4)
        }
    }
}

/// Tabs above a list of people: "All", then one per role among `roles`, most senior first, each with how many have it;
/// hidden when everyone shares one role.
/// Ported from: lib/features/chat/presentation/widgets/chat_role_tabs.dart
struct ChatRoleTabs: View {
    @Environment(\.appTheme) private var theme
    let roles: [String?]
    var serverNames: [String: String] = [:]
    @Binding var selected: String?

    var body: some View {
        let order = OrderChatRoles()(roles)
        if order.count > 1 {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: theme.spacing.s6) {
                    ChatTabChip(label: shellString("chatTabAll", "All"), selected: selected == nil, unread: 0) { selected = nil }
                    ForEach(order, id: \.self) { code in
                        ChatTabChip(label: code.isEmpty ? shellString("chatRoleNone", "No role") : ChatShellLabels.roleLabel(code, serverNames: serverNames),
                                    selected: selected == code, unread: roles.filter { ChatShellLabels.roleMatches(code, $0) }.count) { selected = code }
                    }
                }
                .padding(.horizontal, theme.spacing.s12)
            }
            .frame(height: ChatShellLayout.subHeaderHeight)
            .background(theme.colors.panel)
            .overlay(alignment: .bottom) { Rectangle().fill(theme.colors.line).frame(height: theme.borders.hairline) }
        }
    }
}
