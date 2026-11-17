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
    let message: ChatMessage
    let image: ImageContent
    let state: ChatThreadState
    @State private var data: Data?
    @State private var failed = false
    @State private var viewing = false
    @State private var error: String?

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
        if let data {
            if isSticker { StickerBytesView(data: data, animated: true) }
            // A GIF (or an animated WebP) sent as a picture plays in the chat.
            else if StickerDecoder.isAnimated(data) { FrameAnimatedImage(data: data, animated: true) }
            else if let img = Self.downsampled(data, maxPixel: size.width * 2) { Image(nsImage: img).resizable().scaledToFill() }
            else { Placeholder(broken: true) }
        } else {
            Placeholder(broken: failed)
        }
    }

    private func load() async {
        // Small images travel inline; an own image not uploaded yet shows the picked bytes.
        if let b64 = image.inlineBase64, let d = Data(base64Encoded: b64, options: .ignoreUnknownCharacters) { data = d; return }
        guard let repo = services?.chat else { failed = true; return }
        if image.fileId == 0, message.sendState != .sent, let local = repo.pendingUploadBytes(messageGid: message.gid) { data = local; return }
        switch await repo.loadAttachment(accountId: message.accountId, content: .image(image), thumbnail: image.hasThumb) {
        case .success(let d): data = d
        case .failure: failed = true
        }
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

    /// Decodes at display size: full-size decodes of every image passing by make fast scrolling stutter.
    nonisolated static func downsampled(_ data: Data, maxPixel: CGFloat) -> NSImage? {
        guard let src = CGImageSourceCreateWithData(data as CFData, nil) else { return nil }
        let opts: [CFString: Any] = [kCGImageSourceCreateThumbnailFromImageAlways: true, kCGImageSourceCreateThumbnailWithTransform: true,
                                     kCGImageSourceThumbnailMaxPixelSize: maxPixel]
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
