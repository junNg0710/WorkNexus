import Foundation

/// Reduces text to the form message search compares: lower case, without Vietnamese diacritics (`Đường` → `duong`) and
/// with runs of whitespace collapsed. SQLite's `LIKE` folds case for ASCII only, so both the stored message and the query
/// go through this.
/// Ported from: lib/features/chat/domain/usecases/fold_search_text.dart
public struct FoldSearchText: Sendable {
    public init() {}
    private static let mention = RX(#"\[@([^\]]+)\]\(@#\d+\)"#)
    private static let link = RX(#"\[([^\]]*)\]\(([^)\s]*)\)"#)
    private static let markdownMarks = RX(#"[*~`]"#)
    private static let combining = RX("[\u{0300}-\u{036F}]")
    private static let space = RX(#"\s+"#)
    private static let bases: [(Character, String)] = [
        ("a", "àáạảãâầấậẩẫăằắặẳẵ"), ("e", "èéẹẻẽêềếệểễ"), ("i", "ìíịỉĩ"), ("o", "òóọỏõôồốộổỗơờớợởỡ"),
        ("u", "ùúụủũưừứựửữ"), ("y", "ỳýỵỷỹ"), ("d", "đ"),
    ]
    private static let baseOf: [UInt32: UInt32] = {
        var m: [UInt32: UInt32] = [:]
        for (base, accented) in bases { for u in accented.unicodeScalars { m[u.value] = base.unicodeScalars.first!.value } }
        return m
    }()

    /// How much of a code message is searched.
    private static let codeLimit = 4000

    /// The searchable text of a stored message: what it says, a file's or picture's name, a shared link's address and
    /// title, a code message's name and code. Nil for one with nothing to search (an emoji, a notice).
    public func ofMessage(contentType: String, content: String) -> String? {
        switch contentType {
        case "plain", "text": break
        case "file", "image": return field("name", of: content).map(callAsFunction)
        case "object": return callAsFunction([field("title", of: content), field("url", of: content)].compactMap { $0 }.joined(separator: " "))
        case "code":
            return callAsFunction([field("name", of: content), field("code", of: content).map { String($0.prefix(Self.codeLimit)) }]
                .compactMap { $0 }.joined(separator: " "))
        default: return nil
        }
        var text = Mentions.repair(content.replacingOccurrences(of: "\u{FFFC}", with: ""))
        text = Self.mention.replace(text) { "@\($0[1] ?? "")" }
        text = Self.link.replace(text) { "\($0[1] ?? "") \($0[2] ?? "")" }
        if contentType == "text" { text = Self.markdownMarks.replace(text) { _ in "" } }
        return callAsFunction(DecodeEmoji()(text))
    }

    /// One text field of a message stored as JSON.
    private func field(_ name: String, of content: String) -> String? {
        guard let object = try? JSONSerialization.jsonObject(with: Data(content.utf8)) as? [String: Any] else { return nil }
        return object[name] as? String
    }

    public func callAsFunction(_ text: String) -> String {
        var scalars = String.UnicodeScalarView()
        for u in text.lowercased().unicodeScalars { scalars.append(Unicode.Scalar(Self.baseOf[u.value] ?? u.value) ?? u) }
        var out = Self.combining.replace(String(scalars)) { _ in "" }
        out = Self.space.replace(out) { _ in " " }
        return out.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

/// Moves whitespace at the end of emphasis out of its markers: `**word **` → `**word** `. Markdown does not count
/// emphasis that ends in a space; this catches Markdown typed by hand.
/// Ported from: lib/features/chat/domain/usecases/tidy_markdown_emphasis.dart
public struct TidyMarkdownEmphasis: Sendable {
    public init() {}
    private static let patterns = [
        RX(#"(\*\*)(?!\s)([^\n]*?\S)(\s+)(\*\*)"#), RX(#"(~~)(?!\s)([^\n]*?\S)(\s+)(~~)"#),
        RX(#"(<u>)(?!\s)([^\n]*?\S)(\s+)(</u>)"#), RX(#"(?<!\*)(\*)(?![\s*])([^\n]*?\S)(\s+)(\*)(?!\*)"#),
    ]
    public func callAsFunction(_ text: String) -> String {
        Self.patterns.reduce(text) { out, p in p.replace(out) { "\($0[1] ?? "")\($0[2] ?? "")\($0[4] ?? "")\($0[3] ?? "")" } }
    }
}
