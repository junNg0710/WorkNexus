import CoreDomain
import AVFoundation
import AppKit
import Observation

/// Ported from: lib/shared/detail/presentation/widgets/attachment_video_view.dart (the controller part) +
/// lib/core/widgets/video/smooth_video_position.dart
/// The state of one video player, held in a stable object (never rebuilt with the view, so a re-render does not
/// restart playback). It streams from `source.stream` (the session rides in the request headers); when there is no
/// stream, or it does not start within 20 s, it plays the file `source.download` fetches whole. Formats AVFoundation
/// cannot play (webm, mkv ...) end in `.external`: the view offers "open in another app".
/// The position is read from the AVPlayer's own clock (`currentSeconds`) on every frame, so the seek bar needs no
/// smoothing of the sparse reports Flutter's platform player gave.
@MainActor @Observable
public final class AppVideoPlayerModel {
    public enum Phase: Equatable { case loading, ready, failed, external }

    public let source: AppVideoSource
    public private(set) var phase = Phase.loading
    public private(set) var isPlaying = false
    /// Waiting for data while it should be playing.
    public private(set) var isBuffering = false
    public private(set) var duration: Double = 0
    public private(set) var buffered: [ClosedRange<Double>] = []
    public private(set) var volume: Double = 1
    public private(set) var speed: Double = 1
    public private(set) var isLooping = false
    /// Load speed while buffering (needs `source.sizeBytes`).
    public private(set) var bytesPerSecond: Double?
    /// Width / height of the picture once known.
    public private(set) var aspectRatio: Double = 16.0 / 9.0
    /// Bumped by a seek, so views that show the position while paused redraw.
    public private(set) var positionVersion = 0

    @ObservationIgnored public let player = AVPlayer()
    @ObservationIgnored private var started = false
    @ObservationIgnored private var observers: [NSKeyValueObservation] = []
    @ObservationIgnored private var endObserver: NSObjectProtocol?
    @ObservationIgnored private var meter = VideoLoadSpeedMeter()
    @ObservationIgnored private var meterTask: Task<Void, Never>?
    @ObservationIgnored private let streamTimeout: Duration

    public init(source: AppVideoSource, streamTimeout: Duration = .seconds(20)) {
        self.source = source; self.streamTimeout = streamTimeout
    }

    public var loadedFraction: Double { videoLoadedFraction(ranges: buffered, duration: duration) }
    public var isMuted: Bool { volume == 0 }

    /// The playback position, live from the player.
    public var currentSeconds: Double {
        let t = player.currentTime().seconds
        guard t.isFinite else { return 0 }
        return duration > 0 ? min(max(t, 0), duration) : max(t, 0)
    }

    // MARK: Opening

    /// Opens the video (once). Call from the view's `.task`; cancelling that task stops the open.
    public func start() async {
        guard !started else { return }
        started = true
        if !source.fileExtension.isEmpty, !AppVideoFormats.isNative(source.fileExtension) { phase = .external; return }
        startMeter()
        if var request = await source.stream() {
            // The source knows what the file is even when the stream's address does not say.
            if request.fileExtension == nil, !source.fileExtension.isEmpty { request.fileExtension = source.fileExtension }
            if await use(AVPlayerItem(asset: Self.asset(request)), timeout: streamTimeout) { return }
        }
        guard !Task.isCancelled else { return }
        if let path = await source.download(), !Task.isCancelled,
           await use(AVPlayerItem(asset: AppVideoFormats.asset(forFileAt: URL(fileURLWithPath: path), hint: source.fileExtension)),
                     timeout: .seconds(10)) { return }
        if !Task.isCancelled { phase = .failed }
    }

    /// The asset a player streams from: the session rides in the request headers.
    nonisolated public static func asset(_ request: MediaRequest) -> AVURLAsset {
        AVURLAsset(url: request.url, options: assetOptions(request))
    }

    /// The session as request headers, and the file's content type when the address has no video extension of its own.
    /// AVFoundation tells what a stream is from its extension or the server's content type: ZenTao's attachment
    /// addresses (`data/upload/1/202609/0911...`) have neither, and the asset failed at once with "Cannot Open" (-11828)
    /// - the video of a bug or task never played from the stream. Told the type, the same address is ready in under a
    /// second.
    nonisolated static func assetOptions(_ request: MediaRequest) -> [String: Any] {
        var options: [String: Any] = ["AVURLAssetHTTPHeaderFieldsKey": request.headers]
        if !AppVideoFormats.isVideo(request.url.pathExtension), let ext = request.fileExtension,
           let mime = AppVideoFormats.mimeType(forExtension: ext) {
            options[AVURLAssetOverrideMIMETypeKey] = mime
        }
        return options
    }

