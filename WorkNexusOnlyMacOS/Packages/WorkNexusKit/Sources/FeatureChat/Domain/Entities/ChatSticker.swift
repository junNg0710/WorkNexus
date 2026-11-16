import Foundation

/// A sticker image: one bundled with the app (`custom` false, `location` is the asset key) or one kept on this device
/// (`custom` true, `location` is the file path). Sent as an ordinary image message, so every client shows it.
/// Ported from: lib/features/chat/domain/entities/chat_sticker.dart
public struct ChatSticker: Hashable, Sendable, Identifiable {
    /// Unique among all stickers (the location).
    public var id: String
    /// The set it belongs to: a bundled folder name, an imported set's id, or empty for the user's own stickers.
    public var pack: String
    /// The set's name to show, when it is not `pack` itself (an imported set's title).
    public var packTitle: String?
    /// File name sent with the image.
    public var name: String
    public var location: String
    public var custom: Bool
    public init(id: String, pack: String, packTitle: String? = nil, name: String, location: String, custom: Bool = false) {
        self.id = id; self.pack = pack; self.packTitle = packTitle; self.name = name; self.location = location; self.custom = custom
    }
}

/// How a Telegram sticker is drawn: a still image, a Lottie animation (`.tgs`) or a short video (`.webm`).
public enum RemoteStickerKind: String, Hashable, Sendable { case still, animated, video }

public struct RemoteSticker: Hashable, Sendable {
    public var fileId: String
    public var kind: RemoteStickerKind
    public var thumbnailFileId: String?
    public var emoji: String
    public init(fileId: String, kind: RemoteStickerKind, thumbnailFileId: String? = nil, emoji: String = "") {
        self.fileId = fileId; self.kind = kind; self.thumbnailFileId = thumbnailFileId; self.emoji = emoji
    }
}

/// A sticker set as Telegram lists it, before any file is fetched.
/// Ported from: lib/features/chat/domain/entities/remote_sticker_set.dart
public struct RemoteStickerSet: Hashable, Sendable {
    public var name: String
    public var title: String
    public var stickers: [RemoteSticker]
    public init(name: String, title: String, stickers: [RemoteSticker]) { self.name = name; self.title = title; self.stickers = stickers }
}
