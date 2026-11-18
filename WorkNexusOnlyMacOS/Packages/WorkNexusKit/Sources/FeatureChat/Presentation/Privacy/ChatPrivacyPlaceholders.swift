import CoreUI
import SwiftUI

/// What the privacy mode shows in place of an avatar: a neutral face that says nothing about whose it is (a person, or
/// people for a group).
/// Ported from: lib/features/chat/presentation/widgets/chat_avatar.dart (`_Placeholder`)
struct ChatPrivacyAvatarFace: View {
    @Environment(\.appTheme) private var theme
    let group: Bool
    let side: CGFloat

    var body: some View {
        ZStack {
            theme.colors.panel2
            Image(systemName: group ? "person.2.fill" : "person.fill")
                .font(.system(size: side * (group ? 0.4 : 0.5))).foregroundStyle(theme.colors.tx3)
        }
    }
}

/// A chat avatar the privacy mode swaps for the plain placeholder while it hides names and avatars.
struct ChatPrivacyAvatar: View {
    @Environment(\.chatPrivacyHidden) private var hidden
    let avatar: ChatAvatarView
    var group = false

    var body: some View { avatar.privacyMasked(hidden.contains(.identity), group: group) }
}

/// The info panel's media preview with empty tiles: how many pictures there are, not what they show.
/// Ported from: lib/features/chat/presentation/widgets/chat_info_files_section.dart (`_HiddenMediaGrid`)
struct ChatHiddenMediaGrid: View {
    @Environment(\.appTheme) private var theme
    let count: Int
    var columns = 4

    var body: some View {
        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: theme.spacing.s4), count: columns), spacing: theme.spacing.s4) {
            ForEach(0..<count, id: \.self) { _ in ChatPrivacyCoverFill().aspectRatio(1, contentMode: .fit) }
        }
    }
}

/// A file row that names nothing: a blank badge and dots.
/// Ported from: lib/features/chat/presentation/widgets/chat_info_files_section.dart (`_HiddenFileRow`)
struct ChatHiddenFileRow: View {
    @Environment(\.appTheme) private var theme

    var body: some View {
        HStack(spacing: theme.spacing.s12) {
            ChatPrivacyCoverFill().frame(width: theme.sizes.control36 + theme.spacing.s4, height: theme.sizes.control36 + theme.spacing.s4)
            Text(chatPrivacyMaskText).font(theme.typography.body).foregroundStyle(theme.colors.tx2)
            Spacer(minLength: 0)
        }
        .padding(.vertical, theme.spacing.s6)
    }
}
