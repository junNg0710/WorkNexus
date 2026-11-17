/// Ported from: lib/features/chat/presentation/widgets/{chat_video_dialog,chat_video_controls,chat_floating_video}.dart
import AppKit
import CoreDomain
import CoreUI
import SwiftUI

/// The video viewer sheet: the picture over a bar of controls (play/pause, seek, ±10 s, volume, speed, loop, full screen).
/// The video streams while it downloads (`ChatRepository.videoPlayback`) instead of waiting for the whole file. Keys: Space
/// plays / pauses, ← / → seek 10 s, M mutes, L loops, F toggles full screen, Esc closes. `startAt` resumes where the frame
/// was; `onClosed` reports where the viewer left it.
struct ChatVideoViewer: View {
    @Environment(\.appTheme) private var theme
    @Environment(\.chatServices) private var services
    @Environment(\.dismiss) private var dismiss
    @FocusState private var focused: Bool
    let accountId: String
    let file: FileContent
    var startAt: TimeInterval?
    var onClosed: (TimeInterval?) -> Void = { _ in }
    @State private var player: ChatVideoPlayer?
    @State private var failure: String?
    /// Most of the window it opens over.
    @State private var size = ChatViewerSize.current

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: theme.spacing.s8) {
                Text(file.name).font(theme.typography.bodyStrong).foregroundStyle(theme.colors.tx).lineLimit(1)
                Spacer()
                AppIconButton("xmark", help: appString("chatClosePanel", "Close")) { dismiss() }
            }
            .padding(.horizontal, theme.spacing.s12).frame(height: theme.sizes.titleBar - theme.spacing.s8)
            .background(theme.colors.panel)
            ZStack(alignment: .bottom) {
                theme.colors.scrim
                if let player {
                    ChatPlayerSurface(player: player.player).contentShape(Rectangle()).onTapGesture { player.toggle() }
                    ChatVideoControls(player: player, onToggleFullScreen: toggleFullScreen)
                } else if let failure {
                    VStack(spacing: theme.spacing.s6) {
                        Text(appString("chatVideoFailed", "Couldn't play this video")).foregroundStyle(theme.colors.onScrim)
                        Text(failure).font(theme.typography.caption).foregroundStyle(theme.colors.onScrim.opacity(0.7))
                    }
                    .frame(maxHeight: .infinity)
                } else { ProgressView().tint(theme.colors.onScrim).frame(maxHeight: .infinity) }
            }
        }
        .frame(width: size.width, height: size.height)
        .focusable().focused($focused).focusEffectDisabled()
        .onKeyPress(.space) { player?.toggle(); return player == nil ? .ignored : .handled }
        .onKeyPress(.leftArrow) { player?.skip(by: -ChatVideoPlayer.seekStep); return player == nil ? .ignored : .handled }
        .onKeyPress(.rightArrow) { player?.skip(by: ChatVideoPlayer.seekStep); return player == nil ? .ignored : .handled }
        .onKeyPress(characters: ["m", "M"]) { _ in player?.toggleMute(); return player == nil ? .ignored : .handled }
        .onKeyPress(characters: ["l", "L"]) { _ in player?.isLooping.toggle(); return player == nil ? .ignored : .handled }
        .onKeyPress(characters: ["f", "F"]) { _ in toggleFullScreen(); return .handled }
        .onKeyPress(.escape) { dismiss(); return .handled }
        .task { await start() }
        .onAppear { focused = true }
        .onDisappear { onClosed(player?.position); player?.close(); player = nil }
    }

    private func toggleFullScreen() { (NSApp.mainWindow ?? NSApp.keyWindow)?.toggleFullScreen(nil) }

    private func start() async {
        guard let repo = services?.chat else { failure = "Chat is not available"; return }
        switch await ChatVideoPlayer.open(repository: repo, accountId: accountId, content: .file(file)) {
        case .success(let p):
            if let startAt { p.seek(to: startAt) }
            player = p; p.play()
        case .failure(let f): failure = f.message
        }
    }
}
