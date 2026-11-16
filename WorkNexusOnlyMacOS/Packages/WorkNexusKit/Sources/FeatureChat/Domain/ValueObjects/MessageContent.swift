import Foundation

/// A button under a notification: open `url`.
/// Ported from: lib/features/chat/domain/value_objects/message_content.dart
public struct NotificationAction: Hashable, Sendable {
    public var label: String
    public var url: String
    public init(label: String, url: String) { self.label = label; self.url = url }
}

/// What a chat message carries, parsed from xxd's `contentType` + `content` (see `ParseMessageContent`).
public enum MessageContent: Hashable, Sendable {
    /// Text. xxd's `text` content type is Markdown, `plain` is literal. Mentions stay in wire form `[@Name](@#userId)`.
    case text(String, markdown: Bool = false)
    /// An image. `time` is the upload time in ms (the signed download URL needs it). Small images are sent inline:
    /// then `inlineBase64` holds the bytes and `fileId` is 0.
    case image(ImageContent)
    /// Any other uploaded file; same download rules as an image.
    case file(FileContent)
    /// One emoji sent large, without a bubble.
    case emoji(String)
    /// A notification from ZenTao or xuanbot.
    case notification(NotificationContent)
    /// A shared link card (`object` content of type `url`).
    case link(url: String, title: String?)
    /// A code snippet (`language` is `text` when none was picked).
    case code(String, language: String?, name: String?)
    /// Anything not rendered (cards, conference invites, …).
    case unsupported(String)
}

public struct ImageContent: Hashable, Sendable {
    public var fileId: Int
    public var name: String
    public var size: Int
    public var time: Int
    public var mimeType: String?
    public var width: Int?
    public var height: Int?
    public var inlineBase64: String?
    /// The server stored a smaller preview (`thumb_<name>`) to show inline.
    public var hasThumb: Bool

    public init(fileId: Int, name: String, size: Int, time: Int, mimeType: String? = nil, width: Int? = nil,
                height: Int? = nil, inlineBase64: String? = nil, hasThumb: Bool = false) {
        self.fileId = fileId; self.name = name; self.size = size; self.time = time; self.mimeType = mimeType
        self.width = width; self.height = height; self.inlineBase64 = inlineBase64; self.hasThumb = hasThumb
    }
}

public struct FileContent: Hashable, Sendable {
    public var fileId: Int
    public var name: String
    public var size: Int
    public var time: Int
    public var mimeType: String?
    public init(fileId: Int, name: String, size: Int, time: Int, mimeType: String? = nil) {
        self.fileId = fileId; self.name = name; self.size = size; self.time = time; self.mimeType = mimeType
    }
}

public struct NotificationContent: Hashable, Sendable {
    public var title: String?
    public var subtitle: String?
    public var text: String
    public var markdown: Bool
    public var url: String?
    public var actions: [NotificationAction]
    public var sender: String?
    public init(title: String? = nil, subtitle: String? = nil, text: String = "", markdown: Bool = true, url: String? = nil,
                actions: [NotificationAction] = [], sender: String? = nil) {
        self.title = title; self.subtitle = subtitle; self.text = text; self.markdown = markdown
        self.url = url; self.actions = actions; self.sender = sender
    }
}

public extension MessageContent {
    var asText: (text: String, markdown: Bool)? { if case .text(let t, let m) = self { (t, m) } else { nil } }
    var asImage: ImageContent? { if case .image(let i) = self { i } else { nil } }
    var asFile: FileContent? { if case .file(let f) = self { f } else { nil } }
    var asEmoji: String? { if case .emoji(let e) = self { e } else { nil } }
    var asNotification: NotificationContent? { if case .notification(let n) = self { n } else { nil } }
}
