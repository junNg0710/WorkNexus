/// Ported from: lib/features/chat/presentation/widgets/{chat_video_tile,chat_video_tile_parts,chat_video_overlays}.dart
import AppKit
import CoreDomain
import CoreUI
import SwiftUI

/// A video as a 16:9 frame: its preview image (when one can be made), the name and size along the top, the length bottom-left
/// and a full-screen button bottom-right. Play starts it right in the frame — streaming while it downloads — and a click then
/// pauses / resumes; full screen opens the viewer. Scrolled out of view while it plays, it floats as a mini player
/// (`ChatFloatingVideo`). Own videos still uploading look the same, with send progress over them.
struct ChatVideoTile: View {
    @Environment(\.appTheme) private var theme
    @Environment(\.chatServices) private var services
    @Environment(\.toasts) private var toasts
    let message: ChatMessage
    let file: FileContent
    let state: ChatThreadState
    @State private var thumbnail: NSImage?
    @State private var duration: TimeInterval?
    @State private var viewer: ChatVideoViewerRequest?

    private var key: TransferKey { TransferKey(accountId: message.accountId, content: .file(file)) }
    private var playable: Bool { message.sendState == .sent || file.fileId > 0 }
    static let size = CGSize(width: 320, height: 180)

    var body: some View {
        let playback = state.video
        // Played here only while docked: floating, the mini player shows it.
        let docked = playback.playing(message.gid).flatMap { $0.floating ? nil : $0.player }
        ZStack {
            Rectangle().fill(theme.colors.scrim)
            if let docked { ChatPlayerSurface(player: docked.player) }
            else if let thumbnail { Image(nsImage: thumbnail).resizable().scaledToFill() }
            else if !playable { Image(systemName: "film").font(.system(size: theme.sizes.icon24)).foregroundStyle(theme.colors.tx3) }
            if playable { Color.clear.contentShape(Rectangle()).onTapGesture { Task { await play() } } }
            VStack(spacing: 0) {
                ChatVideoNameBar(name: file.name, size: file.size).allowsHitTesting(false)
                Spacer(minLength: 0)
            }
            ChatVideoCentreControl(canPlay: playable, starting: playback.starting == message.gid, playing: docked, downloadProgress: nil)
                .allowsHitTesting(false)
            VStack {
                Spacer()
                HStack(spacing: theme.spacing.s6) {
                    ChatVideoTimeCorner(player: docked, duration: playable ? duration : nil).allowsHitTesting(false)
                    Spacer()
                    if let docked {
                        ChatVideoCornerButton(icon: docked.volume == 0 ? "speaker.slash.fill" : "speaker.wave.2.fill",
                                              help: docked.volume == 0 ? shellString("chatUnmute", "Unmute") : shellString("chatMute", "Mute")) { docked.toggleMute() }
                    }
                    if playable { ChatVideoCornerButton(icon: "arrow.up.left.and.arrow.down.right", help: shellString("chatFullScreen", "Full screen")) { fullScreen(docked) } }
                }
            }
            .padding(theme.spacing.s8).padding(.bottom, docked == nil ? 0 : theme.spacing.s2)
            if let docked { VStack { Spacer(); ChatVideoProgressLine(player: docked) } }
            if message.sendState != .sent { ChatUploadOverlay(message: message) }
            else if let p = AttachmentTransfers.shared.progress(key) {
                ProgressRing(progress: p, help: appString("chatCancelDownload", "Cancel download")) {
                    if let repo = services?.chat { AttachmentTransfers.shared.cancel(key, repo) }
                }
            }
        }
        .frame(width: Self.size.width, height: Self.size.height)
        .clipShape(RoundedRectangle(cornerRadius: theme.radii.lg))
        .help(appString("chatPlayVideo", "Play video"))
        .onScrollVisibilityChange(threshold: 0.33) { visible in playback.setFloating(message.gid, floating: !visible) }
        .onDisappear { playback.setFloating(message.gid, floating: true) }
        .task(id: message.gid + String(message.sendState == .sent)) { await load() }
        .sheet(item: $viewer) { v in
            ChatVideoViewer(accountId: message.accountId, file: file, startAt: v.startAt) { at in
                if let at, let mine = playback.playing(message.gid)?.player { mine.seek(to: at) }
            }
        }
    }

    /// Plays in the frame (streaming while it downloads); once playing, a click pauses / resumes.
    private func play() async {
        let playback = state.video
        if let mine = playback.playing(message.gid) { mine.player.toggle(); return }
        guard let repo = services?.chat else { return }
        if let failure = await playback.start(messageGid: message.gid, accountId: message.accountId, file: file, repository: repo) {
            if case .cancelled = failure { return }
            toasts?.show(appString("chatVideoFailed", "Couldn't play this video"), kind: .error)
        }
    }

    /// The viewer takes over from where the frame is, and hands the spot back when it closes.
    private func fullScreen(_ docked: ChatVideoPlayer?) {
        docked?.pause()
        viewer = ChatVideoViewerRequest(startAt: docked?.position)
    }

    private func load() async {
        guard let repo = services?.chat else { return }
        let pending = message.sendState != .sent && file.fileId == 0
        let result = pending ? await repo.pendingVideoThumbnail(messageGid: message.gid, fileName: file.name)
                             : await repo.videoThumbnail(accountId: message.accountId, video: .file(file))
        if case .success(let d) = result { thumbnail = NSImage(data: d) }
        if !pending, case .success(let t) = await repo.videoDuration(accountId: message.accountId, video: .file(file)) { duration = t }
    }

    static func format(_ t: TimeInterval) -> String { ChatVideoPlayer.format(t) }
}

/// A request to open the viewer, from where the frame was playing.
struct ChatVideoViewerRequest: Identifiable {
    let id = UUID()
    var startAt: TimeInterval?
}
