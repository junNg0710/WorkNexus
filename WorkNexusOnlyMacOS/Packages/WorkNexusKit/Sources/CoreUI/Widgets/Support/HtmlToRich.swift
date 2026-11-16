import Foundation

/// Ported from: package:flutter_quill_delta_from_html (`HtmlToDelta`) as used by html_editing_controller.dart.
/// Turns an HTML fragment into a `RichDocument`. Tables must already be flattened (see `HtmlEditing`);
/// elements the editor cannot represent (iframe, video, script) are dropped.
enum HtmlToRich {
    static func convert(_ html: String) -> RichDocument {
        var b = Builder()
        b.walkChildren(HtmlNode.parseFragment(html), RichInline(), RichBlock())
        return b.finish()
    }

    /// `width:320px` / `width: 320` → "320".
    static func styleValue(_ style: String?, _ key: String) -> String? {
        guard let style else { return nil }
        for decl in style.split(separator: ";") {
            let parts = decl.split(separator: ":", maxSplits: 1).map { $0.trimmingCharacters(in: .whitespaces) }
            if parts.count == 2, parts[0].lowercased() == key { return parts[1] }
        }
        return nil
    }

    static func normalizeColor(_ css: String) -> String {
        let v = css.trimmingCharacters(in: .whitespaces)
        guard v.lowercased().hasPrefix("rgb") else { return v }
        let nums = v.drop { $0 != "(" }.dropFirst().prefix { $0 != ")" }
            .split(whereSeparator: { $0 == "," || $0 == " " || $0 == "/" }).prefix(3).compactMap { Int($0) }
        guard nums.count == 3 else { return v }
        return "#" + nums.map { String(format: "%02x", min(max($0, 0), 255)) }.joined()
    }

    private struct Builder {
        var lines: [RichLine] = []
        var current: [RichRun] = []
        var listStack: [RichListKind] = []
        static let blocks: Set<String> = ["p", "div", "section", "article", "header", "footer", "main", "aside", "figure",
                                           "figcaption", "tr", "dl", "dt", "dd", "caption", "table", "thead", "tbody", "tfoot"]
        static let skipped: Set<String> = ["script", "style", "head", "iframe", "video", "audio", "object", "embed", "svg", "canvas"]

        mutating func finish() -> RichDocument {
            if !current.isEmpty { flush(RichBlock()) }
            return RichDocument(lines: lines)
        }

        mutating func appendText(_ raw: String, _ inline: RichInline, preserve: Bool) {
            var t = raw
            if !preserve {
                var out = "", pendingSpace = false
                for ch in t {
                    if ch == " " || ch == "\n" || ch == "\t" || ch == "\r" || ch == "\u{0C}" { pendingSpace = true; continue }
                    if pendingSpace { out.append(" "); pendingSpace = false }
                    out.append(ch)
                }
                if pendingSpace { out.append(" ") }
                t = out
                // No leading space at the start of a line (or after one).
                if (current.isEmpty || current.last?.text.hasSuffix(" ") == true), t.hasPrefix(" ") { t.removeFirst() }
            }
            if !t.isEmpty { current.append(RichRun(t, inline)) }
        }

        mutating func flush(_ block: RichBlock) {
            // Trailing blank collapses away; a line is "empty" when only whitespace is left.
            if var last = current.last, last.inline.image == nil {
                while last.text.hasSuffix(" ") { last.text.removeLast() }
                current[current.count - 1] = last
            }
            lines.append(RichLine(runs: current, block: block))
            current = []
        }

        mutating func walkChildren(_ node: HtmlNode, _ inl: RichInline, _ ctx: RichBlock) {
            for c in node.children { walk(c, inl, ctx) }
        }

        mutating func block(_ n: HtmlNode, _ inl: RichInline, _ ctx: RichBlock, emptyLine: Bool = true) {
            if !current.isEmpty { flush(ctx) }
            let before = lines.count
            walkChildren(n, inl, ctx)
            if !current.isEmpty { flush(ctx) }
            else if lines.count == before, emptyLine { lines.append(RichLine(runs: [], block: ctx)) }
        }

        mutating func walk(_ n: HtmlNode, _ inl: RichInline, _ ctx: RichBlock) {
            if n.kind == .text { appendText(n.text, inl, preserve: ctx.codeBlock); return }
            let name = n.name
            if Self.skipped.contains(name) { return }
            var i = inl
            var c = ctx
            switch name {
            case "br": flush(ctx)
            case "img":
                guard let src = n.attr("src")?.trimmingCharacters(in: .whitespaces), !src.isEmpty else { return }
                let w = n.attr("width").flatMap { Int($0).map(String.init) }
                    ?? HtmlToRich.styleValue(n.attr("style"), "width").flatMap { Int($0.filter(\.isNumber)).map(String.init) }
                current.append(.image(src, width: w))
            case "h1", "h2", "h3", "h4", "h5", "h6":
                c.header = Int(name.dropFirst())
                block(n, inl, c)
            case "ul", "ol":
                if !current.isEmpty { flush(ctx) }
                listStack.append(name == "ol" ? .ordered : .bullet)
                walkChildren(n, inl, ctx)
                listStack.removeLast()
            case "li":
                c.list = listStack.last ?? .bullet
                c.indent = max(listStack.count - 1, 0)
                if !current.isEmpty { flush(ctx) }
                // Text first, nested lists after: the item's own line is flushed before a nested list opens.
                walkChildren(n, inl, c)
                if !current.isEmpty { flush(c) }
            case "blockquote":
                c.blockquote = true
                block(n, inl, c, emptyLine: false)
            case "pre":
                c.codeBlock = true
                if !current.isEmpty { flush(ctx) }
                var raw = n.textContent
                if raw.hasSuffix("\n") { raw.removeLast() }
                for part in raw.components(separatedBy: "\n") { lines.append(RichLine(runs: part.isEmpty ? [] : [RichRun(part, i)], block: c)) }
            case "strong", "b": i.bold = true; walkChildren(n, i, c)
            case "em", "i": i.italic = true; walkChildren(n, i, c)
            case "u": i.underline = true; walkChildren(n, i, c)
            case "s", "strike", "del": i.strike = true; walkChildren(n, i, c)
            case "code", "kbd", "samp": i.code = true; walkChildren(n, i, c)
            case "a":
                if let href = n.attr("href"), !href.isEmpty { i.link = href }
                walkChildren(n, i, c)
            case "font":
                if let col = n.attr("color") { i.color = col }
                walkChildren(n, i, c)
            case "span":
                if let col = HtmlToRich.styleValue(n.attr("style"), "color") { i.color = HtmlToRich.normalizeColor(col) }
                if let bg = HtmlToRich.styleValue(n.attr("style"), "background-color") { i.background = HtmlToRich.normalizeColor(bg) }
                walkChildren(n, i, c)
            case "td", "th":
                walkChildren(n, i, c)
                if !current.isEmpty { appendText(" ", i, preserve: false) }
            default:
                if Self.blocks.contains(name) {
                    if let a = HtmlToRich.styleValue(n.attr("style"), "text-align"), ["center", "right", "justify"].contains(a) { c.align = a }
                    block(n, inl, c)
                } else { walkChildren(n, i, c) }
            }
        }
    }
}
