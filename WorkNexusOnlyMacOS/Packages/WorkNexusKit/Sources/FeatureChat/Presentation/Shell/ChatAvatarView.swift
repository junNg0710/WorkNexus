import CoreDomain
import CoreUI
import SwiftUI

/// The "verified" check beside a leading role's avatar: the colour of its rank and the role (for the tooltip).
struct ChatVerifiedBadge: Equatable { var rank: ChatRoleRank; var role: String }

extension ChatShellLabels {
    /// The "verified" check of a user's role; nil for engineers, "others" and unknown roles.
    static func verifiedBadge(_ users: [Int: ChatUser], _ id: Int?) -> ChatVerifiedBadge? {
        guard let id, let role = users[id]?.role?.trimmingCharacters(in: .whitespaces), let rank = chatRoleRank(of: role) else { return nil }
        return ChatVerifiedBadge(rank: rank, role: role)
    }
}

/// A round avatar: the user's picture when they have one, else their initials (or a group's text/glyph), with an optional
/// presence dot and "verified" check.
/// Ported from: lib/features/chat/presentation/widgets/chat_avatar.dart
struct ChatAvatarView: View {
    enum Size { case small, medium, large }

    @Environment(\.appTheme) private var theme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let name: String
    var style = ChatAvatarStyle()
    var presence: ChatPresence?
    var verified: ChatVerifiedBadge?
    var size: Size = .medium
    /// Exact size; overrides `size`.
    var diameter: CGFloat?
    /// The privacy mode hides who this is: a plain placeholder covers the picture (see `privacyMasked`).
    private(set) var masked = false
    private(set) var maskedGroup = false

    init(name: String, style: ChatAvatarStyle = ChatAvatarStyle(), presence: ChatPresence? = nil,
         verified: ChatVerifiedBadge? = nil, size: Size = .medium, diameter: CGFloat? = nil) {
        self.name = name; self.style = style; self.presence = presence; self.verified = verified
        self.size = size; self.diameter = diameter
    }

    /// For a user: their picture, presence and check.
    init(userId: Int, users: [Int: ChatUser], size: Size = .medium, diameter: CGFloat? = nil, showPresence: Bool = true) {
        self.init(name: ChatShellLabels.userName(users, userId), style: ChatAvatarStyle(imageUrl: ChatShellLabels.avatarUrl(users, userId)),
                  presence: showPresence ? ChatShellLabels.presence(users, userId) : nil,
                  verified: ChatShellLabels.verifiedBadge(users, userId), size: size, diameter: diameter)
    }

    /// For a conversation: My Cloud's glyph, the peer's picture or the group's avatar; the peer's presence and check.
    init(chat: ChatConversation, title: String, users: [Int: ChatUser], size: Size = .medium, diameter: CGFloat? = nil) {
        let withPeer = chat.type == .one2one && !chat.isMyCloud
        self.init(name: title, style: ChatShellLabels.avatarStyle(chat, users),
                  presence: withPeer ? ChatShellLabels.presence(users, chat.peerUserId) : nil,
                  verified: withPeer ? ChatShellLabels.verifiedBadge(users, chat.peerUserId) : nil, size: size, diameter: diameter)
    }

    private var side: CGFloat {
        if let diameter { return diameter }
        switch size {
        case .small: return theme.sizes.control32
        case .medium: return theme.sizes.control36 + theme.spacing.s4
        case .large: return theme.sizes.control36 + theme.spacing.s8
        }
    }

    /// This avatar with the privacy mode's placeholder over it while `masked` (people for a `group`, else a person); the
    /// presence dot stays, the "verified" check (a rank) goes.
    func privacyMasked(_ masked: Bool, group: Bool = false) -> ChatAvatarView {
        var copy = self
        copy.masked = masked; copy.maskedGroup = group
        return copy
    }

    var body: some View {
        picture
            // Over the picture, which stays loaded underneath: pointing at it shows it again without a reload.
            .overlay {
                ZStack { if masked { ChatPrivacyAvatarFace(group: maskedGroup, side: side).transition(.opacity) } }
                    .animation(ChatPrivacyMotion.ease(reduced: reduceMotion), value: masked)
            }
            .frame(width: side, height: side).clipShape(Circle())
            .overlay(alignment: .bottomTrailing) { presenceDot }
            .overlay(alignment: .topTrailing) { verifiedCheck }
    }

