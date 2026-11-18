import CoreDomain
import CoreUI
import SwiftUI

/// Beside the chat: who the other person is (direct) or what the group is — owner, creation date, pinned messages, members
/// and shared files — as cards. For a group's owner and admins, a camera badge on the picture and a pencil beside the name
/// edit them, and "Group settings" opens its settings; at the bottom its owner dismisses it, anyone else leaves it.
/// Ported from: lib/features/chat/presentation/widgets/chat_info_panel.dart
struct ChatInfoPanel: View {
    @Environment(\.appTheme) private var theme
    @Environment(\.chatShellLayout) private var layout
    let model: ChatShellModel
    let session: ChatThreadSession

    var body: some View {
        let chat = session.state.chat, users = model.users
        let oneToOne = chat.type == .one2one
        let withPeer = oneToOne && !chat.isMyCloud
        let peer = withPeer ? chat.peerUserId.flatMap { users[$0] } : nil
        let title = ChatShellLabels.title(chat, users)
        let rights = model.groupRights(chat)
        ChatSidePanelFrame(title: shellString("chatInfo", "Chat info"),
                           onClose: layout.infoRoom ? nil : { session.state.closePanel() }) {
            ScrollView {
                VStack(spacing: 0) {
                    // Owner and admins change the picture, as for pinning.
                    ChatGroupAvatarEditor(editable: !oneToOne && PinChatMessage(model.repository).canPin(chat, selfUserId: model.selfUserId,
                                                                                                         selfAccount: model.chatSelfAccount),
                                          onEdit: { model.groupAvatarChat = chat }) {
                        ChatPrivacyAvatar(avatar: ChatAvatarView(chat: chat, title: title, users: users, diameter: theme.sizes.control36 * 2),
                                          group: !oneToOne)
                    }
                    ChatGroupTitleEditor(editable: rights.rename, onEdit: { model.groupDialog = .rename(chat) }) {
                        ChatPrivacyMasked(part: .identity, alignment: .center) {
                            Text(title).font(theme.typography.titleSm).foregroundStyle(theme.colors.tx).multilineTextAlignment(.center)
                                .textSelection(.enabled)
                        } mask: {
                            Text(chatPrivacyMaskText).font(theme.typography.titleSm).foregroundStyle(theme.colors.tx)
                        }
                    }
                    .padding(.top, theme.spacing.s12)
                    if let subtitle = subtitle(chat, peer) {
                        // The peer's @account names them as much as the title does; a count or a status stays.
                        ChatPrivacyText(text: subtitle, part: chatSubtitleNamesPeer(subtitle, peerAccount: nil) ? .identity : nil,
                                        font: theme.typography.meta, color: theme.colors.tx2)
                    }
                    ChatInfoDetails(chat: chat, peer: peer, users: users, roleNames: model.roleNames)
                        .padding(.top, theme.spacing.s20)
                    ChatPanelLink(icon: "pin", label: shellString("chatPinnedMessages", "Pinned messages"), count: chat.pinnedMessageIds.count) {
                        session.state.togglePanel(.pinned, infoRoom: layout.infoRoom)
                    }
                    if !oneToOne {
                        ChatPanelLink(icon: "person.2", label: shellString("chatMembersTitle", "Members"), count: session.memberCount) {
                            session.state.togglePanel(.members, infoRoom: layout.infoRoom)
                        }
                    }
                    if rights.editSettings {
                        ChatPanelLink(icon: "gearshape", label: shellString("chatGroupSettings", "Group settings"), count: nil) {
                            model.groupDialog = .settings(chat)
                        }
                    }
                    ChatInfoStorageCard(repository: model.repository, accountId: model.accountId, chatGid: chat.gid,
                                        onManage: model.events.onOpenStorage)
                    ChatInfoFilesSection(model: model, session: session)
                    if !oneToOne { ChatGroupExitButton(model: model, chat: chat) }
                }
                .padding(theme.spacing.s12)
            }
            // Pointing anywhere on the panel shows all of it while the privacy mode hides it.
            .chatPrivacyRevealRegion()
        }
    }

    private func subtitle(_ chat: ChatConversation, _ peer: ChatUser?) -> String? {
        if chat.isMyCloud { return shellString("chatMyCloudHint", "Notes, links and files you keep for yourself") }
        if chat.type != .one2one, let n = session.memberCount { return ChatShellLabels.memberCount(n) }
        if let status = peer?.status { return ChatShellLabels.presenceLabel(ChatPresence.from(status: status)) }
        return peer.map { "@\($0.account)" }
    }
}

