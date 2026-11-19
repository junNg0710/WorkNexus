import SwiftUI

/// Ported from: lib/core/widgets/video/video_control_bar.dart
/// The row under a video: play/pause, -10 s / +10 s, volume, the time, then speed, loop and expand.
struct VideoControlBar: View {
    @Environment(\.appTheme) private var theme
    let model: AppVideoPlayerModel
    let expanded: Bool
    let onToggleExpand: () -> Void

    var body: some View {
        HStack(spacing: theme.spacing.s2) {
            AppIconButton(model.isPlaying ? "pause.fill" : "play.fill",
                          help: model.isPlaying ? appString("videoPause", "Pause (Space)") : appString("videoPlay", "Play (Space)")) { model.togglePlay() }
            AppIconButton("gobackward.10", help: appString("videoBack10", "Back 10 seconds (←)")) { model.seek(by: -videoSeekStep) }
            AppIconButton("goforward.10", help: appString("videoForward10", "Forward 10 seconds (→)")) { model.seek(by: videoSeekStep) }
            Spacer().frame(width: theme.spacing.s6)
            AppIconButton(model.isMuted ? "speaker.slash.fill" : "speaker.wave.2.fill",
                          help: model.isMuted ? appString("videoUnmute", "Unmute (M)") : appString("videoMute", "Mute (M)")) { model.toggleMute() }
            Slider(value: Binding(get: { model.volume }, set: { model.setVolume($0) }), in: 0...1)
                .controlSize(.mini).tint(theme.colors.tx2).frame(width: theme.sizes.control36 * 2)
            Spacer().frame(width: theme.spacing.s8)
            VideoTimeLabel(model: model)
            Spacer(minLength: theme.spacing.s8)
            VideoSpeedMenu(model: model)
            VideoToggleButton(symbol: "repeat", selected: model.isLooping, help: appString("videoLoop", "Loop")) { model.toggleLoop() }
            AppIconButton(expanded ? "arrow.down.right.and.arrow.up.left" : "arrow.up.left.and.arrow.down.right",
                          help: expanded ? appString("videoCollapse", "Exit expanded (F)") : appString("videoExpand", "Expand (F)"), action: onToggleExpand)
        }
    }
}

/// "0:12 / 3:40", live while playing.
private struct VideoTimeLabel: View {
    @Environment(\.appTheme) private var theme
    let model: AppVideoPlayerModel

    var body: some View {
        TimelineView(.animation(minimumInterval: 0.25, paused: !model.isPlaying)) { _ in
            let _ = model.positionVersion
            Text("\(formatVideoTime(model.currentSeconds)) / \(formatVideoTime(model.duration))")
                .font(theme.typography.mono).foregroundStyle(theme.colors.tx2).monospacedDigit().lineLimit(1).fixedSize()
        }
    }
}

private struct VideoSpeedMenu: View {
    @Environment(\.appTheme) private var theme
    let model: AppVideoPlayerModel

    var body: some View {
        AppMenuButton(help: appString("videoSpeed", "Playback speed"), items: {
            VideoSpeeds.options.map { s in AppNativeMenu.Item(VideoSpeeds.label(s), checked: s == model.speed) { model.setSpeed(s) } }
        }) {
            Text(VideoSpeeds.label(model.speed)).font(theme.typography.metaStrong)
                .foregroundStyle(model.speed == 1 ? theme.colors.tx2 : theme.colors.accent)
                .padding(.horizontal, theme.spacing.s8).frame(height: theme.sizes.control32).contentShape(Rectangle())
        }
        .fixedSize()
    }
}

private struct VideoToggleButton: View {
    @Environment(\.appTheme) private var theme
    let symbol: String; let selected: Bool; let help: String; let action: () -> Void
    var body: some View {
        Button(action: action) {
            Image(systemName: symbol).font(.system(size: theme.sizes.icon16))
                .foregroundStyle(selected ? theme.colors.accent : theme.colors.tx2)
                .frame(width: theme.sizes.control32, height: theme.sizes.control32)
                .background(selected ? theme.colors.sel : .clear, in: Circle()).contentShape(Circle())
        }
        .buttonStyle(.plain).help(help)
    }
}