    private func use(_ item: AVPlayerItem, timeout: Duration) async -> Bool {
        detach()
        player.replaceCurrentItem(with: item)
        attach(item)
        let deadline = ContinuousClock.now + timeout
        while item.status == .unknown {
            if Task.isCancelled || ContinuousClock.now > deadline { break }
            try? await Task.sleep(for: .milliseconds(100))
        }
        guard item.status == .readyToPlay, !Task.isCancelled else {
            detach(); player.replaceCurrentItem(with: nil)
            return false
        }
        phase = .ready
        player.defaultRate = Float(speed)
        player.play()
        isPlaying = true
        return true
    }

    // MARK: Observation of the player

    private func attach(_ item: AVPlayerItem) {
        observers = [
            player.observe(\.timeControlStatus, options: [.initial, .new]) { [weak self] p, _ in
                let status = p.timeControlStatus, reason = p.reasonForWaitingToPlay
                Task { @MainActor in
                    self?.isPlaying = status != .paused
                    self?.isBuffering = status == .waitingToPlayAtSpecifiedRate && reason != .noItemToPlay
                }
            },
            item.observe(\.loadedTimeRanges, options: [.initial, .new]) { [weak self] i, _ in
                let ranges = i.loadedTimeRanges.map(\.timeRangeValue).map { r in r.start.seconds...(r.start.seconds + r.duration.seconds) }
                Task { @MainActor in self?.buffered = ranges.filter { $0.lowerBound.isFinite && $0.upperBound.isFinite } }
            },
            item.observe(\.duration, options: [.initial, .new]) { [weak self] i, _ in
                let d = i.duration.seconds
                Task { @MainActor in if d.isFinite { self?.duration = d } }
            },
            item.observe(\.presentationSize, options: [.initial, .new]) { [weak self] i, _ in
                let s = i.presentationSize
                Task { @MainActor in if s.width > 0, s.height > 0 { self?.aspectRatio = Double(s.width / s.height) } }
            },
        ]
        endObserver = NotificationCenter.default.addObserver(forName: .AVPlayerItemDidPlayToEndTime, object: item, queue: .main) { [weak self] _ in
            Task { @MainActor in
                guard let self, self.isLooping else { return }
                await self.player.seek(to: .zero)
                self.player.play()
            }
        }
    }

    private func detach() {
        observers.forEach { $0.invalidate() }
        observers = []
        if let endObserver { NotificationCenter.default.removeObserver(endObserver) }
        endObserver = nil
    }

    private func startMeter() {
        meterTask?.cancel()
        meterTask = Task { [weak self] in
            while !Task.isCancelled {
                self?.sampleLoadSpeed()
                try? await Task.sleep(for: .milliseconds(500))
            }
        }
    }

    private func sampleLoadSpeed() {
        guard isBuffering || phase == .loading, let size = source.sizeBytes, size > 0 else { return }
        meter.add(Date(), bytes: Int(loadedFraction * Double(size)))
        bytesPerSecond = meter.bytesPerSecond
    }

    /// Stops playback and drops the item (call when the view goes away).
    public func stop() {
        meterTask?.cancel(); meterTask = nil
        player.pause()
        detach()
        player.replaceCurrentItem(with: nil)
    }

    // MARK: Controls

    public func play() {
        if duration > 0, currentSeconds >= duration - 0.05 { player.seek(to: .zero) }
        player.defaultRate = Float(speed)
        player.play()
        isPlaying = true
    }

    public func pause() { player.pause(); isPlaying = false }
    public func togglePlay() { isPlaying ? pause() : play() }

    /// Moves the playhead to `seconds` (clamped to the video).
    public func seek(to seconds: Double) {
        let target = min(max(seconds, 0), duration > 0 ? duration : max(seconds, 0))
        player.seek(to: CMTime(seconds: target, preferredTimescale: 600))
        positionVersion += 1
    }

    public func seek(by delta: Double) { seek(to: currentSeconds + delta) }

    public func setVolume(_ value: Double) {
        volume = min(max(value, 0), 1)
        player.volume = Float(volume)
    }

    public func toggleMute() { setVolume(isMuted ? 1 : 0) }

    public func setSpeed(_ value: Double) {
        speed = value
        player.defaultRate = Float(value)
        if isPlaying { player.rate = Float(value) }
    }

    public func toggleLoop() { isLooping.toggle() }

    /// Downloads the file (if it was not already) and hands it to the system's default app for it.
    @discardableResult
    public func openExternally() async -> Bool {
        guard let path = await source.download() else { return false }
        return NSWorkspace.shared.open(URL(fileURLWithPath: path))
    }
}
