/// Ported from: lib/features/chat/presentation/widgets/chat_sticker_image.dart (+ animated sticker rendering)
import AppKit
import Compression
import ImageIO
import CoreUI
import Lottie
import SwiftUI

/// Draws a sticker/image from its bytes: a Telegram `.tgs` (gzipped Lottie JSON) as a looping animation, an animated GIF /
/// WebP / PNG through `FrameAnimatedImage` (it plays when `animated`), anything else through `NSImage`. Falls back to a
/// broken-image glyph.
struct StickerBytesView: View {
    @Environment(\.appTheme) private var theme
    let data: Data
    var animated = true

    var body: some View {
        switch StickerDecoder.decode(data) {
        case .lottie(let animation):
            if animated {
                LottieView(animation: animation).playbackMode(.playing(.toProgress(1, loopMode: .loop))).resizable()
            } else {
                LottieView(animation: animation).playbackMode(.paused(at: .progress(0.4))).resizable()
            }
        case .image(let image):
            // `NSImage` sees the frames of a GIF only: an animated WebP showed its first frame for ever.
            if StickerDecoder.isAnimated(data) { FrameAnimatedImage(data: data, animated: animated) }
            else { AnimatedImage(image: image, animated: animated) }
        case .none:
            Image(systemName: "photo.badge.exclamationmark").foregroundStyle(theme.colors.tx3)
        }
    }
}

enum DecodedSticker {
    case lottie(LottieAnimation)
    case image(NSImage)
    case none
}

enum StickerDecoder {
    private static let cache = NSCache<NSData, NSImage>()

    static func isTgs(_ data: Data) -> Bool { data.count > 2 && data[data.startIndex] == 0x1F && data[data.startIndex + 1] == 0x8B }

    static func decode(_ data: Data) -> DecodedSticker {
        if isTgs(data) {
            if let json = gunzip(data), let a = try? LottieAnimation.from(data: json) { return .lottie(a) }
            return .none
        }
        let key = data as NSData
        if let hit = cache.object(forKey: key) { return .image(hit) }
        guard let image = NSImage(data: data) else { return .none }
        cache.setObject(image, forKey: key, cost: data.count)
        return .image(image)
    }

    private static let animatedCache = NSCache<NSData, NSNumber>()

    /// Whether the image holds more than one frame (an animated GIF, WebP or PNG), as ImageIO reads it.
    static func isAnimated(_ data: Data) -> Bool {
        let key = data as NSData
        if let hit = animatedCache.object(forKey: key) { return hit.boolValue }
        let frames = CGImageSourceCreateWithData(data as CFData, nil).map(CGImageSourceGetCount) ?? 0
        animatedCache.setObject(NSNumber(value: frames > 1), forKey: key)
        return frames > 1
    }

    /// Inflates a gzip stream: skips the header, inflates the raw deflate body (Apple's `COMPRESSION_ZLIB` takes no zlib header).
    static func gunzip(_ data: Data) -> Data? {
        let b = [UInt8](data)
        guard b.count > 18, b[0] == 0x1F, b[1] == 0x8B, b[2] == 8 else { return nil }
        let flags = b[3]
        var i = 10
        if flags & 4 != 0 { guard i + 2 <= b.count else { return nil }; i += 2 + Int(b[i]) + Int(b[i + 1]) << 8 }
        if flags & 8 != 0 { while i < b.count, b[i] != 0 { i += 1 }; i += 1 }
        if flags & 16 != 0 { while i < b.count, b[i] != 0 { i += 1 }; i += 1 }
        if flags & 2 != 0 { i += 2 }
        guard i < b.count - 8 else { return nil }
        let body = Data(b[i..<(b.count - 8)])
        return try? (body as NSData).decompressed(using: .zlib) as Data
    }
}

/// An `NSImageView` so animated GIFs play; scales proportionally.
struct AnimatedImage: NSViewRepresentable {
    let image: NSImage
    var animated: Bool

    func makeNSView(context: Context) -> NSImageView {
        let v = NSImageView()
        v.imageScaling = .scaleProportionallyUpOrDown
        v.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        v.setContentCompressionResistancePriority(.defaultLow, for: .vertical)
        return v
    }

    func updateNSView(_ v: NSImageView, context: Context) {
        if v.image !== image { v.image = image }
        v.animates = animated
    }
}

/// Plays an animated GIF / WebP / PNG frame by frame with ImageIO, scaled to fit; still on its first frame when not `animated`.
/// It plays only while it is in a window, so a sticker scrolled away (or in a closed panel) costs nothing.
struct FrameAnimatedImage: NSViewRepresentable {
    let data: Data
    var animated: Bool

    func makeNSView(context: Context) -> FramePlayerView {
        let v = FramePlayerView()
        v.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        v.setContentCompressionResistancePriority(.defaultLow, for: .vertical)
        return v
    }

    func updateNSView(_ v: FramePlayerView, context: Context) { v.show(data, animated: animated) }
}

final class FramePlayerView: NSView {
    private var data: Data?
    private var animated = false
    /// Bumped whenever what plays changes: a running animation of an earlier generation stops at its next frame.
    private var generation = 0
    private(set) var isPlaying = false

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        layer?.contentsGravity = .resizeAspect
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    func show(_ data: Data, animated: Bool) {
        guard data != self.data || animated != self.animated else { return }
        self.data = data; self.animated = animated
        restart()
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        restart()
    }

    private func restart() {
        generation += 1
        isPlaying = false
        guard let data else { layer?.contents = nil; return }
        if let source = CGImageSourceCreateWithData(data as CFData, nil) { layer?.contents = CGImageSourceCreateImageAtIndex(source, 0, nil) }
        guard animated, window != nil else { return }
        let mine = generation
        isPlaying = true
        CGAnimateImageDataWithBlock(data as CFData, nil) { [weak self] _, frame, stop in
            guard let self, self.generation == mine else { stop.pointee = true; return }
            self.layer?.contents = frame
        }
    }
}
