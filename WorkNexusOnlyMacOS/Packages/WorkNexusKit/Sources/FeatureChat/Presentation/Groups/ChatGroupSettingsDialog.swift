import CoreDomain
import CoreUI
import SwiftUI

/// A group's settings, for its owner and admins: public or not, whether only they add people, and who may post. Saved
/// together, as the official client does.
/// Ported from: lib/features/chat/presentation/widgets/chat_group_settings_dialog.dart
struct ChatGroupSettingsDialog: View {
    @Environment(\.appTheme) private var theme
    let model: ChatShellModel
    let chat: ChatConversation
    let onClose: () -> Void
    @State private var isPublic: Bool
    @State private var adminInvite: Bool
    @State private var scope: ChatSendScope
    @State private var picked: Set<Int>
    @State private var saving = false

    init(model: ChatShellModel, chat: ChatConversation, onClose: @escaping () -> Void) {
        self.model = model; self.chat = chat; self.onClose = onClose
        let committers = ChatCommitters.parse(chat.committers)
        _isPublic = State(initialValue: chat.isPublic)
        _adminInvite = State(initialValue: chat.adminInvite)
        _scope = State(initialValue: committers.scope)
        _picked = State(initialValue: committers.userIds)
    }

    private var canSave: Bool { !saving && (scope != .selected || !picked.isEmpty) }

    var body: some View {
        AppDialogFrame(title: shellString("chatGroupSettings", "Group settings"), maxWidth: theme.sizes.dialogMd, onClose: onClose) {
            VStack(alignment: .leading, spacing: theme.spacing.s12) {
                ChatSettingsCard {
                    ChatSwitchRow(label: shellString("chatPublicGroup", "Public group"),
                                  hint: shellString("chatPublicGroupHint", "Anyone can find this group and join it"), isOn: $isPublic)
                    // Anyone may join a public group: keeping invites to admins means nothing there, so it shows off and
                    // cannot be changed.
                    ChatSwitchRow(label: shellString("chatAdminInvite", "Only the owner and admins add members"),
                                  hint: shellString("chatAdminInviteHint", "Off: anyone who can post may add people"),
                                  isOn: Binding(get: { !isPublic && adminInvite }, set: { adminInvite = $0 }), enabled: !isPublic)
                }
                Text(shellString("chatWhoCanPost", "Who can send messages")).font(theme.typography.bodyStrong).foregroundStyle(theme.colors.tx)
                    .padding(.top, theme.spacing.s8)
                AppSegmentedTabs(ChatSendScope.allCases.map { s in AppSegmentedTab(label: Self.label(s), active: s == scope) { scope = s } })
                if scope == .selected {
                    Text(shellString("chatPostSelectedHint", "The owner can always post. Tick who else can:"))
                        .font(theme.typography.meta).foregroundStyle(theme.colors.tx2)
                    ChatCommitterPicker(model: model, chat: chat, picked: $picked)
                }
            }
            .padding(.horizontal, theme.spacing.s24).padding(.bottom, theme.spacing.s24)
        } actions: {
            Spacer(minLength: 0)
            AppButton(shellString("chatCancel", "Cancel"), kind: .ghost, action: onClose)
            AppButton(shellString("chatSave", "Save"), kind: .primary, action: save).disabled(!canSave)
        }
    }

    static func label(_ scope: ChatSendScope) -> String {
        switch scope {
        case .everyone: shellString("chatPostEveryone", "Everyone")
        case .admins: shellString("chatPostAdmins", "Admins only")
        case .selected: shellString("chatPostSelected", "Chosen members")
        }
    }

    private func save() {
        guard canSave else { return }
        saving = true
        Task {
            let ok = await model.updateGroupSettings(chat, isPublic: isPublic, adminInvite: adminInvite, committers: ChatCommitters(scope, picked))
            saving = false
            if ok { onClose() }
        }
    }
}

/// The group settings' list of members to tick: who may post when only chosen members may. The owner always may, so is
/// not listed.
/// Ported from: lib/features/chat/presentation/widgets/chat_committer_picker.dart
private struct ChatCommitterPicker: View {
    @Environment(\.appTheme) private var theme
    let model: ChatShellModel
    let chat: ChatConversation
    @Binding var picked: Set<Int>
    @State private var members: [Int]?
    @State private var failed = false

    var body: some View {
        Group {
            if let members {
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(members.filter { model.users[$0]?.account != chat.ownerAccount }, id: \.self) { id in
                            MemberTick(model: model, id: id, picked: picked.contains(id)) {
                                if picked.remove(id) == nil { picked.insert(id) }
                            }
                        }
                    }
                }
                .frame(maxHeight: theme.sizes.dialogSm * 0.6)
            } else if failed {
                AppStateView(.error(shellString("chatMembersFailed", "Couldn't load the members"))) { Task { await load() } }
            } else {
                AppStateView(.loading)
            }
        }
        .task { await load() }
    }

    private func load() async {
        failed = false
        switch await model.repository.members(accountId: model.accountId, chatGid: chat.gid) {
        case .success(let ids): members = ids
        case .failure: failed = true
        }
    }
}

private struct MemberTick: View {
    @Environment(\.appTheme) private var theme
    let model: ChatShellModel
    let id: Int
    let picked: Bool
    let onTap: () -> Void

    var body: some View {
        HoverSurface(onTap: onTap, selected: picked) {
            HStack(spacing: theme.spacing.s12) {
                ChatAvatarView(userId: id, users: model.users)
                Text(ChatShellLabels.userName(model.users, id)).font(theme.typography.bodyStrong).foregroundStyle(theme.colors.tx).lineLimit(1)
                Spacer(minLength: 0)
                Image(systemName: picked ? "checkmark.circle.fill" : "circle").font(.system(size: theme.sizes.icon18))
                    .foregroundStyle(picked ? theme.colors.accent : theme.colors.line2)
            }
            .padding(.horizontal, theme.spacing.s8).padding(.vertical, theme.spacing.s6)
        }
    }
}
