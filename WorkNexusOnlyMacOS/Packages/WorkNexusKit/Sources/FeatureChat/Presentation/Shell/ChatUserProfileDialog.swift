import CoreDomain
import CoreUI
import SwiftUI

/// A user's profile: picture, name, account and presence, role, contacts, and the actions — message them, or for yourself
/// change your picture / open your full profile.
/// Ported from: lib/features/chat/presentation/widgets/chat_user_profile_dialog.dart
struct ChatUserProfileDialog: View {
    @Environment(\.appTheme) private var theme
    let model: ChatShellModel
    let userId: Int
    @State private var busy = false
    @State private var uploadStatus: (text: String, isError: Bool)?
    /// A picture picked for the avatar, waiting for its crop.
    @State private var cropping: Data?

    var body: some View {
        if let cropping {
            ChatAvatarCropDialog(imageData: cropping, onApply: { crop in self.cropping = nil; Task { await upload(cropping, crop: crop) } },
                                 onCancel: { self.cropping = nil })
        } else {
            profile
        }
    }

    private var profile: some View {
        let users = model.users, user = users[userId], isSelf = userId == model.selfUserId
        return AppDialogFrame(title: shellString("chatUserProfile", "Profile"), maxWidth: theme.sizes.dialogSm, onClose: { model.profileUserId = nil }) {
            FitOrScroll(maxHeight: theme.sizes.dialogLg) {
                VStack(spacing: theme.spacing.s8) {
                    ChatAvatarView(userId: userId, users: users, diameter: theme.sizes.control36 * 2)
                    Text(ChatShellLabels.userName(users, userId)).font(theme.typography.titleSm).foregroundStyle(theme.colors.tx).textSelection(.enabled)
                    if let user {
                        Text(([("@" + user.account)] + (user.status.map { [ChatShellLabels.presenceLabel(ChatPresence.from(status: $0))] } ?? [])).joined(separator: "  ·  "))
                            .font(theme.typography.meta).foregroundStyle(theme.colors.tx2)
                        if let role = user.role, !role.isEmpty {
                            TintedPill(ChatShellLabels.roleLabel(role, serverNames: model.roleNames), tint: theme.colors.accent)
                        }
                        VStack(alignment: .leading, spacing: theme.spacing.s12) {
                            if let v = user.email { ChatDetailRow(icon: "envelope", label: shellString("chatEmail", "Email"), value: v) }
                            if let v = user.mobile { ChatDetailRow(icon: "iphone", label: shellString("chatMobile", "Mobile"), value: v) }
                            if let v = user.phone { ChatDetailRow(icon: "phone", label: shellString("chatPhone", "Phone"), value: v) }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading).padding(.top, theme.spacing.s8)
                    }
                    if let uploadStatus { AppInlineNote(uploadStatus.text, isError: uploadStatus.isError) }
                    Actions(model: model, userId: userId, isSelf: isSelf, busy: $busy, onPicked: { cropping = $0 })
                        .padding(.top, theme.spacing.s16)
                }
                .padding(.horizontal, theme.spacing.s24).padding(.bottom, theme.spacing.s24)
            }
        }
    }
}

extension ChatUserProfileDialog {
    /// Uploads the cropped picture as your avatar and reports how it went above the buttons.
    fileprivate func upload(_ image: Data, crop: ChatAvatarCrop?) async {
        busy = true; uploadStatus = (shellString("chatMyAvatarUploading", "Uploading your picture…"), false)
        switch await model.setMyAvatar(image, crop: crop) {
        case .success: uploadStatus = (shellString("chatMyAvatarUpdated", "Your picture was updated"), false)
        case .failure(let f): uploadStatus = (shellString("chatMyAvatarFailed", "Couldn't update your picture: {reason}", ["reason": f.message]), true)
        }
        busy = false
    }
}

private struct Actions: View {
    @Environment(\.appTheme) private var theme
    let model: ChatShellModel
    let userId: Int
    let isSelf: Bool
    @Binding var busy: Bool
    let onPicked: (Data) -> Void

    var body: some View {
        VStack(spacing: theme.spacing.s8) {
            if isSelf {
                if let open = model.events.onViewProfile {
                    AppButton(shellString("chatViewFullProfile", "View profile"), systemImage: "person") { model.profileUserId = nil; open(model.accountId) }
                }
                AppButton(shellString("chatChangeMyAvatar", "Change your picture"), systemImage: "camera") {
                    if let image = model.pickImageData() { onPicked(image) }
                }
                .disabled(busy)
            } else {
                AppButton(shellString("chatSendMessage", "Message"), systemImage: "message", kind: .primary) {
                    busy = true
                    Task { await model.openDirectChat(userId: userId); busy = false; model.profileUserId = nil }
                }
                .disabled(busy)
            }
        }
    }
}
