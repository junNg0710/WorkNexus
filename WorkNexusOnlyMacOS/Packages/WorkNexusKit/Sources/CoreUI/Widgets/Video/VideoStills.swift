import AVFoundation
import AppKit
import CoreDomain

/// Ported from: lib/core/platform/video_thumbnailer.dart (the streamed variant) + sync_coordinator.dart `attachmentThumbnail`
/// A still frame of a video that is not on disk: `AVAssetImageGenerator` reads just what it needs over HTTP (the
/// session rides in the request headers), so a timeline can show a picture without downloading the recording.
public enum AppVideoStills {
    private static let cache = NSCache<NSString, NSData>()

    /// PNG bytes of the frame at `seconds` (0.5 s, else the first), no wider than `maxWidth`; nil when it cannot be read
    /// within `timeout` (the server does not serve ranges, a format AVFoundation cannot open ...). Cached per URL.
    public static func frame(from request: MediaRequest, at seconds: Double = 0.5, maxWidth: CGFloat = 480,
                             timeout: Duration = .seconds(10)) async -> Data? {
        let key = request.url.absoluteString as NSString
        if let hit = cache.object(forKey: key) { return hit as Data }
        let data = await withTaskGroup(of: Data?.self) { group in
            group.addTask { await grab(request, seconds, maxWidth) }
            group.addTask { try? await Task.sleep(for: timeout); return nil }
            let first = await group.next() ?? nil
            group.cancelAll()
            return first
        }
        if let data { cache.setObject(data as NSData, forKey: key) }
        return data
    }

    private static func grab(_ request: MediaRequest, _ seconds: Double, _ maxWidth: CGFloat) async -> Data? {
        let generator = AVAssetImageGenerator(asset: AppVideoPlayerModel.asset(request))
        generator.appliesPreferredTrackTransform = true
        generator.maximumSize = CGSize(width: maxWidth, height: maxWidth)
        generator.requestedTimeToleranceBefore = .positiveInfinity
        generator.requestedTimeToleranceAfter = .positiveInfinity
        for at in [seconds, 0] {
            if Task.isCancelled { return nil }
            if let (image, _) = try? await generator.image(at: CMTime(seconds: at, preferredTimescale: 600)),
               let png = NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:]) { return png }
        }
        return nil
    }

    /// Forgets the stills (after the attachment storage is cleared).
    public static func clearCache() { cache.removeAllObjects() }
}
