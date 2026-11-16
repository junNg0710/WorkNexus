/// Ported from: lib/features/chat/presentation/widgets/{chat_video_tile_parts,chat_video_overlays}.dart
import CoreDomain
import CoreUI
import SwiftUI

/// The round dark disc the play / spinner / progress controls sit in.
struct ChatVideoDisc<Content: View>: View {
    @Environment(\.appTheme) private var theme
    @ViewBuilder let content: Content
    var body: some View {
        content.frame(width: theme.sizes.control36 + theme.spacing.s12, height: theme.sizes.control36 + theme.spacing.s12)
            .background(theme.colors.scrim.opacity(0.55), in: Circle())
    }
}

/// A small round button in a corner of the frame.
struct ChatVideoCornerButton: View {
    @Environment(\.appTheme) private var theme
    let icon: String
    let help: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: icon).font(.system(size: theme.sizes.icon14, weight: .medium)).foregroundStyle(theme.colors.onScrim)
                .frame(width: theme.sizes.control32 - theme.spacing.s4, height: theme.sizes.control32 - theme.spacing.s4)
                .background(theme.colors.scrim.opacity(0.55), in: Circle())
        }
        .buttonStyle(.plain).help(help)
    }
}

/// The file's name and size along the top of the frame, on a fade so they read over any picture.
struct ChatVideoNameBar: View {
    @Environment(\.appTheme) private var theme
    let name: String
    let size: Int

    var body: some View {
        HStack(spacing: theme.spacing.s8) {
            Text(name).lineLimit(1)
            Spacer(minLength: 0)
            Text(AttachmentActions.byteCount(size))
        }
        .font(theme.typography.caption).foregroundStyle(theme.colors.onScrim)
        .padding(.horizontal, theme.spacing.s10).padding(.vertical, theme.spacing.s8)
        .background(LinearGradient(colors: [theme.colors.scrim.opacity(0.55), .clear], startPoint: .top, endPoint: .bottom))
    }
}

/// The length bottom-left, or "position / length" while it plays.
struct ChatVideoTimeCorner: View {
    @Environment(\.appTheme) private var theme
    let player: ChatVideoPlayer?
    let duration: TimeInterval?

    var body: some View {
        let text: String? = {
            if let player, player.duration > 0 { return "\(ChatVideoPlayer.format(player.position)) / \(ChatVideoPlayer.format(player.duration))" }
            return duration.map(ChatVideoPlayer.format)
        }()
        if let text {
            Text(text).font(theme.typography.caption).foregroundStyle(theme.colors.onScrim)
                .padding(.horizontal, theme.spacing.s8).padding(.vertical, theme.spacing.s2)
                .background(theme.colors.scrim.opacity(0.55), in: Capsule())
        }
    }
}

/// A thin line along the bottom of the frame: how far the video has played.
struct ChatVideoProgressLine: View {
    @Environment(\.appTheme) private var theme
    let player: ChatVideoPlayer

    var body: some View {
        GeometryReader { geo in
            let ratio = player.duration > 0 ? min(max(player.position / player.duration, 0), 1) : 0
            ZStack(alignment: .leading) {
                theme.colors.onScrim.opacity(0.25)
                theme.colors.accent.frame(width: geo.size.width * ratio)
            }
        }
        .frame(height: theme.spacing.s2)
    }
}

/// What sits in the middle of an unplayed frame: play (a sent video), the upload's progress, or a spinner while it opens.
struct ChatVideoCentreControl: View {
    @Environment(\.appTheme) private var theme
    let canPlay: Bool
    let starting: Bool
    let playing: ChatVideoPlayer?
    let downloadProgress: Double?

    var body: some View {
        if let playing {
            if !playing.isPlaying {
                ChatVideoDisc { Image(systemName: "play.fill").font(.system(size: theme.sizes.icon20)).foregroundStyle(theme.colors.onScrim) }
            }
        } else if starting {
            ChatVideoDisc { ProgressView().controlSize(.small).tint(theme.colors.onScrim) }
        } else if canPlay {
            ChatVideoDisc { Image(systemName: "play.fill").font(.system(size: theme.sizes.icon20)).foregroundStyle(theme.colors.onScrim) }
        }
    }
}
