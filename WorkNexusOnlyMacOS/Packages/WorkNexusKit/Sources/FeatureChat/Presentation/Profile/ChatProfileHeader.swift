/// Ported from: lib/features/chat/presentation/widgets/chat_profile_header.dart
import CoreDomain
import CoreUI
import SwiftUI

/// The top of a profile: a banner in the person's colour with their avatar over its edge, then name, handle and presence,
/// and their role.
struct ChatProfileHeader: View {
    @Environment(\.appTheme) private var theme
    let model: ChatShellModel; let userId: Int

    var body: some View {
        let users = model.users, user = users[userId], c = theme.colors
        let name = ChatShellLabels.userName(users, userId)
        let hue = chatNameHue(name, theme)
        let diameter = theme.sizes.control36 * 2.4
        VStack(spacing: theme.spacing.s6) {
            LinearGradient(colors: [hue.opacity(0.55), hue.opacity(0.18)], startPoint: .topLeading, endPoint: .bottomTrailing)
                .frame(height: diameter * 0.9)
                .overlay(alignment: .bottom) {
                    ChatAvatarView(name: name, style: ChatAvatarStyle(imageUrl: ChatShellLabels.avatarUrl(users, userId)),
                                   presence: user?.status.map { ChatPresence.from(status: $0) },
                                   verified: ChatShellLabels.verifiedBadge(users, userId), diameter: diameter)
                        .padding(theme.spacing.s4).background(Circle().fill(c.panel))
                        .offset(y: diameter / 2)
                }
                .padding(.bottom, diameter / 2)
            Text(name).font(theme.typography.title).foregroundStyle(c.tx).textSelection(.enabled).multilineTextAlignment(.center)
                .padding(.top, theme.spacing.s8).padding(.horizontal, theme.spacing.s24)
            if let user {
                HStack(spacing: theme.spacing.s6) {
                    Text(verbatim: "@" + user.account).foregroundStyle(c.tx2)
                    if let status = user.status {
                        let presence = ChatPresence.from(status: status)
                        Text(verbatim: "·").foregroundStyle(c.tx3)
                        Circle().fill(ChatAvatarView.presenceColor(presence, theme) ?? c.tx3)
                            .frame(width: theme.spacing.s8, height: theme.spacing.s8)
                        Text(ChatShellLabels.presenceLabel(presence))
                            .foregroundStyle(ChatAvatarView.presenceColor(presence, theme) ?? c.tx2)
                    }
                }
                .font(theme.typography.body)
                if let role = user.role, !role.isEmpty {
                    TintedPill(ChatShellLabels.roleLabel(role, serverNames: model.roleNames), tint: c.accent).padding(.top, theme.spacing.s2)
                }
            }
        }
    }
}
