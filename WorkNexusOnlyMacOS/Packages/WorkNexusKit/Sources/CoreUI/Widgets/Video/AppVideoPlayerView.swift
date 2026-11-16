import SwiftUI

/// Ported from: lib/shared/detail/presentation/widgets/{attachment_video_view,attachment_video_picture}.dart
/// In-app video playback: the picture (a click plays / pauses, a play disc while paused, a loading badge with the
/// percent and speed while it buffers), a seek bar and the full control row, with the keys Space (play / pause),
/// left / right (-10 s / +10 s), M (mute) and F (expand). Streams when `source.stream` gives a request, else plays the
/// downloaded file; formats AVFoundation cannot play show "Open in another app". The player lives in a stable
/// `AppVideoPlayerModel` owned by this view (give the view an `.id` per video). `expanded` / `onToggleExpand` let
/// the host fill the window (and go full screen); the player only draws the state and the button.
public struct AppVideoPlayerView: View {
    @Environment(\.appTheme) private var theme
    @Environment(\.toasts) private var toasts
    @State private var model: AppVideoPlayerModel
    @FocusState private var focused: Bool
    let expanded: Bool
    let onToggleExpand: () -> Void

    public init(source: AppVideoSource, expanded: Bool = false, onToggleExpand: @escaping () -> Void = {}) {
        _model = State(initialValue: AppVideoPlayerModel(source: source))
        self.expanded = expanded; self.onToggleExpand = onToggleExpand
    }

    /// A player whose model the host owns (to read its state, or to keep playback across views).
    public init(model: AppVideoPlayerModel, expanded: Bool = false, onToggleExpand: @escaping () -> Void = {}) {
        _model = State(initialValue: model)
        self.expanded = expanded; self.onToggleExpand = onToggleExpand
    }

    public var body: some View {
        VStack(spacing: 0) {
            ZStack {
                theme.colors.scrim
                switch model.phase {
                case .loading: ProgressView().controlSize(.regular).tint(theme.colors.onScrim)
                case .ready: VideoPicture(model: model)
                case .failed: VideoMessage(text: appString("attachmentLoadFailed", "Couldn't load the attachment"), isError: true,
                                           actionTitle: nil, action: {})
                case .external:
                    VideoMessage(text: appString("videoNeedsExternalApp", "This video format can't be played here"), isError: false,
                                 actionTitle: appString("openInAnotherApp", "Open in another app")) {
                        Task { if !(await model.openExternally()) { toasts?.show(appString("attachmentLoadFailed", "Couldn't load the attachment"), kind: .error) } }
                    }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            if model.phase == .ready {
                VStack(spacing: theme.spacing.s2) {
                    VideoSeekBar(model: model)
                    VideoControlBar(model: model, expanded: expanded, onToggleExpand: onToggleExpand)
                }
                .padding(.horizontal, theme.spacing.s12).padding(.top, theme.spacing.s2).padding(.bottom, theme.spacing.s8)
            }
        }
        .focusable().focused($focused).focusEffectDisabled()
        .onKeyPress(.space) { guard model.phase == .ready else { return .ignored }; model.togglePlay(); return .handled }
        .onKeyPress(.leftArrow) { guard model.phase == .ready else { return .ignored }; model.seek(by: -videoSeekStep); return .handled }
        .onKeyPress(.rightArrow) { guard model.phase == .ready else { return .ignored }; model.seek(by: videoSeekStep); return .handled }
        .onKeyPress(characters: CharacterSet(charactersIn: "mMfF"), phases: .down) { press in
            if press.characters.lowercased() == "m" { guard model.phase == .ready else { return .ignored }; model.toggleMute() } else { onToggleExpand() }
            return .handled
        }
        .task { await model.start() }
        .onAppear { focused = true }
        .onDisappear { model.stop() }
    }
}

/// The picture with its overlays; a click plays / pauses.
private struct VideoPicture: View {
    @Environment(\.appTheme) private var theme
    let model: AppVideoPlayerModel

    var body: some View {
        ZStack {
            VideoSurface(player: model.player)
                .aspectRatio(model.aspectRatio, contentMode: .fit)
            Color.clear.contentShape(Rectangle()).onTapGesture { model.togglePlay() }
            if model.isBuffering { VideoLoadingBadge(model: model) } else if !model.isPlaying { VideoPlayDisc().allowsHitTesting(false) }
        }
    }
}

/// The disc over a paused picture (and over a video's still).
public struct VideoPlayDisc: View {
    @Environment(\.appTheme) private var theme
    public init() {}
    public var body: some View {
        Image(systemName: "play.fill").font(.system(size: theme.sizes.icon24)).foregroundStyle(theme.colors.onScrim)
            .padding(.leading, theme.spacing.s2)
            .frame(width: theme.sizes.control36 * 1.5, height: theme.sizes.control36 * 1.5)
            .background(theme.colors.scrim.opacity(0.55), in: Circle())
    }
}

/// A spinner and "Loading 32% · 1.2 MB/s" while the player waits for data.
private struct VideoLoadingBadge: View {
    @Environment(\.appTheme) private var theme
    let model: AppVideoPlayerModel

    var body: some View {
        let percent = String(Int((model.loadedFraction * 100).rounded()))
        let label = VideoLoadingText.make(percent: percent, bytesPerSecond: model.bytesPerSecond)
        HStack(spacing: theme.spacing.s8) {
            ProgressView().controlSize(.small).tint(theme.colors.onScrim)
            Text(label).font(theme.typography.label).foregroundStyle(theme.colors.onScrim)
        }
        .padding(.horizontal, theme.spacing.s14).padding(.vertical, theme.spacing.s10)
        .background(theme.colors.scrim.opacity(0.6), in: RoundedRectangle(cornerRadius: theme.radii.lg))
        .allowsHitTesting(false)
    }
}

/// "Loading 32%" / "Loading 32% · 1.2 MB/s". The catalog texts hold a literal `%` after `%1$@`, so the placeholders are
/// replaced by hand: `String(format:)` would read that `%` as a conversion.
enum VideoLoadingText {
    static func make(percent: String, bytesPerSecond: Double?) -> String {
        guard let speed = bytesPerSecond else {
            return appString("videoBuffering", "Loading %1$@%").replacingOccurrences(of: "%1$@", with: percent)
        }
        return appString("videoBufferingSpeed", "Loading %1$@% · %2$@/s")
            .replacingOccurrences(of: "%1$@", with: percent).replacingOccurrences(of: "%2$@", with: formatFileSize(Int(speed)) ?? "")
    }
}

private struct VideoMessage: View {
    @Environment(\.appTheme) private var theme
    let text: String; let isError: Bool; let actionTitle: String?; let action: () -> Void

    var body: some View {
        VStack(spacing: theme.spacing.s10) {
            Text(text).font(theme.typography.body).foregroundStyle(isError ? theme.colors.red : theme.colors.onScrim)
                .multilineTextAlignment(.center)
            if let actionTitle { AppButton(actionTitle, systemImage: "arrow.up.right.square", kind: .primary, action: action) }
        }
        .padding(theme.spacing.s16)
    }
}
