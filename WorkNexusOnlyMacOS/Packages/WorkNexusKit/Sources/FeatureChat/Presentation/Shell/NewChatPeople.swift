import CoreDomain
import CoreUI
import SwiftUI

/// The people picker of the new-chat dialog: picked people as pills, a search box, role tabs and the users as rows with a tick.
/// Ported from: lib/features/chat/presentation/widgets/new_chat_people.dart
struct NewChatPeople: View {
    @Environment(\.appTheme) private var theme
    let model: ChatShellModel
    @Binding var search: String
    @Binding var selected: [Int]
    let loading: Bool
    let failed: Bool
    let onRetry: () -> Void
    @State private var role: String?

    var body: some View {
        let users = model.users
        let everyone = ChatPeople.everyone(users, selfId: model.selfUserId)
        let people = ChatPeople.filtered(everyone, role: role, query: search)
        VStack(alignment: .leading, spacing: theme.spacing.s8) {
            AppSearchField(text: $search, hint: shellString("chatSearchPeople", "Search people"), autofocus: true)
            if !selected.isEmpty {
                FlowLayout(spacing: theme.spacing.s6) {
                    ForEach(selected, id: \.self) { id in
                        PickedPill(name: ChatShellLabels.userName(users, id)) { selected.removeAll { $0 == id } }
                    }
                }
            }
            ChatRoleTabs(roles: everyone.map(\.role), serverNames: model.roleNames, selected: $role)
                .clipShape(RoundedRectangle(cornerRadius: theme.radii.md))
            if people.isEmpty && users.isEmpty && failed {
                AppStateView(.error(shellString("chatMembersFailed", "Couldn't load the members")), retry: onRetry)
            } else if people.isEmpty && users.isEmpty && loading {
                AppStateView(.loading)
            } else if people.isEmpty {
                AppStateView(.empty(shellString("chatNoPeople", "No one found")))
            } else {
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(people) { u in
                            PersonRow(user: u, roleNames: model.roleNames, picked: selected.contains(u.userId)) {
                                if let at = selected.firstIndex(of: u.userId) { selected.remove(at: at) } else { selected.append(u.userId) }
                            }
                        }
                    }
                }
            }
        }
    }
}

/// A picked person: name and a remove mark.
private struct PickedPill: View {
    @Environment(\.appTheme) private var theme
    let name: String
    let onRemove: () -> Void

    var body: some View {
        Button(action: onRemove) {
            HStack(spacing: theme.spacing.s4) {
                Text(name).font(theme.typography.metaStrong).foregroundStyle(theme.colors.accent).lineLimit(1)
                Image(systemName: "xmark").font(.system(size: theme.sizes.icon12)).foregroundStyle(theme.colors.accent)
            }
            .padding(.horizontal, theme.spacing.s10).padding(.vertical, theme.spacing.s4)
            .background(theme.colors.sel, in: Capsule())
        }
        .buttonStyle(.plain).help(shellString("chatUnpickPerson", "Remove {name}", ["name": name]))
    }
}

/// A user as a chat-list-like row with a round tick.
private struct PersonRow: View {
    @Environment(\.appTheme) private var theme
    let user: ChatUser
    let roleNames: [String: String]
    let picked: Bool
    let onTap: () -> Void

    var body: some View {
        HoverSurface(onTap: onTap, selected: picked) {
            HStack(spacing: theme.spacing.s12) {
                ChatAvatarView(name: ChatPeople.name(user), style: ChatAvatarStyle(imageUrl: user.avatarUrl),
                               presence: user.status.map { ChatPresence.from(status: $0) },
                               verified: chatRoleRank(of: user.role).map { ChatVerifiedBadge(rank: $0, role: user.role ?? "") })
                VStack(alignment: .leading, spacing: 0) {
                    Text(ChatPeople.name(user)).font(theme.typography.bodyStrong).foregroundStyle(theme.colors.tx).lineLimit(1)
                    Text("@" + user.account + (user.role.flatMap { $0.isEmpty ? nil : " · " + ChatShellLabels.roleLabel($0, serverNames: roleNames) } ?? ""))
                        .font(theme.typography.caption).foregroundStyle(theme.colors.tx2).lineLimit(1)
                }
                Spacer(minLength: 0)
                Image(systemName: picked ? "checkmark.circle.fill" : "circle").font(.system(size: theme.sizes.icon18))
                    .foregroundStyle(picked ? theme.colors.accent : theme.colors.line2)
            }
            .padding(.horizontal, theme.spacing.s8).padding(.vertical, theme.spacing.s6)
        }
    }
}
