/// Ported from: lib/features/chat/presentation/widgets/{chat_profile_groups,chat_profile_tickets}.dart
import CoreDomain
import CoreUI
import SwiftUI

/// The groups the signed-in user shares with the person, most recently active first; each opens its chat.
struct ChatProfileGroups: View {
    @Environment(\.appTheme) private var theme
    let model: ChatShellModel; let groups: ChatProfileModel.Load<[ChatConversation]>

    var body: some View {
        ChatProfileSection(title: shellString("chatProfileSharedGroups", "Groups in common"), count: groups.value?.count) {
            switch groups {
            case .loading: ChatProfileLoadingRows()
            case .failed: ChatProfileNote(text: shellString("chatProfileLoadFailed", "Couldn't load this right now"), isError: true)
            case .loaded(let list) where list.isEmpty: ChatProfileNote(text: shellString("chatProfileNoGroups", "No groups in common"))
            case .loaded(let list):
                ChatProfileExpandable(count: list.count) { i in
                    let chat = list[i]
                    HoverSurface(onTap: { model.profileUserId = nil; model.select(chat.gid) }, cornerRadius: theme.radii.md) {
                        HStack(spacing: theme.spacing.s12) {
                            ChatAvatarView(chat: chat, title: chat.name, users: model.users, diameter: theme.sizes.control32)
                            Text(chat.name).font(theme.typography.bodyStrong).foregroundStyle(theme.colors.tx).lineLimit(1)
                            Spacer(minLength: 0)
                            Image(systemName: "chevron.right").font(.system(size: theme.sizes.icon12)).foregroundStyle(theme.colors.tx3)
                        }
                        .padding(.vertical, theme.spacing.s4).padding(.horizontal, theme.spacing.s4)
                    }
                    .help(shellString("chatProfileOpenGroup", "Open {name}", ["name": chat.name]))
                }
            }
        }
    }
}

/// The person's open synced bugs and tasks: assigned to them, then reported by them; each opens in the detail panel.
/// Hidden when there are none.
struct ChatProfileTickets: View {
    @Environment(\.appTheme) private var theme
    @Environment(\.chatServices) private var services
    let model: ChatShellModel; let tickets: PersonTickets

    var body: some View {
        if tickets.count > 0 {
            ChatProfileSection(title: shellString("chatProfileOpenWork", "Open work"), count: tickets.count) {
                group(shellString("chatProfileAssigned", "Assigned"), tickets.assigned)
                group(shellString("chatProfileReported", "Reported"), tickets.reported)
            }
        }
    }

    @ViewBuilder private func group(_ title: String, _ list: [Ticket]) -> some View {
        if !list.isEmpty {
            Text(verbatim: "\(title) · \(list.count)").font(theme.typography.metaStrong).foregroundStyle(theme.colors.tx2)
                .padding(.top, theme.spacing.s4)
            ChatProfileExpandable(count: list.count) { i in ChatProfileTicketRow(ticket: list[i]) { open(list[i]) } }
        }
    }

    private func open(_ ticket: Ticket) {
        model.profileUserId = nil
        services?.openTicket?(ticket)
    }
}

private struct ChatProfileTicketRow: View {
    @Environment(\.appTheme) private var theme
    let ticket: Ticket; let onTap: () -> Void

    var body: some View {
        let c = theme.colors
        let bug = (ticket.externalType ?? "").lowercased() == "bug"
        HoverSurface(onTap: onTap, cornerRadius: theme.radii.md) {
            HStack(spacing: theme.spacing.s10) {
                ChatProfileIcon(systemImage: bug ? "ladybug" : "checklist", tint: bug ? c.red : c.green)
                Text(verbatim: "#\(ticket.externalKey)").font(theme.typography.mono).foregroundStyle(c.tx3)
                Text(ticket.title).font(theme.typography.body).foregroundStyle(c.tx).lineLimit(1)
                Spacer(minLength: theme.spacing.s4)
                TintedPill(statusLabel(ticket.status), tint: c.statusColor(ticket.status))
            }
            .padding(.vertical, theme.spacing.s2).padding(.horizontal, theme.spacing.s4)
        }
        .help(ticket.title)
    }
}
