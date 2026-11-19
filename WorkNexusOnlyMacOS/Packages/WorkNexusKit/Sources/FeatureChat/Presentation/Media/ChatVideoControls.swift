/// Ported from: lib/features/chat/presentation/widgets/chat_video_controls.dart
import AppKit
import CoreUI
import SwiftUI

/// The video viewer's bottom controls: a seek bar with times, play/pause, ±10 s, volume/mute, speed, loop and full screen.
struct ChatVideoControls: View {
    @Environment(\.appTheme) private var theme
    let player: ChatVideoPlayer
    let onToggleFullScreen: () -> Void

    var body: some View {
        let ink = theme.colors.onScrim
        VStack(spacing: theme.spacing.s4) {
            HStack(spacing: theme.spacing.s8) {
                Text(ChatVideoPlayer.format(player.position)).font(theme.typography.caption).foregroundStyle(ink)
                Slider(value: Binding(get: { min(player.position, max(player.duration, 1)) }, set: { player.seek(to: $0) }),
                       in: 0...max(player.duration, 1)).tint(theme.colors.accent).disabled(player.duration <= 0)
                Text(ChatVideoPlayer.format(player.duration)).font(theme.typography.caption).foregroundStyle(ink)
            }
            HStack(spacing: theme.spacing.s4) {
                ControlButton(icon: "gobackward.10", help: shellString("chatBack10", "Back 10 seconds")) { player.skip(by: -ChatVideoPlayer.seekStep) }
                ControlButton(icon: player.isPlaying ? "pause.fill" : "play.fill",
                              help: player.isPlaying ? shellString("chatPause", "Pause") : shellString("chatPlay", "Play")) { player.toggle() }
                ControlButton(icon: "goforward.10", help: shellString("chatForward10", "Forward 10 seconds")) { player.skip(by: ChatVideoPlayer.seekStep) }
                ControlButton(icon: player.volume == 0 ? "speaker.slash.fill" : "speaker.wave.2.fill",
                              help: player.volume == 0 ? shellString("chatUnmute", "Unmute") : shellString("chatMute", "Mute")) { player.toggleMute() }
                    .padding(.leading, theme.spacing.s8)
                Slider(value: Binding(get: { player.volume }, set: { player.setVolume($0) }), in: 0...1).frame(width: theme.sizes.dialogSm / 3)
                Spacer(minLength: 0)
                AppMenuButton(help: shellString("chatSpeed", "Speed"), items: {
                    ChatVideoPlayer.speeds.map { s in AppNativeMenu.Item("\(speed(s))x", checked: s == player.speed) { player.setSpeed(s) } }
                }) { Text("\(speed(player.speed))x").font(theme.typography.label).foregroundStyle(ink) }
                    .fixedSize()
                    .padding(.horizontal, theme.spacing.s8)
                ControlButton(icon: "repeat", help: shellString("chatLoop", "Loop"), selected: player.isLooping) { player.isLooping.toggle() }
                ControlButton(icon: "arrow.up.left.and.arrow.down.right", help: shellString("chatFullScreen", "Full screen"), action: onToggleFullScreen)
            }
        }
        .padding(.horizontal, theme.spacing.s16).padding(.vertical, theme.spacing.s8)
        .background(theme.colors.scrim.opacity(0.6))
    }

    private func speed(_ s: Double) -> String { s == s.rounded() ? String(format: "%.1f", s) : "\(s)" }
}

private struct ControlButton: View {
    @Environment(\.appTheme) private var theme
    let icon: String
    let help: String
    var selected = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: icon).font(.system(size: theme.sizes.icon16, weight: .medium))
                .foregroundStyle(selected ? theme.colors.accent : theme.colors.onScrim)
                .frame(width: theme.sizes.control32, height: theme.sizes.control32).contentShape(Rectangle())
        }
        .buttonStyle(.plain).help(help)
    }
}
