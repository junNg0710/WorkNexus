import Foundation

/// Writes chat messages as the plain-text transcript an AI prompt quotes, oldest first, one message a line:
/// `[18/11 09:05] Lan: the text`.
///
/// Deleted messages and the server's notices are left out; a picture or a file is named rather than sent. Each message is
/// cut to `maxMessageChars` and, when the whole would pass `maxChars`, the oldest messages are dropped so the newest — what a
/// summary or a reply needs most — always fit.
/// Ported from: lib/features/chat/domain/usecases/build_chat_transcript.dart
public struct BuildChatTranscript: Sendable {
    public var maxChars: Int
    public var maxMessageChars: Int
    public init(maxChars: Int = 12000, maxMessageChars: Int = 600) { self.maxChars = maxChars; self.maxMessageChars = maxMessageChars }

    /// Mentions are sent as `[@Name](@#id)`; the model only needs `@Name`.
    private static let mention = RX(#"\[@([^\]]+)\]\(@#\d+\)"#)
    private static let lineBreak = RX(#"\s*\n\s*"#)

    /// `nameOf` names a sender by user id; the user's own messages are written as `selfName`. Returns the transcript and how
    /// many messages it holds.
    public func callAsFunction(_ messages: [ChatMessage], nameOf: (Int) -> String, selfName: String) -> (text: String, count: Int) {
        let ordered = messages.sorted { $0.sentAt < $1.sentAt }
        var byServerId: [Int: ChatMessage] = [:]
        for m in ordered { if let id = m.serverId { byServerId[id] = m } }
        func sender(_ m: ChatMessage) -> String { m.isMine ? selfName : nameOf(m.senderId) }

        var lines: [String] = []
        var total = 0
        for message in ordered.reversed() {
            if message.deleted || message.isNotice { continue }
            guard let body = Self.body(of: message.content), !body.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { continue }
            let reply = message.replyToId.flatMap { byServerId[$0] }.map { " (↪ \(sender($0)))" } ?? ""
            let line = "[\(Self.stamp(message.sentAt))] \(sender(message))\(reply): \(clip(body))"
            if total + line.utf16.count > maxChars && !lines.isEmpty { break }
            lines.append(line)
            total += line.utf16.count + 1
        }
        return (lines.reversed().joined(separator: "\n"), lines.count)
    }

    static func body(of content: MessageContent) -> String? {
        switch content {
        case .text(let text, _): return mention.replace(text) { "@\($0[1] ?? "")" }
        case .emoji(let emoji): return emoji
        case .image: return "[image]"
        case .file(let file): return "[file: \(file.name)]"
        case .link(let url, let title): return title.map { "\($0) (\(url))" } ?? url
        case .code(let code, let language, _): return "[code\(language.map { " \($0)" } ?? "")] \(code)"
        case .notification(let n):
            return [n.title, n.text].compactMap { $0 }.filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
                .joined(separator: ": ")
        case .unsupported: return nil
        }
    }

    /// One line per message: line breaks become spaces.
    private func clip(_ text: String) -> String {
        let flat = Self.lineBreak.replace(text) { _ in " " }.trimmingCharacters(in: .whitespacesAndNewlines)
        return flat.count <= maxMessageChars ? flat : String(flat.prefix(maxMessageChars)) + "…"
    }

    private static func stamp(_ at: Date) -> String {
        let c = Calendar.current.dateComponents([.day, .month, .hour, .minute], from: at)
        func two(_ n: Int?) -> String { String(format: "%02d", n ?? 0) }
        return "\(two(c.day))/\(two(c.month)) \(two(c.hour)):\(two(c.minute))"
    }
}

/// The JSON object (or, with `array`, list) in a model's reply, which may wrap it in prose or a code fence; nil when there is
/// none or it does not parse.
/// Ported from: lib/features/chat/domain/usecases/extract_ai_json.dart
public enum ExtractAiJson {
    public static func extract(_ reply: String, array: Bool = false) -> Any? {
        guard let start = reply.firstIndex(of: array ? "[" : "{"), let end = reply.lastIndex(of: array ? "]" : "}"), start < end,
              let data = String(reply[start...end]).data(using: .utf8) else { return nil }
        return try? JSONSerialization.jsonObject(with: data, options: [.fragmentsAllowed])
    }

    /// The non-blank strings of a JSON list; anything else gives none.
    public static func strings(_ value: Any?) -> [String] {
        guard let list = value as? [Any] else { return [] }
        return list.compactMap { ($0 as? String)?.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
    }

    /// A JSON scalar as text (`"Minh"`, `3`); nil for null, a list or an object.
    static func text(_ value: Any?) -> String? {
        switch value {
        case let s as String: return s
        case let n as NSNumber: return n.stringValue
        default: return nil
        }
    }
}
