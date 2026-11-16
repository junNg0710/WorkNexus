import AVFoundation
import AppKit
import QuickLookThumbnailing

/// Ported from: lib/core/platform/video_thumbnailer.dart
/// Extracts a still frame from a local video for chat previews: `AVAssetImageGenerator` first, QuickLook when the
/// asset can't be decoded that way. Returns nil when neither works; the UI then shows an icon. The PNG is cached next
/// to the video (`<video>.thumb.png`).
public actor VideoThumbnailer {
    public static let shared = VideoThumbnailer()
    private static let width: CGFloat = 480
    private var inFlight: [String: Task<Data?, Never>] = [:]

    public init() {}

    /// The frame made earlier for `videoPath`, even if the video itself is gone from the cache; nil when there is none.
    public nonisolated func cachedThumbnail(of videoPath: String) -> Data? {
        let cached = URL(fileURLWithPath: videoPath + ".thumb.png")
        guard let data = try? Data(contentsOf: cached) else { return nil }
        // Mark as used so the cache keeps the frame.
        try? FileManager.default.setAttributes([.modificationDate: Date()], ofItemAtPath: cached.path)
        return data
    }

    /// One run per video: a message's content changes twice as its upload lands (local result, then the server's echo),
    /// and two runs into the same output would race.
    public func thumbnail(of videoPath: String) async -> Data? {
        if let running = inFlight[videoPath] { return await running.value }
        let task = Task { await Self.make(videoPath) }
        inFlight[videoPath] = task
        let result = await task.value
        inFlight[videoPath] = nil
        return result
    }

    private static func make(_ videoPath: String) async -> Data? {
        let target = URL(fileURLWithPath: videoPath + ".thumb.png")
        if let data = try? Data(contentsOf: target) { return data }
        let video = URL(fileURLWithPath: videoPath)
        let png: Data?
        if let frame = await assetFrame(video) { png = frame } else { png = await quickLook(video) }
        guard let png else {
            // Another process may have made it meanwhile (an earlier app run).
            return try? Data(contentsOf: target)
        }
        try? png.write(to: target, options: .atomic)
        return png
    }

    private static func assetFrame(_ video: URL) async -> Data? {
        let generator = AVAssetImageGenerator(asset: AVURLAsset(url: video))
        generator.appliesPreferredTrackTransform = true
        generator.maximumSize = CGSize(width: width, height: width)
        generator.requestedTimeToleranceBefore = .positiveInfinity
        generator.requestedTimeToleranceAfter = .positiveInfinity
        for seconds in [0.5, 0.0] {
            if let (image, _) = try? await generator.image(at: CMTime(seconds: seconds, preferredTimescale: 600)),
               let png = pngData(image) { return png }
        }
        return nil
    }

    private static func quickLook(_ video: URL) async -> Data? {
        let request = QLThumbnailGenerator.Request(fileAt: video, size: CGSize(width: width, height: width), scale: 2,
                                                   representationTypes: .thumbnail)
        guard let rep = try? await QLThumbnailGenerator.shared.generateBestRepresentation(for: request) else { return nil }
        return pngData(rep.cgImage)
    }

    private static func pngData(_ image: CGImage) -> Data? {
        NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:])
    }
}
