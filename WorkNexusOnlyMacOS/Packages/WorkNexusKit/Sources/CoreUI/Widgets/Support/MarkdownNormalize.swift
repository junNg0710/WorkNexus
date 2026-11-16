import Foundation

/// Ported from: lib/core/util/markdown_normalize.dart (+ adjacent_mentions.dart)
/// Markdown helpers around the renderer, which covers the common subset of CommonMark/GFM but not every
/// spelling of it.
private let fence = NSRegularExpression(#"^\s*(```|~~~)"#)
private let definition = NSRegularExpression(
    #"^ {0,3}\[([^\]^][^\]]*)\]:\s*<?(\S+?)>?(?:\s+(?:"[^"]*"|'[^']*'|\([^)]*\)))?\s*$"#)
private let reference = NSRegularExpression(#"(!?)\[([^\]]*)\]\[([^\]]*)\]"#)
private let titled = NSRegularExpression(#"\]\((\S+?)\s+(?:"[^"]*"|'[^']*')\)"#)
private let underscoreBold = NSRegularExpression(#"(?<![\w_])__(?=\S)(.+?)(?<=\S)__(?![\w_])"#)
private let underscoreItalic = NSRegularExpression(#"(?<![\w_])_(?=[^\s_])(.+?)(?<=[^\s_])_(?![\w_])"#)
private let plusBullet = NSRegularExpression(#"^(\s*)\+(\s+)"#)
private let emptyQuote = NSRegularExpression(#"^(\s*(?:>\s*)+)$"#)
private let footnoteDef = NSRegularExpression(#"^ {0,3}\[\^([^\]]+)\]:\s*(.*)$"#)
private let abbreviation = NSRegularExpression(#"^ {0,3}\*\[[^\]]+\]:"#)
private let container = NSRegularExpression(#"^ {0,3}:::\s*(\S*)"#)
private let adjacentMention = NSRegularExpression(#"(\]\(@#\d+\))(?=\[@|@)"#)
private let definitionItem = NSRegularExpression(#"^ {0,3}(?::|\s~)\s+(\S.*)$"#)
private let footnoteRef = NSRegularExpression(#"\[\^([^\]]+)\]|\^\[([^\]]+)\]"#)
private let escapeRx = NSRegularExpression(#"\\([!-/:-@\[-`{-~])"#)
private let escapedBase: UInt32 = 0xE000
private let escapedRx = NSRegularExpression("[\u{E021}-\u{E07E}]")
private let superscripts = Array("⁰¹²³⁴⁵⁶⁷⁸⁹")

private let adjacentAt = NSRegularExpression(
    #"(?<![\w./@])@[\p{L}\p{N}_]+(?:-[\p{L}\p{N}_]+)*(?:@[\p{L}\p{N}_]+(?:-[\p{L}\p{N}_]+)*)+(?=$|[^\p{L}\p{N}_./@-]|\.(?!\w))"#)

/// Puts a space between raw mentions jammed together in `text` (`@A@B` → `@A @B`). Packages, fediverse
/// handles and e-mails are left whole.
public func splitAdjacentMentions(_ text: String) -> String {
    adjacentAt.replacing(in: text) { m in
        m[0]!.dropFirst().split(separator: "@").map { "@\($0)" }.joined(separator: " ")
    }
}

private final class Footnotes {
    var texts: [String: String]
    var order: [String] = []
    var numbers: [String: Int] = [:]
    init(_ texts: [String: String]) { self.texts = texts }

    func mark(id: String?, text: String?) -> String {
        let key = id?.lowercased() ?? "\u{0}\(order.count)"
        if let text { texts[key] = text }
        let n: Int
        if let existing = numbers[key] { n = existing } else { order.append(key); n = order.count; numbers[key] = n }
        return String("\(n)".compactMap { $0.wholeNumberValue.map { superscripts[$0] } })
    }

    var section: String {
        (["---"] + order.enumerated().compactMap { i, key in texts[key].map { "\(i + 1). \($0)" } }).joined(separator: "\n")
    }
}

/// Rewrites the Markdown spellings the renderer does not understand into ones it does: reference-style links
/// and images are inlined, link titles dropped, `__bold__`/`_italic_` become `**bold**`/`*italic*`, `+` bullets
/// become `-`, an empty blockquote line keeps its quote. Footnotes become superscripts listed at the end,
/// definition-list items bullets, containers quotes, abbreviation definitions are dropped. Code is left alone.
public func normalizeMarkdown(_ text: String) -> String {
    var refs: [String: String] = [:]
    var notes: [String: String] = [:]
    var kept: [String] = []
    var inFence = false
    var inContainer = false
    var note: String?
    for line in text.components(separatedBy: "\n") {
        if fence.hasMatch(in: line) { inFence.toggle() }
        if inFence { kept.append(inContainer ? "> \(line)" : line); continue }
        // A footnote runs on over indented (or blank) lines.
        if let n = note, line.trimmingCharacters(in: .whitespaces).isEmpty || line.hasPrefix("  ") {
            if !line.trimmingCharacters(in: .whitespaces).isEmpty {
                notes[n] = "\(notes[n] ?? "") \(line.trimmingCharacters(in: .whitespaces))"
            }
            continue
        }
        // Keeps the next block apart from the one before the footnote.
        if note != nil, let last = kept.last, !last.trimmingCharacters(in: .whitespaces).isEmpty { kept.append("") }
        note = nil
        if let def = definition.firstMatch(in: line) {
            refs[def[1]!.lowercased()] = def[2]!
        } else if let def = footnoteDef.firstMatch(in: line) {
            note = def[1]!.lowercased()
            notes[note!] = def[2]!
        } else if abbreviation.hasMatch(in: line) {
            continue
        } else if let f = container.firstMatch(in: line) {
            inContainer = !(f[1] ?? "").isEmpty
            if inContainer { kept.append("> **\(f[1]!)**") }
        } else if let item = definitionItem.firstMatch(in: line) {
            kept.append("- \(item[1]!)")
        } else {
            kept.append(inContainer ? "> \(line)" : line)
        }
    }
    let footnotes = Footnotes(notes)
    inFence = false
    var out: [String] = []
    for line in kept {
        let isFence = fence.hasMatch(in: line)
        if isFence { inFence.toggle() }
        let code = isFence || inFence || line.hasPrefix("    ") || line.hasPrefix("\t")
        out.append(code ? line : normalizeLine(line, refs, footnotes))
    }
    if !footnotes.order.isEmpty { out += ["", footnotes.section] }
    return out.joined(separator: "\n")
}

private func normalizeLine(_ line: String, _ refs: [String: String], _ footnotes: Footnotes) -> String {
    if let q = emptyQuote.firstMatch(in: line) { return "\(q[1]!)\u{00A0}" }   // keeps a quoted blank
    // The renderer has no backslash escapes and would show the backslashes.
    let escaped = escapeRx.replacing(in: line) { m in
        String(UnicodeScalar(escapedBase + m[1]!.unicodeScalars.first!.value)!)
    }
    // Odd parts are inline code spans: left as they are.
    let withBullet = plusBullet.replacing(in: escaped) { "\($0[1]!)-\($0[2]!)" }
    var parts = withBullet.components(separatedBy: "`")
    for i in stride(from: 0, to: parts.count, by: 2) {
        var p = reference.replacing(in: parts[i]) { m in
            let id = ((m[3] ?? "").isEmpty ? m[2]! : m[3]!).lowercased()
            guard let url = refs[id] else { return m[0]! }
            return "\(m[1]!)[\(m[2]!)](\(url))"
        }
        p = footnoteRef.replacing(in: p) { footnotes.mark(id: $0[1], text: $0[2]) }
        p = titled.replacing(in: p) { "](\($0[1]!))" }
        p = underscoreBold.replacing(in: p) { "**\($0[1]!)**" }
        p = underscoreItalic.replacing(in: p) { "*\($0[1]!)*" }
        p = adjacentMention.replacing(in: p) { "\($0[1]!) " }
        parts[i] = splitAdjacentMentions(p)
    }
    return escapedRx.replacing(in: parts.joined(separator: "`")) { m in
        let mark = String(UnicodeScalar(m[0]!.unicodeScalars.first!.value - escapedBase)!)
        // A literal `*` would still pair up into emphasis; the asterisk operator looks the same and does not.
        return mark == "*" ? "\u{2217}" : mark
    }
}

private let markdownSyntax = NSRegularExpression([
    #"^\s{0,3}#{1,6}\s"#, #"^\s*(?:[-*+]|\d+[.)])\s+\S"#, #"^\s{0,3}>"#, #"^\s*(```|~~~)"#,
    #"^\s{0,3}(?:-{3,}|\*{3,}|_{3,})\s*$"#, #"^\s*\|.*\|"#, #"`[^`\n]+`"#,
    #"\*\*\S|\S\*\*|(?<![\w_])__\S"#, #"(?:^|[\s(])[*_][^\s*_][^\n]*[*_](?=$|[\s.,!?)])"#, #"~~\S"#,
    #"!?\[[^\]\n]*\]\((?!@#)[^)\s]+"#, #"!?\[[^\]\n]*\]\[[^\]\n]*\]"#,
].joined(separator: "|"), options: [.anchorsMatchLines])

/// Whether `text` uses any Markdown syntax — when not, it can be shown as plain text, which is far cheaper
/// to lay out than the Markdown renderer.
public func hasMarkdownSyntax(_ text: String) -> Bool { markdownSyntax.hasMatch(in: text) }

private let linkable = NSRegularExpression(
    #"`[^`\n]*`|!?\[[^\]\n]*\]\([^)\s]*\)|<(?<auto>https?://[^>\s]+)>|(?<url>https?://[^\s<>()\[\]`]+[^\s<>()\[\]`.,;:!?'"])"#)

/// Turns bare web addresses (and `<https://…>` autolinks) into Markdown links. Code and existing links are
/// left alone.
public func linkifyBareUrls(_ text: String) -> String {
    guard text.contains("http") else { return text }
    var inFence = false
    var out: [String] = []
    for line in text.components(separatedBy: "\n") {
        let isFence = fence.hasMatch(in: line)
        if isFence { inFence.toggle() }
        out.append(inFence || isFence ? line : linkifyLine(line))
    }
    return out.joined(separator: "\n")
}

private func linkifyLine(_ line: String) -> String {
    linkable.replacing(in: line) { m in
        guard let url = m.named("url") ?? m.named("auto") else { return m[0]! }
        return "[\(url)](\(url))"
    }
}
