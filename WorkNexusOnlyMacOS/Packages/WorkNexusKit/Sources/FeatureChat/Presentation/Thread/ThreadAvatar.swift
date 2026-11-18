/// Ported from: lib/features/chat/presentation/widgets/chat_avatar.dart + message_avatar_slot.dart + chat_typing_avatars.dart
import CoreDomain
import CoreUI
import SwiftUI

/// A user's avatar: their picture, else initials on a colour that is the same for the same name; circle or rounded
/// square, with a "verified" check in the colour of their rank.
struct ThreadAvatar: View {
    @Environment(\.appTheme) private var theme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let name: String
    let imageUrl: String?
    var shape: ChatAvatarShape = .circle
    var diameter: CGFloat = 32
    var verifiedRank: ChatRoleRank?
    /// The privacy mode hides who sent it: a plain placeholder covers the face (still loaded underneath).
    var masked = false

    var body: some View {
        ZStack(alignment: .bottomTrailing) {
            face
                .overlay {
                    ZStack { if masked { ChatPrivacyAvatarFace(group: false, side: diameter).transition(.opacity) } }
                        .animation(ChatPrivacyMotion.ease(reduced: reduceMotion), value: masked)
                }
                .frame(width: diameter, height: diameter).clipShape(clip)
            if let verifiedRank, !masked {
                Image(systemName: "checkmark.seal.fill")
                    .font(.system(size: max(10, diameter * 0.36)))
                    .foregroundStyle(color(for: verifiedRank))
                    .background(Circle().fill(theme.colors.card).padding(2))
                    .offset(x: diameter * 0.1, y: diameter * 0.1)
            }
        }
        .frame(width: diameter, height: diameter)
    }

    private var clip: AnyShape {
        shape == .circle ? AnyShape(Circle()) : AnyShape(RoundedRectangle(cornerRadius: diameter * 0.12))
    }

    private var face: some View {
        ZStack {
            tint
            Text(initials).font(.system(size: diameter * 0.4, weight: .semibold)).foregroundStyle(theme.colors.onColorInk)
            if let imageUrl, let url = URL(string: imageUrl) {
                AsyncImage(url: url) { $0.resizable().scaledToFill() } placeholder: { Color.clear }
            }
        }
    }

    private var initials: String {
        let words = name.split(whereSeparator: { $0 == " " || $0 == "_" || $0 == "-" }).prefix(2)
        let letters = words.compactMap { $0.first.map { String($0).uppercased() } }.joined()
        return letters.isEmpty ? "?" : letters
    }

    /// A stable hue per name.
    private var tint: Color {
        let h = name.unicodeScalars.reduce(5381) { ($0 &* 33) &+ Int($1.value) }
        return Color(hue: Double(abs(h) % 360) / 360, saturation: 0.45, brightness: theme.colors.isDark ? 0.8 : 0.9)
    }

    private func color(for rank: ChatRoleRank) -> Color {
        switch rank {
        case .lead: theme.colors.accent
        case .manager: theme.colors.violet
        case .executive: theme.colors.amber
        }
    }
}

/// The column beside a run of messages that holds the sender's avatar: as wide as the avatar on every message, so bubbles
/// line up, with the avatar itself only where the style puts it (`visible`).
struct MessageAvatarSlot: View {
    @Environment(\.chatPrivacyHidden) private var hidden
    let ctx: ThreadContext
    let senderId: Int
    let name: String
    let style: ChatStyle
    let visible: Bool

    var body: some View {
        Group {
            if visible {
                Button { ctx.actions.openProfile(senderId) } label: {
                    ThreadAvatar(name: name, imageUrl: ctx.users[senderId]?.avatarUrl, shape: style.avatarShape,
                                 diameter: style.avatarSize, verifiedRank: chatRoleRank(of: ctx.users[senderId]?.role),
                                 masked: hidden.contains(.identity))
                }
                .buttonStyle(.plain)
                .help(name)
            } else {
                Color.clear
            }
        }
        .frame(width: style.avatarSize, height: visible ? style.avatarSize : 0, alignment: .top)
        .frame(width: style.avatarSize)
    }
}
