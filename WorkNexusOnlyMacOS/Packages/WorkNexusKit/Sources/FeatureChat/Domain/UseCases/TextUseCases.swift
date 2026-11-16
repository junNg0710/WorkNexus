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

    /// The searchable text of a stored message, or nil for one that is not text.
    public func ofMessage(contentType: String, content: String) -> String? {
        guard contentType == "plain" || contentType == "text" else { return nil }
        var text = Mentions.repair(content.replacingOccurrences(of: "\u{FFFC}", with: ""))
        text = Self.mention.replace(text) { "@\($0[1] ?? "")" }
        text = Self.link.replace(text) { "\($0[1] ?? "") \($0[2] ?? "")" }
        if contentType == "text" { text = Self.markdownMarks.replace(text) { _ in "" } }
        return callAsFunction(DecodeEmoji()(text))
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
