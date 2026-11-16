import CoreDomain
import Foundation

/// Ported from: lib/core/widgets/video/{video_time,video_control_bar}.dart, lib/core/util/load_speed_meter.dart
/// Pure helpers behind the video player: time text, the speed list, the loaded share and the load-speed meter.

/// "m:ss", or "h:mm:ss" for long videos. Negative, NaN and infinite values read as 0:00.
public func formatVideoTime(_ seconds: Double) -> String {
    let total = seconds.isFinite ? max(Int(seconds), 0) : 0
    let h = total / 3600, m = (total / 60) % 60, s = total % 60
    return h > 0 ? String(format: "%d:%02d:%02d", h, m, s) : String(format: "%d:%02d", m, s)
}

/// Playback speeds offered by the speed menu, and how one reads ("1x", "1.25x").
public enum VideoSpeeds {
    public static let options: [Double] = [0.5, 0.75, 1, 1.25, 1.5, 2]
    public static func label(_ speed: Double) -> String {
        let text = speed.truncatingRemainder(dividingBy: 1) == 0 ? String(Int(speed)) : String(speed)
        return "\(text)x"
    }
}

/// Seek step of the +-10 s buttons (and the arrow keys), in seconds.
public let videoSeekStep: Double = 10

/// What a player can show: formats AVFoundation plays or streams, versus those that need another app.
public enum AppVideoFormats {
    public static let native: Set<String> = ["mp4", "m4v", "mov"]
    public static let external: Set<String> = ["webm", "mkv", "avi", "flv", "wmv", "mpg", "mpeg", "ogv", "3gp"]
    public static var all: Set<String> { native.union(external) }
    public static func isNative(_ ext: String) -> Bool { native.contains(ext.lowercased()) }
    public static func isVideo(_ ext: String) -> Bool { all.contains(ext.lowercased()) }
}

/// How much of a video has loaded, 0...1: the end of its furthest buffered range.
public func videoLoadedFraction(ranges: [ClosedRange<Double>], duration: Double) -> Double {
    guard duration > 0, duration.isFinite else { return 0 }
    let end = ranges.map(\.upperBound).max() ?? 0
    return min(max(end / duration, 0), 1)
}

/// How fast something loads, from how many bytes are in at moments in time, averaged over the last `window` so one
/// slow or quick sample does not swing it.
public struct VideoLoadSpeedMeter {
    public let window: TimeInterval
    private var samples: [(at: Date, bytes: Int)] = []
    public init(window: TimeInterval = 3) { self.window = window }

    /// Notes that `bytes` were loaded by `at`. A seek can restart the buffer lower: a new run, not a negative speed.
    public mutating func add(_ at: Date, bytes: Int) {
        if let last = samples.last, bytes < last.bytes { samples.removeAll() }
        samples.append((at, bytes))
        while samples.count > 2, at.timeIntervalSince(samples[1].at) >= window { samples.removeFirst() }
    }

    /// Bytes per second over the window; nil until two samples are apart.
    public var bytesPerSecond: Double? {
        guard let first = samples.first, let last = samples.last, samples.count >= 2 else { return nil }
        let seconds = last.at.timeIntervalSince(first.at)
        return seconds > 0 ? Double(last.bytes - first.bytes) / seconds : nil
    }
}

/// Where a player gets a video from, provider-agnostic. `stream` returns a URL plus the headers (session) it needs, or
/// nil when the file cannot be streamed; `download` fetches the whole file and returns its local path (used when
/// streaming is unavailable or fails).
public struct AppVideoSource {
    public var title: String
    public var fileExtension: String
    public var sizeBytes: Int?
    public var stream: () async -> MediaRequest?
    public var download: () async -> String?

    public init(title: String, fileExtension: String, sizeBytes: Int? = nil,
                stream: @escaping () async -> MediaRequest? = { nil }, download: @escaping () async -> String?) {
        self.title = title; self.fileExtension = fileExtension; self.sizeBytes = sizeBytes
        self.stream = stream; self.download = download
    }

    /// A local file.
    public static func file(path: String) -> AppVideoSource {
        let url = URL(fileURLWithPath: path)
        return AppVideoSource(title: url.lastPathComponent, fileExtension: url.pathExtension, download: { path })
    }
}
