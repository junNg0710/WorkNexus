/// Ported from: lib/features/chat/presentation/providers/chat_video_playback.dart (`openChatVideo`, the player controller)
import AVFoundation
import Combine
import CoreDomain
import Foundation
import Observation

/// One chat video's player: an `AVPlayer` with the state the controls draw (playing, position, length, volume, speed, loop)
/// and the commands they send. Plays a cached file or streams through a `ChatVideoSourceLoader` while the video downloads.
@MainActor @Observable
final class ChatVideoPlayer {
    /// Seek step of the ±10 s buttons (and the arrow keys).
    static let seekStep: TimeInterval = 10
    /// Playback speeds offered by the speed menu.
    static let speeds: [Double] = [0.5, 0.75, 1.0, 1.25, 1.5, 2.0]

    let player: AVPlayer
    private(set) var isPlaying = false
    private(set) var position: TimeInterval = 0
    private(set) var duration: TimeInterval = 0
    /// Width over height once known.
    private(set) var aspectRatio: CGFloat?
    private(set) var volume: Double = 1
    private(set) var speed: Double = 1
    var isLooping = false

    @ObservationIgnored private let loader: ChatVideoSourceLoader?
    @ObservationIgnored private var timeObserver: Any?
    @ObservationIgnored private var bag = Set<AnyCancellable>()
    @ObservationIgnored private var userWantsPlaying = false

    init(item: AVPlayerItem, loader: ChatVideoSourceLoader?) {
        player = AVPlayer(playerItem: item)
        self.loader = loader
        timeObserver = player.addPeriodicTimeObserver(forInterval: CMTime(seconds: 0.25, preferredTimescale: 600), queue: .main) { [weak self] t in
            MainActor.assumeIsolated { if t.isNumeric { self?.position = t.seconds } }
        }
        player.publisher(for: \.timeControlStatus).receive(on: DispatchQueue.main)
            .sink { [weak self] s in MainActor.assumeIsolated { self?.isPlaying = s != .paused } }.store(in: &bag)
        item.publisher(for: \.duration).receive(on: DispatchQueue.main)
            .sink { [weak self] d in MainActor.assumeIsolated { if d.isNumeric { self?.duration = d.seconds } } }.store(in: &bag)
        item.publisher(for: \.presentationSize).receive(on: DispatchQueue.main)
            .sink { [weak self] s in MainActor.assumeIsolated { if s.width > 0, s.height > 0 { self?.aspectRatio = s.width / s.height } } }.store(in: &bag)
        NotificationCenter.default.publisher(for: .AVPlayerItemDidPlayToEndTime, object: item).receive(on: DispatchQueue.main)
            .sink { [weak self] _ in MainActor.assumeIsolated { self?.finished() } }.store(in: &bag)
    }

    /// Opens `file` for playback: the cached file or a stream. Fails with the reason when the player cannot read it.
    static func open(repository: ChatRepository, accountId: String, content: MessageContent) async -> Outcome<ChatVideoPlayer> {
        let playback: ChatVideoPlayback
        switch await repository.videoPlayback(accountId: accountId, content: content) {
        case .success(let p): playback = p
        case .failure(let f): return .failure(f)
        }
        let asset: AVURLAsset, loader: ChatVideoSourceLoader?
        switch playback {
        case .file(let url): asset = AVURLAsset(url: url); loader = nil
        case .stream(let source): (asset, loader) = ChatVideoSourceLoader.asset(for: source)
        }
        let item = AVPlayerItem(asset: asset)
        let player = ChatVideoPlayer(item: item, loader: loader)
        for await status in item.publisher(for: \.status).values {
            if status == .readyToPlay { return .success(player) }
            if status == .failed {
                player.close()
                return .failure(.unexpected(item.error?.localizedDescription ?? "Couldn't play this video"))
            }
            if Task.isCancelled { player.close(); return .failure(.cancelled("cancelled")) }
        }
        // The loop also ends when the task is cancelled while waiting.
        if Task.isCancelled { player.close(); return .failure(.cancelled("cancelled")) }
        return .success(player)
    }

    func play() { userWantsPlaying = true; if position >= duration - 0.05, duration > 0 { seek(to: 0) }; player.rate = Float(speed) }
    func pause() { userWantsPlaying = false; player.pause() }
    func toggle() { isPlaying ? pause() : play() }

    func seek(to t: TimeInterval) {
        let target = min(max(t, 0), duration > 0 ? duration : t)
        position = target
        player.seek(to: CMTime(seconds: target, preferredTimescale: 600), toleranceBefore: .zero, toleranceAfter: .zero)
    }

    func skip(by delta: TimeInterval) { seek(to: position + delta) }

    func setVolume(_ v: Double) { volume = min(max(v, 0), 1); player.volume = Float(volume) }
    func toggleMute() { setVolume(volume == 0 ? 1 : 0) }

    func setSpeed(_ s: Double) { speed = s; if isPlaying { player.rate = Float(s) } }

    private func finished() {
        if isLooping { seek(to: 0); player.rate = Float(speed) } else { userWantsPlaying = false; isPlaying = false }
    }

    /// Stops the transfer and releases the player.
    func close() {
        player.pause()
        if let timeObserver { player.removeTimeObserver(timeObserver); self.timeObserver = nil }
        bag.removeAll()
        loader?.cancelAll()
        player.replaceCurrentItem(with: nil)
    }

    /// "m:ss", or "h:mm:ss" for long videos.
    static func format(_ t: TimeInterval) -> String {
        let s = Int(max(t, 0).rounded())
        return s >= 3600 ? String(format: "%d:%02d:%02d", s / 3600, s / 60 % 60, s % 60) : String(format: "%d:%02d", s / 60, s % 60)
    }
}
