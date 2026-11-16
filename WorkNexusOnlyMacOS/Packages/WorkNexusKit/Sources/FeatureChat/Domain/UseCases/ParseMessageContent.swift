import Foundation

/// Parses xxd's `contentType` + `content` into a `MessageContent`.
/// Ported from: lib/features/chat/domain/usecases/parse_message_content.dart
public struct ParseMessageContent: Sendable {
    public init() {}

    private static let objectReplacement = "\u{FFFC}"
    private static let shortname = RX(#":[a-z0-9_+\-]+:"#)
    private static let decodeEmoji = DecodeEmoji()

    public static func repairMentions(_ text: String) -> String { Mentions.repair(text) }

    public func callAsFunction(_ contentType: String, _ content: String) -> MessageContent {
        switch contentType {
        case "plain", "text":
            let text = content.replacingOccurrences(of: Self.objectReplacement, with: "")
            // Nothing but lost objects: say so rather than show an empty bubble.
            if text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && text.utf16.count != content.utf16.count {
                return .unsupported("object")
            }
            return .text(Self.decodeEmoji(Mentions.repair(text)), markdown: contentType == "text")
        case "image", "file":
            if let c = Self.media(contentType, content) { return c }
        case "emotion":
            // Newer official clients send a large emoji as its own content type, with `{type: emoji, content: :smile:}`
            // (or, from some builds, just the shortname).
            let inline = Self.object(content)?["content"]?.string ?? content.trimmingCharacters(in: .whitespacesAndNewlines)
            if !inline.isEmpty { return Self.emoji(inline) }
        case "code":
            // `{lang: go, code: …, name: main.go}`.
            if let json = Self.object(content), let code = json["code"]?.string {
                return .code(code, language: Self.str(json["lang"]), name: Self.str(json["name"]))
            }
        case "notification":
            if let json = Self.object(content) { return Self.notification(json) }
        case "object":
            if let json = Self.object(content), json["type"]?.string == "url", let url = json["url"]?.string, !url.isEmpty {
                let title = json["title"]?.string
                return .link(url: url, title: title.flatMap { $0.isEmpty ? nil : $0 })
            }
        default: break
        }
        return .unsupported(contentType)
    }

    private static func media(_ contentType: String, _ content: String) -> MessageContent? {
        let json = object(content)
        let inline = json?["content"]?.string
        // The official client's large emoji: `{type: emoji, content: :smile:}`.
        if contentType == "image", json?["type"]?.string == "emoji", let inline, !inline.isEmpty { return emoji(inline) }
        if contentType == "image", json?["type"]?.string == "base64", let inline, !inline.isEmpty {
            // Newer clients send a data URI (`data:image/png;base64,…`).
            let b64 = inline.hasPrefix("data:") ? String(inline[inline.index(after: inline.firstIndex(of: ",") ?? inline.startIndex)...]) : inline
            return .image(ImageContent(fileId: 0, name: json?["name"]?.string ?? "", size: json?["size"]?.intValue ?? 0,
                                       time: json?["time"]?.intValue ?? 0, width: json?["width"]?.intValue,
                                       height: json?["height"]?.intValue, inlineBase64: b64))
        }
        guard let json, let name = json["name"]?.string else { return nil }
        let id = json["id"]?.intValue
        let size = json["size"]?.intValue
        guard let id else {
            // A file or image still uploading (no server id yet): show it by name — an image at its real size, so the
            // bubble keeps its shape when the upload lands.
            guard let size else { return nil }
            return contentType == "image"
                ? .image(ImageContent(fileId: 0, name: name, size: size, time: 0, width: json["width"]?.intValue, height: json["height"]?.intValue))
                : .file(FileContent(fileId: 0, name: name, size: size, time: 0))
        }
        let time = json["time"]?.intValue ?? 0
        let mime = json["type"]?.string
        return contentType == "image"
            ? .image(ImageContent(fileId: id, name: name, size: size ?? 0, time: time, mimeType: mime,
                                  width: json["width"]?.intValue, height: json["height"]?.intValue,
                                  hasThumb: json["hasThumb"] == .bool(true)))
            : .file(FileContent(fileId: id, name: name, size: size ?? 0, time: time, mimeType: mime))
    }

    private static func emoji(_ inline: String) -> MessageContent {
        let e = decodeEmoji(inline)
        return shortname.hasMatch(e) ? .text(e, markdown: false) : .emoji(e)
    }

    private static func notification(_ json: JSONObject) -> MessageContent {
        var n = json
        if n["contentType"]?.string == "object", let inner = n["content"]?.string, let o = object(inner) {
            for (k, v) in o.pairs { n[k] = v }
        }
        // ZenTao action cards ("X assigned 1 Bug") put the item as JSON in the text itself, without saying it is an
        // object: show the item, not the raw JSON.
        let isObject = n["contentType"]?.string == "object"
        let card = !isObject && n["content"]?.string != nil ? zentaoCard(object(n["content"]!.string!)) : nil
        let actionsValue = n["actions"]
        var actions: [NotificationAction] = []
        let rawActions: [JSONValue] = actionsValue?.array ?? (actionsValue.map { $0.isNull ? [] : [$0] } ?? [])
        for a in rawActions {
            if case .object(let o) = a, let url = str(o["url"]) {
                actions.append(NotificationAction(label: str(o["label"]) ?? url, url: url))
            }
        }
        let sender: String? = {
            switch n["sender"] {
            case .object(let m)?: return str(m["realname"]) ?? str(m["name"]) ?? str(m["displayName"])
            case .string(let s)?: return s.isEmpty ? nil : s
            default: return nil
            }
        }()
        let text: String
        if let card { text = card.text }
        else if let c = n["content"]?.string, !isObject { text = decodeEmoji(c) }
        else { text = "" }
        return .notification(NotificationContent(
            title: str(n["title"]), subtitle: str(n["subtitle"]) ?? card?.project, text: text,
            markdown: card == nil && n["contentType"]?.string != "plain",
            // The card's own link first: the outer one may be the official client's `xxc:openInApp/…` wrapper.
            url: card?.url ?? unwrapAppUrl(str(n["url"])), actions: actions, sender: sender))
    }

    private static func zentaoCard(_ json: JSONObject?) -> (text: String, url: String?, project: String?)? {
        guard let json else { return nil }
        let name = str(json["objectName"]) ?? str(json["name"])
        let url = str(json["cardURL"])
        if name == nil && url == nil { return nil }
        let idRaw = json["id"].flatMap { $0.isNull ? nil : $0 } ?? json["object"].flatMap { $0.isNull ? nil : $0 }
        let id = str(.string(idRaw.map { JS.toString($0) } ?? ""))
        let count = json["count"]?.intValue ?? 1
        var parts: [String] = []
        if let id { parts.append("#\(id)") }
        if let name { parts.append(name) }
        // Only the first of several items is named.
        if count > 1 { parts.append("(+\(count - 1))") }
        return (parts.joined(separator: " "), url, str(json["headSubTitle"]) ?? str(json["headTitle"]))
    }

    private static func unwrapAppUrl(_ url: String?) -> String? {
        let prefix = "xxc:openInApp/"
        guard let url, url.hasPrefix(prefix) else { return url }
        let rest = String(url.dropFirst(prefix.count))
        guard let slash = rest.firstIndex(of: "/") else { return url }
        guard let inner = String(rest[rest.index(after: slash)...]).removingPercentEncoding else { return url }
        return inner.hasPrefix("http") ? inner : url
    }

    private static func str(_ v: JSONValue?) -> String? {
        guard case .string(let s)? = v else { return nil }
        let t = s.trimmingCharacters(in: .whitespacesAndNewlines)
        return t.isEmpty ? nil : t
    }

    private static func object(_ content: String) -> JSONObject? {
        guard let j = try? JSONValue.parse(content), case .object(let o) = j else { return nil }
        return o
    }
}
