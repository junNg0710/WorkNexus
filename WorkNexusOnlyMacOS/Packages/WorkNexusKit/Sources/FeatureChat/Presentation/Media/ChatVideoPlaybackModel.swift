/// Ported from: lib/features/chat/presentation/providers/chat_video_playback.dart (`ChatVideoPlaybackNotifier`)
import CoreDomain
import Foundation
import Observation

/// The chat video playing right now in one open chat. One at a time: starting another stops it. While its message is
/// scrolled out of view it plays on in a floating mini player (`floating`); closing the chat stops it.
@MainActor @Observable
final class ChatVideoPlaybackModel {
    struct Playing {
        var messageGid: String
        var file: FileContent
        var player: ChatVideoPlayer
        var floating = false
    }

    private(set) var current: Playing?
    /// The message whose video is being opened (downloading its first bytes).
    private(set) var starting: String?

    func playing(_ messageGid: String) -> Playing? { current?.messageGid == messageGid ? current : nil }

    /// Plays `file` of `messageGid`, stopping whatever played before. The failure's text when it cannot be opened.
    func start(messageGid: String, accountId: String, file: FileContent, repository: ChatRepository, at: TimeInterval? = nil) async -> Failure? {
        guard starting == nil else { return nil }
        stop()
        starting = messageGid; defer { starting = nil }
        switch await ChatVideoPlayer.open(repository: repository, accountId: accountId, content: .file(file)) {
        case .failure(let f): return f
        case .success(let player):
            if let at { player.seek(to: at) }
            current = Playing(messageGid: messageGid, file: file, player: player)
            player.play()
            return nil
        }
    }

    /// Floats the video of `messageGid` (its message left the view) or docks it back; nothing when another video, or none,
    /// plays. A paused video stays docked: the mini player is for one still playing.
    func setFloating(_ messageGid: String, floating: Bool) {
        guard var c = current, c.messageGid == messageGid, c.floating != floating else { return }
        if floating && !c.player.isPlaying { return }
        c.floating = floating
        current = c
    }

    /// Stops and drops the player.
    func stop() {
        guard let c = current else { return }
        current = nil
        c.player.close()
    }
}
