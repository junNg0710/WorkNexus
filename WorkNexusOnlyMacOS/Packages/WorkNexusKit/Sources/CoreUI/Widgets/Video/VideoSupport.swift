import AVFoundation
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

    /// The content type of a file AVFoundation plays, by its extension; nil for anything else.
    public static func mimeType(forExtension ext: String) -> String? {
        switch ext.lowercased() {
        case "mp4": "video/mp4"
        case "m4v": "video/x-m4v"
        case "mov": "video/quicktime"
        default: nil
        }
    }

    /// The content type of an MP4 or QuickTime file, read from its first bytes; nil for anything else. Both open with
    /// an `ftyp` box (its brand tells them apart); an older QuickTime movie opens with one of its own atoms.
    public static func sniffedMimeType(_ head: Data) -> String? {
        let bytes = [UInt8](head.prefix(12))
        guard bytes.count >= 8 else { return nil }
        let atom = String(decoding: bytes[4..<8], as: UTF8.self)
        if atom == "ftyp" {
            let brand = bytes.count >= 12 ? String(decoding: bytes[8..<12], as: UTF8.self) : ""
            return brand == "qt  " ? "video/quicktime" : "video/mp4"
        }
        return ["moov", "mdat", "wide", "free", "skip"].contains(atom) ? "video/quicktime" : nil
    }

    /// The asset of a video file on this Mac. AVFoundation tells what a file is from its name: one kept without an
    /// extension, or under another one (a download named after an id, a chat file sent as "video"), failed with
    /// "Cannot Open" although it is a plain MP4. Such a file is told what it is, from `hint` (the extension its owner
    /// knows it by) or from its first bytes.
    public static func asset(forFileAt url: URL, hint: String? = nil) -> AVURLAsset {
        if isNative(url.pathExtension) { return AVURLAsset(url: url) }
        var mime = hint.flatMap(mimeType(forExtension:))
        if mime == nil, let handle = try? FileHandle(forReadingFrom: url) {
            mime = (try? handle.read(upToCount: 12)).flatMap { sniffedMimeType($0) }
            try? handle.close()
        }
        return AVURLAsset(url: url, options: mime.map { [AVURLAssetOverrideMIMETypeKey: $0] })
    }
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
