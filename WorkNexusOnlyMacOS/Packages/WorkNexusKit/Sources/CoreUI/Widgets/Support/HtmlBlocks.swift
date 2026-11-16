import Foundation
import SwiftUI

/// Ported from: lib/core/widgets/html_text.dart (flutter_widget_from_html_core → our own block model).
/// Renders a provider's HTML as it is — ZenTao's descriptions and comments come from its rich-text editor.
public enum HtmlBlocks {
    public static func parse(_ html: String) -> [BodyBlock] {
        var b = Builder()
        b.children(HtmlNode.parseFragment(html), Style())
        return b.finish()
    }

    private struct Style {
        var bold = false, italic = false, underline = false, strike = false, code = false
        var link: String?
        var color: String?
        var background: String?
        var pre = false
    }

    private static let blockTags: Set<String> = ["p", "div", "section", "article", "header", "footer", "main", "aside", "figure", "figcaption", "dl", "dt", "dd", "center"]
    private static let skipped: Set<String> = ["script", "style", "head", "iframe", "video", "audio", "object", "embed", "svg", "canvas"]

    private struct Builder {
        var blocks: [BodyBlock] = []
        var current = AttributedString()
        var level = 0

        mutating func finish() -> [BodyBlock] { flush(); return blocks }

        mutating func flush() {
            let s = String(current.characters).trimmingCharacters(in: .whitespacesAndNewlines)
            if !s.isEmpty { blocks.append(.text(trimmed(current), level: level)) }
            current = AttributedString(); level = 0
        }

        func trimmed(_ a: AttributedString) -> AttributedString {
            var s = a
            while let f = s.characters.first, f.isWhitespace { s.removeSubrange(s.startIndex..<s.characters.index(after: s.startIndex)) }
            while let l = s.characters.last, l.isWhitespace { s.removeSubrange(s.characters.index(before: s.endIndex)..<s.endIndex) }
            return s
        }

        mutating func append(_ text: String, _ st: Style) {
            var t = text
            if !st.pre {
                var out = "", pending = false
                for ch in t {
                    if ch == " " || ch == "\n" || ch == "\t" || ch == "\r" { pending = true; continue }
                    if pending { out.append(" "); pending = false }
                    out.append(ch)
                }
                if pending { out.append(" ") }
                t = out
                if t.hasPrefix(" "), current.characters.isEmpty || current.characters.last == " " || current.characters.last == "\n" { t.removeFirst() }
            }
            guard !t.isEmpty else { return }
            var a = AttributedString(t)
            var intent: InlinePresentationIntent = []
            if st.bold { intent.insert(.stronglyEmphasized) }
            if st.italic { intent.insert(.emphasized) }
            if st.code { intent.insert(.code) }
            if !intent.isEmpty { a.inlinePresentationIntent = intent }
            if st.underline { a.underlineStyle = .single }
            if st.strike { a.strikethroughStyle = .single }
            if let l = st.link, let url = URL(string: l) { a.link = url }
            if let c = st.color.flatMap(Self.color) { a.foregroundColor = c }
            if let c = st.background.flatMap(Self.color) { a.backgroundColor = c.opacity(0.35) }
            current.append(a)
        }

        static func color(_ css: String) -> Color? {
            ProviderColor.argb(fromHex: HtmlToRich.normalizeColor(css)).map { Color(.sRGB, red: Double(($0 >> 16) & 0xFF) / 255, green: Double(($0 >> 8) & 0xFF) / 255, blue: Double($0 & 0xFF) / 255) }
        }

        mutating func children(_ n: HtmlNode, _ st: Style) { for c in n.children { walk(c, st) } }

        mutating func sub(_ n: HtmlNode, _ st: Style) -> [BodyBlock] {
            var b = Builder()
            b.children(n, st)
            return b.finish()
        }

        mutating func walk(_ n: HtmlNode, _ st: Style) {
            if n.kind == .text { append(n.text, st); return }
            let name = n.name
            if HtmlBlocks.skipped.contains(name) { return }
            var s = st
            switch name {
            case "br": current.append(AttributedString("\n"))
            case "hr": flush(); blocks.append(.rule)
            case "img":
                guard let src = n.attr("src")?.trimmingCharacters(in: .whitespaces), !src.isEmpty else { return }
                flush()
                let w = n.attr("width").flatMap(Double.init) ?? HtmlToRich.styleValue(n.attr("style"), "width").flatMap { Double($0.filter(\.isNumber)) }
                blocks.append(.image(url: src, alt: n.attr("alt") ?? "", width: w))
            case "h1", "h2", "h3", "h4", "h5", "h6":
                flush(); level = Int(name.dropFirst()) ?? 0; s.bold = true; children(n, s); flush()
            case "ul", "ol":
                flush()
                let items = n.children.filter { $0.isElement && $0.name == "li" }.map { sub($0, st) }
                blocks.append(.list(ordered: name == "ol", start: Int(n.attr("start") ?? "") ?? 1, items: items))
            case "blockquote": flush(); blocks.append(.quote(sub(n, st)))
            case "pre":
                flush()
                var raw = n.textContent
                if raw.hasSuffix("\n") { raw.removeLast() }
                blocks.append(.code(raw))
            case "table":
                flush()
                let rows = n.elements(named: ["tr"]).map { tr in tr.elements(named: ["th", "td"]).map { cell -> AttributedString in
                    var b = Builder(); b.children(cell, st)
                    return b.trimmed(b.current)
                } }
                let hasHeader = n.elements(named: ["th"]).isEmpty == false
                if let first = rows.first {
                    blocks.append(.table(header: hasHeader ? first : [], rows: hasHeader ? Array(rows.dropFirst()) : rows))
                }
            case "strong", "b": s.bold = true; children(n, s)
            case "em", "i": s.italic = true; children(n, s)
            case "u": s.underline = true; children(n, s)
            case "s", "strike", "del": s.strike = true; children(n, s)
            case "code", "kbd", "samp": s.code = true; children(n, s)
            case "a": if let h = n.attr("href"), !h.isEmpty { s.link = h }; children(n, s)
            case "font": if let c = n.attr("color") { s.color = c }; children(n, s)
            case "span":
                if let c = HtmlToRich.styleValue(n.attr("style"), "color") { s.color = c }
                if let c = HtmlToRich.styleValue(n.attr("style"), "background-color") { s.background = c }
                children(n, s)
            default:
                if HtmlBlocks.blockTags.contains(name) { flush(); children(n, s); flush() } else { children(n, s) }
            }
        }
    }
}
