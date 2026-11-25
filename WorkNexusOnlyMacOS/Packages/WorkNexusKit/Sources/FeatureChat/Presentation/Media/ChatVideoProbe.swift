#if DEBUG
import AVFoundation
import CoreDomain
import Foundation

/// DEBUG only: opens one chat video the way the tile does and says, step by step, what happened and how long it took -
/// which transfers the player asked for, what the server answered, when (whether) the player was ready. For a video that
/// "will not play" on a real account (`WN_LIVE_VIDEO`).
public enum ChatVideoProbe {
    @MainActor
    public static func run(repository: ChatRepository, accountId: String, file: FileContent, log: @escaping @Sendable (String) -> Void) async {
        let began = Date()
        func at() -> String { String(format: "+%.1fs", Date().timeIntervalSince(began)) }
        XxdRangeStream.trace = { line in log("\(String(format: "+%.1fs", Date().timeIntervalSince(began))) \(line)") }
        defer { XxdRangeStream.trace = nil }
        let content = MessageContent.file(file)
        log("\(at()) cached: \(await repository.isAttachmentCached(accountId: accountId, content: content))")
        switch await repository.videoPlayback(accountId: accountId, content: content) {
        case .failure(let f): log("\(at()) videoPlayback failed: \(f.message)"); return
        case .success(.file(let url)): log("\(at()) plays from the cached file \(url.lastPathComponent)")
        case .success(.stream(let source)): log("\(at()) streams: \(source.contentLength) bytes, type \(source.contentType)")
        }
        switch await ChatVideoPlayer.open(repository: repository, accountId: accountId, content: content) {
        case .failure(let f): log("\(at()) open failed: \(f.message)")
        case .success(let player):
            log("\(at()) ready to play: \(player.player.currentItem?.duration.seconds ?? -1) s long")
            player.play()
            try? await Task.sleep(for: .seconds(4))
            log("\(at()) after 4 s: at \(player.position) s, playing \(player.isPlaying), "
                + "\(XxdRangeStream.delivered.with { $0 } / 1024) KB read, error \(player.player.currentItem?.error?.localizedDescription ?? "none")")
            player.close()
        }
    }
}
#endif