    private var picture: some View {
        ZStack {
            AvatarFill(name: name, style: style, side: side)
            if let url = style.imageUrl.flatMap(URL.init(string:)), !(style.imageUrl ?? "").isEmpty {
                AsyncImage(url: url) { $0.resizable().scaledToFill() } placeholder: { Color.clear }
            }
        }
    }

    @ViewBuilder private var presenceDot: some View {
        if let color = Self.presenceColor(presence, theme) {
            let dot = min(max(side * 0.3, theme.spacing.s10), theme.spacing.s14)
            Circle().fill(color).frame(width: dot, height: dot)
                .overlay(Circle().stroke(theme.colors.panel, lineWidth: dot * 0.18))
                .offset(x: dot * 0.1, y: dot * 0.1)
        }
    }

    @ViewBuilder private var verifiedCheck: some View {
        if let verified, !masked {
            let check = min(max(side * 0.36, theme.spacing.s12), theme.sizes.icon20)
            Image(systemName: "checkmark.seal.fill").font(.system(size: check))
                .foregroundStyle(Self.rankColor(verified.rank, theme))
                .background(Circle().fill(theme.colors.onScrim).frame(width: check * 0.5, height: check * 0.5))
                .offset(x: check * 0.15, y: -check * 0.15)
                .help(ChatShellLabels.roleLabel(verified.role))
        }
    }

    /// The colour of a presence dot; nil when nothing shows (offline or unknown).
    static func presenceColor(_ p: ChatPresence?, _ theme: AppTheme) -> Color? {
        switch p {
        case .online: theme.colors.green
        case .away: theme.colors.amber
        case .busy: theme.colors.red
        case .meeting: theme.colors.violet
        case .offline, nil: nil
        }
    }

    static func rankColor(_ rank: ChatRoleRank, _ theme: AppTheme) -> Color {
        switch rank { case .lead: theme.colors.accent; case .manager: theme.colors.amber; case .executive: theme.colors.violet }
    }
}

/// The avatar's background and text: a glyph on the accent, a group's text on its colour, or initials on a hue of their own.
private struct AvatarFill: View {
    @Environment(\.appTheme) private var theme
    let name: String; let style: ChatAvatarStyle; let side: CGFloat

    var body: some View {
        if let icon = style.systemIcon {
            ZStack {
                theme.colors.accent
                Image(systemName: icon).font(.system(size: side * 0.5)).foregroundStyle(theme.colors.accentTx)
            }
        } else if let bg = style.background, let label = style.label, !label.trimmingCharacters(in: .whitespaces).isEmpty {
            ZStack { Color(argb: 0xFF00_0000 | bg); AvatarText(text: label.trimmingCharacters(in: .whitespaces), ink: theme.colors.accentTx, side: side) }
        } else {
            let hue = Self.hue(name, theme)
            ZStack {
                theme.colors.panel
                hue.opacity(0.22)
                AvatarText(text: style.label.flatMap { $0.isEmpty ? nil : $0 } ?? initials, ink: hue, side: side)
            }
        }
    }

    /// Two letters don't fit a tiny avatar: it shows one.
    private var initials: String {
        let full = ChatShellLabels.initials(name)
        return side < theme.sizes.control32 ? String(full.prefix(1)) : full
    }

    /// One of the theme's colours, picked by a stable hash of the name.
    static func hue(_ name: String, _ theme: AppTheme) -> Color {
        let hues = [theme.colors.accent, theme.colors.green, theme.colors.amber, theme.colors.violet, theme.colors.orange, theme.colors.red]
        var hash = 0
        for unit in name.utf16 { hash = (hash &* 31 &+ Int(unit)) & 0x7fff_ffff }
        return hues[hash % hues.count]
    }
}

private struct AvatarText: View {
    @Environment(\.appTheme) private var theme
    let text: String; let ink: Color; let side: CGFloat

    var body: some View {
        Text(text).font(.system(size: side * (side < theme.sizes.control32 ? 0.5 : 0.4), weight: .semibold)).foregroundStyle(ink).lineLimit(1)
    }
}
