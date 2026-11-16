/// Ported from: lib/features/chat/presentation/widgets/chat_sticker_image.dart (+ animated sticker rendering)
import AppKit
import Compression
import CoreUI
import Lottie
import SwiftUI

/// Draws a sticker/image from its bytes: a Telegram `.tgs` (gzipped Lottie JSON) as a looping animation, anything else through
/// `NSImage` (animated GIFs play when `animated`). Falls back to a broken-image glyph.
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
            AnimatedImage(image: image, animated: animated)
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
