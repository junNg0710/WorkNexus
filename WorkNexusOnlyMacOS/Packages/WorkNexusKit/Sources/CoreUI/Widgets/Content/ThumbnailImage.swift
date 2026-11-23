/// Not in the Flutter app.
import AppKit
import ImageIO
import SwiftUI

/// A small picture of a remote or local image, for grids that scroll: fetched once, shrunk to the size it is drawn at and
/// decoded off the main thread, and kept for the rest of the run, so a card scrolling back into view shows it at once.
/// (`AsyncImage` keeps nothing: every card coming into view fetched and decoded its full-size image again on the main
/// thread — a pet's poster is a whole sprite frame — which made the pet picker stutter.)
public struct ThumbnailImage<Placeholder: View>: View {
    let url: URL?
    let maxPixels: CGFloat
    let contentMode: ContentMode
    let placeholder: Placeholder
    @State private var image: CGImage?

    /// - Parameters:
    ///   - maxPixels: the longest side, in pixels, the picture is shrunk to (twice the points it is drawn at; more for one
    ///     that fills its frame, where the shorter side has to cover it).
    ///   - contentMode: `.fill` for a picture that covers its frame (an avatar); the caller clips it.
    public init(url: URL?, maxPixels: CGFloat, contentMode: ContentMode = .fit, @ViewBuilder placeholder: () -> Placeholder) {
        self.url = url; self.maxPixels = maxPixels; self.contentMode = contentMode; self.placeholder = placeholder()
        _image = State(initialValue: url.flatMap { ThumbnailCache.cached($0, maxPixels) })
    }

    public var body: some View {
        Group {
            if let image {
                Image(decorative: image, scale: 2).resizable().interpolation(.medium).aspectRatio(contentMode: contentMode)
            } else {
                placeholder
            }
        }
        .task(id: url) {
            guard let url else { image = nil; return }
            if let kept = ThumbnailCache.cached(url, maxPixels) { image = kept; return }
            image = await ThumbnailCache.load(url, maxPixels)
        }
    }
}

/// The shrunk pictures, by address and size; loads run off the main thread, and one address is fetched once at a time.
enum ThumbnailCache {
    private final class Box { let image: CGImage; init(_ i: CGImage) { image = i } }
    nonisolated(unsafe) private static let memory: NSCache<NSString, Box> = { let c = NSCache<NSString, Box>(); c.countLimit = 400; return c }()

    private static func key(_ url: URL, _ size: CGFloat) -> NSString { "\(Int(size))|\(url.absoluteString)" as NSString }

    static func cached(_ url: URL, _ size: CGFloat) -> CGImage? { memory.object(forKey: key(url, size))?.image }

    static func load(_ url: URL, _ size: CGFloat) async -> CGImage? {
        let data: Data?
        if url.isFileURL {
            data = await Task.detached(priority: .utility) { try? Data(contentsOf: url) }.value
        } else {
            data = try? await URLSession.shared.data(from: url).0
        }
        guard let data else { return nil }
        let image = await Task.detached(priority: .utility) { downsample(data, size) }.value
        if let image { memory.setObject(Box(image), forKey: key(url, size)) }
        return image
    }

    /// The image no larger than `size` pixels on its longest side, decoded now (not when first drawn).
    static func downsample(_ data: Data, _ size: CGFloat) -> CGImage? {
        guard let source = CGImageSourceCreateWithData(data as CFData, [kCGImageSourceShouldCache: false] as CFDictionary) else { return nil }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceThumbnailMaxPixelSize: max(1, size),
        ]
        return CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary)
    }
}
