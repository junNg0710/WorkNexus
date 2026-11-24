/// Ported from: lib/features/chat/presentation/widgets/chat_image_body.dart (+ chat_cover_decode.dart)
import AppKit
import CoreDomain
import CoreUI
import ImageIO
import SwiftUI

private let imageMaxSide: CGFloat = 360
private let placeholderSize = CGSize(width: 280, height: 180)
private let stickerSide: CGFloat = 160

/// An image without a bubble, rounded. Its box is sized from the width and height the message carries before any byte arrives, so
/// the list does not jump. It shows the server's thumbnail when there is one; until the original is downloaded a badge shows its
/// size, and a click downloads it and then opens the viewer. Sticker images (webp / tgs) are shown small and animated.
struct ChatImageBody: View {
    @Environment(\.appTheme) private var theme
    @Environment(\.chatServices) private var services
    /// False in a chat kept open behind another one: a GIF does not play there.
    @KeptAwake private var animationsRun
    let message: ChatMessage
    let image: ImageContent
    let state: ChatThreadState
    @State private var data: Data?
    /// The picture decoded at display size, off the main thread, once per load. Decoding it in `body` ran again on every
    /// redraw of the row, on the main thread - a share of the stutter scrolling past pictures.
    @State private var picture: NSImage?
    /// A GIF (or an animated WebP) sent as a picture: it plays.
    @State private var animated = false
    @State private var failed = false
    @State private var viewing = false
    @State private var error: String?

    init(message: ChatMessage, image: ImageContent, state: ChatThreadState) {
        self.message = message; self.image = image; self.state = state
        // Seen before (scrolled back into view): the picture is there in the row's first frame - no skeleton, and no
        // second draw of the row once a task has found it.
        _picture = State(initialValue: isSticker ? nil : Self.decoded.object(forKey: decodedKey))
    }

    private var key: TransferKey { TransferKey(accountId: message.accountId, content: .image(image)) }
    private var isSticker: Bool { IsStickerImage()(image) }