/// The details card: the peer's role and contacts, or a group's owner and creation date.
private struct ChatInfoDetails: View {
    @Environment(\.appTheme) private var theme
    let chat: ChatConversation
    let peer: ChatUser?
    let users: [Int: ChatUser]
    let roleNames: [String: String]

    var body: some View {
        let rows = rows
        if !rows.isEmpty {
            ChatPanelCard {
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(rows.indices, id: \.self) { i in ChatDetailRow(icon: rows[i].icon, label: rows[i].label, value: rows[i].value, privacyPart: .identity).padding(.top, i == 0 ? 0 : theme.spacing.s12) }
                }
            }
        }
    }

    private var rows: [(icon: String, label: String, value: String)] {
        var out: [(String, String, String)] = []
        if let role = peer?.role, !role.isEmpty {
            out.append(("person.text.rectangle", shellString("chatRole", "Role"), ChatShellLabels.roleLabel(role, serverNames: roleNames)))
        }
        if let v = peer?.email { out.append(("envelope", shellString("chatEmail", "Email"), v)) }
        if let v = peer?.mobile { out.append(("iphone", shellString("chatMobile", "Mobile"), v)) }
        if let v = peer?.phone { out.append(("phone", shellString("chatPhone", "Phone"), v)) }
        if chat.type != .one2one, let owner = chat.ownerAccount {
            let name = users.values.first { $0.account == owner }?.realname
            out.append(("checkmark.shield", shellString("chatOwner", "Owner"), name ?? owner))
        }
        if chat.type != .one2one, let created = chat.createdAt {
            out.append(("calendar", shellString("chatCreatedOn", "Created"), created.formatted(date: .abbreviated, time: .omitted)))
        }
        return out
    }
}

/// One labelled detail; the value can be selected and copied.
/// Ported from: lib/features/chat/presentation/widgets/chat_detail_row.dart
struct ChatDetailRow: View {
    @Environment(\.appTheme) private var theme
    let icon: String, label: String, value: String
    /// Shows the value as dots while the privacy mode hides this part.
    var privacyPart: ChatPrivacyPart?

    var body: some View {
        HStack(alignment: .top, spacing: theme.spacing.s12) {
            Image(systemName: icon).font(.system(size: theme.sizes.icon16)).foregroundStyle(theme.colors.tx2)
                .frame(width: theme.sizes.icon20)
            VStack(alignment: .leading, spacing: 0) {
                Text(label).font(theme.typography.caption).foregroundStyle(theme.colors.tx2)
                // Every detail here names or places a person (a role, contacts, an owner, a date): dots while names hide.
                ChatPrivacyMasked(part: privacyPart) {
                    Text(value).font(theme.typography.body).foregroundStyle(theme.colors.tx).textSelection(.enabled)
                } mask: {
                    Text(chatPrivacyMaskText).font(theme.typography.body).foregroundStyle(theme.colors.tx)
                }
            }
            Spacer(minLength: 0)
        }
    }
}

/// A card that opens a sub-panel of the info: icon, label, count, chevron.
private struct ChatPanelLink: View {
    @Environment(\.appTheme) private var theme
    let icon: String, label: String, count: Int?, onTap: () -> Void

    var body: some View {
        HoverSurface(onTap: onTap, fill: theme.colors.panel, border: theme.colors.line, cornerRadius: theme.radii.lg) {
            HStack(spacing: theme.spacing.s12) {
                Image(systemName: icon).font(.system(size: theme.sizes.icon16)).foregroundStyle(theme.colors.accent).frame(width: theme.sizes.icon20)
                Text(label).font(theme.typography.bodyStrong).foregroundStyle(theme.colors.tx)
                Spacer(minLength: 0)
                if let count { Text("\(count)").font(theme.typography.bodyStrong).foregroundStyle(theme.colors.tx2) }
                Image(systemName: "chevron.right").font(.system(size: theme.sizes.icon14)).foregroundStyle(theme.colors.tx3)
            }
            .padding(.horizontal, theme.spacing.s12).padding(.vertical, theme.spacing.s10)
        }
        .padding(.bottom, theme.spacing.s8)
    }
}
