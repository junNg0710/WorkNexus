import Foundation

/// Ported from: lib/core/widgets/markdown_text.dart + html_text.dart (the layout model both renderers share).
/// Markdown (GitHub, GitLab) and HTML (ZenTao) bodies are parsed into the same block list, which
/// `BodyBlocksView` draws.
public indirect enum BodyBlock: Equatable {
    /// A paragraph (`level` 0) or heading (1…6) of inline-styled text.
    case text(AttributedString, level: Int)
    case image(url: String, alt: String, width: Double?)
    case code(String)
    case quote([BodyBlock])
    case list(ordered: Bool, start: Int, items: [[BodyBlock]])
    case table(header: [AttributedString], rows: [[AttributedString]])
    case rule
}

/// A GitHub-flavoured Markdown subset parser: headings, fences, quotes, (nested) lists, tables, rules, images
/// and inline emphasis / code / links through `AttributedString(markdown:)`.
public enum MarkdownBlocks {
    private static let heading = NSRegularExpression(#"^ {0,3}(#{1,6})\s+(.*?)\s*#*\s*$"#)
    private static let rule = NSRegularExpression(#"^ {0,3}(?:-{3,}|\*{3,}|_{3,})\s*$"#)
    private static let item = NSRegularExpression(#"^(\s*)([-*+]|\d+[.)])\s+(.*)$"#)
    private static let fenceOpen = NSRegularExpression(#"^\s*(```|~~~)"#)
    private static let tableSep = NSRegularExpression(#"^\s*\|?\s*:?-{2,}:?\s*(\|\s*:?-{2,}:?\s*)*\|?\s*$"#)
    private static let image = NSRegularExpression(#"!\[([^\]]*)\]\(([^)\s]+)(?:\s+"[^"]*")?\)"#)

    /// Blocks of `text`, which should already be through `normalizeMarkdown` / `linkifyBareUrls`.
    public static func parse(_ text: String) -> [BodyBlock] {
        parse(lines: text.components(separatedBy: "\n"))
    }

    public static func inline(_ s: String) -> AttributedString {
        let opts = AttributedString.MarkdownParsingOptions(interpretedSyntax: .inlineOnlyPreservingWhitespace)
        return (try? AttributedString(markdown: s, options: opts)) ?? AttributedString(s)
    }

    private static func parse(lines: [String]) -> [BodyBlock] {
        var out: [BodyBlock] = []
        var i = 0
        func isBlank(_ s: String) -> Bool { s.trimmingCharacters(in: .whitespaces).isEmpty }
        func startsBlock(_ s: String) -> Bool {
            heading.hasMatch(in: s) || rule.hasMatch(in: s) || fenceOpen.hasMatch(in: s) || item.hasMatch(in: s)
                || s.trimmingCharacters(in: .whitespaces).hasPrefix(">")
        }
        while i < lines.count {
            let line = lines[i]
            if isBlank(line) { i += 1; continue }
            if let f = fenceOpen.firstMatch(in: line) {
                let mark = f[1]!
                var code: [String] = []
                i += 1
                while i < lines.count, !lines[i].trimmingCharacters(in: .whitespaces).hasPrefix(mark) { code.append(lines[i]); i += 1 }
                i += 1
                out.append(.code(code.joined(separator: "\n")))
            } else if let h = heading.firstMatch(in: line) {
                out.append(.text(inline(h[2]!), level: h[1]!.count)); i += 1
            } else if rule.hasMatch(in: line) {
                out.append(.rule); i += 1
            } else if line.trimmingCharacters(in: .whitespaces).hasPrefix(">") {
                var inner: [String] = []
                while i < lines.count, lines[i].trimmingCharacters(in: .whitespaces).hasPrefix(">") {
                    var l = lines[i].trimmingCharacters(in: .whitespaces).dropFirst()
                    if l.hasPrefix(" ") { l = l.dropFirst() }
                    inner.append(String(l).replacingOccurrences(of: "\u{00A0}", with: ""))
                    i += 1
                }
                out.append(.quote(parse(lines: inner)))
            } else if line.trimmingCharacters(in: .whitespaces).hasPrefix("|"), i + 1 < lines.count, tableSep.hasMatch(in: lines[i + 1]) {
                let header = cells(line).map(inline)
                i += 2
                var rows: [[AttributedString]] = []
                while i < lines.count, lines[i].trimmingCharacters(in: .whitespaces).hasPrefix("|") { rows.append(cells(lines[i]).map(inline)); i += 1 }
                out.append(.table(header: header, rows: rows))
            } else if let m = item.firstMatch(in: line) {
                i = list(lines, from: i, first: m, into: &out)
            } else {
                var para: [String] = [line]
                i += 1
                while i < lines.count, !isBlank(lines[i]), !startsBlock(lines[i]) { para.append(lines[i]); i += 1 }
                out += paragraph(para.joined(separator: "\n"))
            }
        }
        return out
    }

    private static func cells(_ line: String) -> [String] {
        var t = line.trimmingCharacters(in: .whitespaces)
        if t.hasPrefix("|") { t.removeFirst() }
        if t.hasSuffix("|") { t.removeLast() }
        return t.components(separatedBy: "|").map { $0.trimmingCharacters(in: .whitespaces) }
    }

    /// A paragraph, with images pulled out as blocks of their own.
    private static func paragraph(_ text: String) -> [BodyBlock] {
        var blocks: [BodyBlock] = []
        let ns = text as NSString
        var at = 0
        for m in image.matches(in: text) {
            let before = ns.substring(with: NSRange(location: at, length: m.range.location - at))
            if !before.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { blocks.append(.text(inline(before), level: 0)) }
            blocks.append(.image(url: m[2]!, alt: m[1] ?? "", width: nil))
            at = m.range.location + m.range.length
        }
        let rest = ns.substring(from: at)
        if !rest.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { blocks.append(.text(inline(rest), level: 0)) }
        return blocks
    }

    /// Consumes one list (same marker kind and indent), nesting deeper-indented lines inside their item.
    private static func list(_ lines: [String], from start: Int, first: RxMatch, into out: inout [BodyBlock]) -> Int {
        let indent = first[1]!.count
        let ordered = first[2]!.first!.isNumber
        let startNumber = ordered ? Int(first[2]!.dropLast()) ?? 1 : 1
        var items: [[BodyBlock]] = []
        var i = start
        while i < lines.count {
            guard let m = item.firstMatch(in: lines[i]), m[1]!.count == indent, m[2]!.first!.isNumber == ordered else { break }
            var content = [m[3]!]
            i += 1
            var sub: [String] = []
            while i < lines.count {
                let l = lines[i]
                let lead = l.prefix { $0 == " " }.count
                if l.trimmingCharacters(in: .whitespaces).isEmpty {
                    // A blank line continues the item only when an indented line follows.
                    if i + 1 < lines.count, lines[i + 1].prefix(while: { $0 == " " }).count > indent { sub.append(""); i += 1; continue }
                    break
                }
                if lead > indent { sub.append(l); i += 1 } else { break }
            }
            if !sub.isEmpty { content += sub.map { String($0.dropFirst(min($0.prefix { $0 == " " }.count, indent + 2))) } }
            items.append(parse(lines: content))
        }
        out.append(.list(ordered: ordered, start: startNumber, items: items))
        return i
    }
}