    /// The image scaled down (never up) into the max box, or a fixed placeholder when the sender did not record a size.
    private var size: CGSize {
        if isSticker { return CGSize(width: stickerSide, height: stickerSide) }
        guard let w = image.width.map(CGFloat.init), let h = image.height.map(CGFloat.init), w > 0, h > 0 else { return placeholderSize }
        let scale = min(1, imageMaxSide / w, imageMaxSide / h)
        return CGSize(width: w * scale, height: h * scale)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: theme.spacing.s4) {
            ZStack(alignment: .bottomLeading) {
                content
                if image.hasThumb, !isSticker {
                    AttachmentDownloadBadge(key: key, size: image.size).padding(theme.spacing.s8)
                }
                if message.sendState != .sent { ChatUploadOverlay(message: message).frame(maxWidth: .infinity, maxHeight: .infinity) }
            }
            .frame(width: size.width, height: size.height)
            .clipShape(RoundedRectangle(cornerRadius: isSticker ? 0 : theme.radii.lg))
            .contentShape(Rectangle())
            .onTapGesture { open() }
            if let error { Text(error).font(theme.typography.caption).foregroundStyle(theme.colors.red) }
        }
        .task(id: message.gid + String(message.sendState == .sent)) { await load() }
        .sheet(isPresented: $viewing) { ChatImageViewer(accountId: message.accountId, chatGid: message.chatGid, item: .image(image)) }
    }

    @ViewBuilder private var content: some View {
        if let data, isSticker {
            StickerBytesView(data: data, animated: true)
        } else if let data, animated {
            // A GIF (or an animated WebP) sent as a picture plays in the chat.
            FrameAnimatedImage(data: data, animated: animationsRun)
        } else if let picture {
            Image(nsImage: picture).resizable().scaledToFill()
        } else {
            Placeholder(broken: failed || (data != nil && !isSticker))
        }
    }

    private func load() async {
        // Seen before (scrolled back into view): the decoded picture is there, and its bytes are not read again (opening
        // it reads the original).
        if !isSticker, let hit = Self.decoded.object(forKey: decodedKey) { picture = hit; return }
        // Small images travel inline; an own image not uploaded yet shows the picked bytes.
        if let b64 = image.inlineBase64, let d = Data(base64Encoded: b64, options: .ignoreUnknownCharacters) { await show(d); return }
        guard let repo = services?.chat else { failed = true; return }
        if image.fileId == 0, message.sendState != .sent, let local = repo.pendingUploadBytes(messageGid: message.gid) { await show(local); return }
        switch await repo.loadAttachment(accountId: message.accountId, content: .image(image), thumbnail: image.hasThumb) {
        case .success(let d): await show(d)
        case .failure: failed = true
        }
    }

    /// Pictures already decoded at display size, so a row scrolled back into view shows at once (no placeholder, no
    /// second decode).
    nonisolated(unsafe) private static let decoded: NSCache<NSString, NSImage> = { let c = NSCache<NSString, NSImage>(); c.totalCostLimit = 96 << 20; return c }()
    private var decodedKey: NSString { "\(message.gid)|\(image.fileId)|\(image.name)|\(Int(size.width))|\(image.hasThumb)" as NSString }

    /// Decodes `d` at display size off the main thread, then shows it.
    private func show(_ d: Data) async {
        if isSticker { data = d; return }
        if let hit = Self.decoded.object(forKey: decodedKey) { picture = hit; data = d; return }
        let maxPixel = size.width * 2
        let (decoded, moving) = await PerformanceLog.measure("chat: decode picture \(image.width ?? 0)×\(image.height ?? 0)", slowerThan: 0.03) {
            await Task.detached(priority: .userInitiated) { (Self.downsampled(d, maxPixel: maxPixel), StickerDecoder.isAnimated(d)) }.value
        }
        animated = moving; picture = moving ? nil : decoded; data = d
        if let decoded, !moving { Self.decoded.setObject(decoded, forKey: decodedKey, cost: Int(decoded.size.width * decoded.size.height * 4)) }
    }

    /// Downloads (if needed) and opens the viewer.
    private func open() {
        guard let repo = services?.chat, message.sendState == .sent || image.fileId > 0 else { return }
        error = nil
        Task {
            if await AttachmentTransfers.shared.isCached(key, repo) { viewing = true; return }
            switch await AttachmentTransfers.shared.download(key, repo) {
            case .success?: viewing = true
            case .failure(let f)? where !isCancelled(f): error = f.message
            default: break
            }
        }
    }

    /// Decodes at display size: full-size decodes of every image passing by make fast scrolling stutter. Decoded here
    /// and now (`ShouldCacheImmediately`), not on the main thread when the picture is first drawn.
    nonisolated static func downsampled(_ data: Data, maxPixel: CGFloat) -> NSImage? {
        guard let src = CGImageSourceCreateWithData(data as CFData, [kCGImageSourceShouldCache: false] as CFDictionary) else { return nil }
        let opts: [CFString: Any] = [kCGImageSourceCreateThumbnailFromImageAlways: true, kCGImageSourceCreateThumbnailWithTransform: true,
                                     kCGImageSourceShouldCacheImmediately: true, kCGImageSourceThumbnailMaxPixelSize: max(1, maxPixel)]
        return CGImageSourceCreateThumbnailAtIndex(src, 0, opts as CFDictionary).map { NSImage(cgImage: $0, size: .zero) }
    }
}

func isCancelled(_ f: Failure) -> Bool { if case .cancelled = f { true } else { false } }

/// A skeleton while an image loads, a broken-image glyph when it cannot.
struct Placeholder: View {
    @Environment(\.appTheme) private var theme
    let broken: Bool
    var body: some View {
        ZStack {
            Rectangle().fill(broken ? theme.colors.panel : theme.colors.skel)
            if broken { Image(systemName: "photo.badge.exclamationmark").foregroundStyle(theme.colors.tx3) }
        }
    }
}
