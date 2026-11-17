/// Not in the Flutter app: a video on the media viewer's stage.
import CoreUI
import SwiftUI

/// Plays `file` on the viewer's dark stage with the usual controls, streaming while it downloads. A click on the picture
/// pauses / resumes; stepping to another item (or closing) stops and releases the player.
struct ChatViewerVideoStage: View {
    @Environment(\.appTheme) private var theme
    @Environment(\.chatServices) private var services
    let accountId: String
    let file: FileContent
    @State private var player: ChatVideoPlayer?
    @State private var failure: String?

    var body: some View {
        ZStack(alignment: .bottom) {
            if let player {
                ChatPlayerSurface(player: player.player).contentShape(Rectangle()).onTapGesture { player.toggle() }
                ChatVideoControls(player: player, onToggleFullScreen: { (NSApp.mainWindow ?? NSApp.keyWindow)?.toggleFullScreen(nil) })
            } else if let failure {
                VStack(spacing: theme.spacing.s6) {
                    Text(appString("chatVideoFailed", "Couldn't play this video")).foregroundStyle(theme.colors.onScrim)
                    Text(failure).font(theme.typography.caption).foregroundStyle(theme.colors.onScrim.opacity(0.7))
                }
                .frame(maxHeight: .infinity)
            } else { ProgressView().tint(theme.colors.onScrim).frame(maxHeight: .infinity) }
        }
        .task(id: file) { await start() }
        .onDisappear { stop() }
    }

    private func start() async {
        stop(); failure = nil
        guard let repo = services?.chat else { failure = "Chat is not available"; return }
        switch await ChatVideoPlayer.open(repository: repo, accountId: accountId, content: .file(file)) {
        case .success(let p):
            if Task.isCancelled { p.close(); return }
            player = p; p.play()
        case .failure(let f): if !isCancelled(f) { failure = f.message }
        }
    }

    private func stop() { player?.close(); player = nil }
}
