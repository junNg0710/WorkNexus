/// Not in the Flutter app: what the media viewer steps through.
import Foundation

/// One thing the viewer shows: a picture (a GIF plays) or a video.
public enum ChatMediaItem: Hashable, Sendable {
    case image(ImageContent)
    case video(FileContent)

    public var name: String {
        switch self { case .image(let i): i.name; case .video(let f): f.name }
    }
    public var content: MessageContent {
        switch self { case .image(let i): .image(i); case .video(let f): .file(f) }
    }
    public var size: Int {
        switch self { case .image(let i): i.size; case .video(let f): f.size }
    }
}

/// Whether a picture message is a sticker: a Telegram sticker (tgs), a sticker-sized WebP / GIF (512 px at most), or a
/// picture named like one of the stickers this Mac knows (the bundled packs, the user's own) at sticker size.
public struct IsStickerImage: Sendable {
    public static let maxSide = 512
    public init() {}

    public func callAsFunction(_ image: ImageContent, knownNames: Set<String> = []) -> Bool {
        let ext = (image.name as NSString).pathExtension.lowercased()
        if ext == "tgs" { return true }
        guard let w = image.width, let h = image.height, max(w, h) <= Self.maxSide else { return false }
        return ext == "webp" || ext == "gif" || knownNames.contains(image.name)
    }
}

/// The pictures and videos of a chat's attachments the viewer steps through, in the order given: stickers are left out
/// (they are reactions, not media), except the one on show when it is a sticker itself.
public struct ListViewerMedia: Sendable {
    public init() {}

    public func callAsFunction(_ messages: [ChatMessage], current: ChatMediaItem?, stickerNames: Set<String>) -> [ChatMediaItem] {
        let isSticker = IsStickerImage()
        return messages.compactMap { m -> ChatMediaItem? in
            guard !m.deleted else { return nil }
            switch m.content {
            case .image(let i):
                let item = ChatMediaItem.image(i)
                return isSticker(i, knownNames: stickerNames) && item != current ? nil : item
            case .file(let f): return isVideoFile(f) ? .video(f) : nil
            default: return nil
            }
        }
    }
}
