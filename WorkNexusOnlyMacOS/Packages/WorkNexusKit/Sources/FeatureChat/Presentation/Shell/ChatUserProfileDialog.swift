import CoreDomain
import CoreUI
import SwiftUI

/// A user's profile: a banner in their colour with their picture, name, handle, presence and role; then Contact and Work
/// (chat's record completed by their ZenTao profile), the groups you share and their open bugs and tasks; and the actions —
/// message them, or for yourself change your picture / open your full profile.
/// Ported from: lib/features/chat/presentation/widgets/chat_user_profile_dialog.dart
struct ChatUserProfileDialog: View {
    @Environment(\.appTheme) private var theme
    @Environment(\.chatServices) private var services
    let model: ChatShellModel
    let userId: Int
    @State private var busy = false
    @State private var uploadStatus: (text: String, isError: Bool)?
    /// A picture picked for the avatar, waiting for its crop.
    @State private var cropping: Data?
    @State private var person = ChatProfileModel()

    var body: some View {
        if let cropping {
            ChatAvatarCropDialog(imageData: cropping, onApply: { crop in self.cropping = nil; Task { await upload(cropping, crop: crop) } },
                                 onCancel: { self.cropping = nil })
        } else {
            profile
        }
    }

    private var profile: some View {
        let user = model.users[userId], isSelf = userId == model.selfUserId
        return VStack(spacing: 0) {
            FitOrScroll(maxHeight: theme.sizes.dialogLg) {
                VStack(spacing: 0) {
                    ChatProfileHeader(model: model, userId: userId)
                    if let uploadStatus { AppInlineNote(uploadStatus.text, isError: uploadStatus.isError).padding(.top, theme.spacing.s12) }
                    VStack(alignment: .leading, spacing: 0) {
                        ChatProfileDetails(user: user, profile: person.profile)
                        if let groups = person.groups { ChatProfileGroups(model: model, groups: groups) }
                        ChatProfileTickets(model: model, tickets: person.tickets)
                    }
                    .padding(.horizontal, theme.spacing.s24).padding(.bottom, theme.spacing.s24)
                }
            }
            Divider().overlay(theme.colors.line)
            Actions(model: model, userId: userId, isSelf: isSelf, busy: $busy, onPicked: { cropping = $0 })
                .padding(.horizontal, theme.spacing.s24).padding(.vertical, theme.spacing.s16)
        }
        .frame(maxWidth: theme.sizes.dialogMd)
        .overlay(alignment: .topTrailing) {
            AppIconButton("xmark", help: appString("close", "Close")) { model.profileUserId = nil }.padding(theme.spacing.s12)
        }
        .clipShape(RoundedRectangle(cornerRadius: theme.radii.xl, style: .continuous))
        .appGlass(in: RoundedRectangle(cornerRadius: theme.radii.xl, style: .continuous), fallback: theme.colors.panel)
        .shadow(color: theme.colors.scrim.opacity(0.25), radius: theme.spacing.s24, y: theme.spacing.s8)
        .onExitCommand { model.profileUserId = nil }
        .accessibilityLabel(shellString("chatUserProfile", "Profile"))
        .task(id: userId) { await person.load(services: services, accountId: model.accountId, userId: userId, isSelf: isSelf) }
        .task(id: user?.account) { await person.watchTickets(services: services, accountId: model.accountId, handle: user?.account) }
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
        HStack(spacing: theme.spacing.s8) {
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
