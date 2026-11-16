/// Ported from: lib/features/chat/presentation/widgets/chat_floating_video.dart
import CoreUI
import SwiftUI

/// The playing video of the open chat, floating over the message list while its message is scrolled out of view: top-left at
/// first, dragged anywhere in the list; a click pauses / resumes and × stops it. Leaving the chat stops it too.
struct ChatFloatingVideo: View {
    @Environment(\.appTheme) private var theme
    let model: ChatVideoPlaybackModel
    /// Width of the mini player (a portrait video's is narrower).
    private static let width: CGFloat = 240
    /// Top-left corner in the list; nil is the default spot, just inside the top-left corner.
    @State private var at: CGPoint?
    @State private var dragStart: CGPoint?

    var body: some View {
        if let playing = model.current, playing.floating {
            let player = playing.player
            // Portrait to landscape, never a sliver or a banner.
            let aspect = min(max(player.aspectRatio ?? 16.0 / 9, 9.0 / 16), 16.0 / 9)
            let size = aspect < 1 ? CGSize(width: Self.width * 0.6, height: Self.width * 0.6 / aspect) : CGSize(width: Self.width, height: Self.width / aspect)
            GeometryReader { box in
                let origin = clamp(at ?? CGPoint(x: theme.spacing.s10, y: theme.spacing.s10), size, box.size)
                MiniPlayer(player: player) { model.stop() }
                    .frame(width: size.width, height: size.height)
                    .offset(x: origin.x, y: origin.y)
                    .gesture(DragGesture(minimumDistance: 4).onChanged { v in
                        if dragStart == nil { dragStart = origin }
                        at = clamp(CGPoint(x: (dragStart?.x ?? 0) + v.translation.width, y: (dragStart?.y ?? 0) + v.translation.height), size, box.size)
                    }.onEnded { _ in dragStart = nil })
            }
        }
    }

    private func clamp(_ p: CGPoint, _ size: CGSize, _ box: CGSize) -> CGPoint {
        CGPoint(x: min(max(p.x, 0), max(0, box.width - size.width)), y: min(max(p.y, 0), max(0, box.height - size.height)))
    }
}

/// The mini player itself: the video with a soft shadow, play while paused, × top-right and a thin progress line.
private struct MiniPlayer: View {
    @Environment(\.appTheme) private var theme
    let player: ChatVideoPlayer
    let onClose: () -> Void

    var body: some View {
        ZStack {
            theme.colors.scrim
            ChatPlayerSurface(player: player.player)
            Color.clear.contentShape(Rectangle()).onTapGesture { player.toggle() }
            if !player.isPlaying {
                ChatVideoDisc { Image(systemName: "play.fill").font(.system(size: theme.sizes.icon20)).foregroundStyle(theme.colors.onScrim) }.allowsHitTesting(false)
            }
            VStack(spacing: 0) {
                HStack { Spacer(); ChatVideoCornerButton(icon: "xmark", help: appString("close", "Close"), action: onClose) }
                    .padding(.top, theme.spacing.s6).padding(.trailing, theme.spacing.s6)
                Spacer()
                ChatVideoProgressLine(player: player)
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: theme.radii.lg))
        .shadow(color: theme.colors.scrim.opacity(0.35), radius: theme.spacing.s16, y: theme.spacing.s4)
        .help(shellString("chatPlay", "Play"))
    }
}
