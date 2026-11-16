import Foundation

/// Ported from: package:vsc_quill_delta_to_html (`QuillDeltaToHtmlConverter`, inline styles, no link target,
/// `multiLineParagraph`) as configured in html_editing_controller.dart.
enum RichToHtml {
    static func convert(_ doc: RichDocument) -> String {
        var out = "", i = 0
        let lines = doc.lines
        while i < lines.count {
            let b = lines[i].block
            var j = i
            if b.list != nil {
                while j < lines.count, lines[j].block.list != nil { j += 1 }
                var k = i
                out += renderList(lines, &k, upTo: j, indent: lines[i].block.indent)
            } else if b.blockquote {
                while j < lines.count, lines[j].block.blockquote { j += 1 }
                out += "<blockquote>" + lines[i..<j].map { inline($0) }.joined(separator: "<br/>") + "</blockquote>"
            } else if b.codeBlock {
                while j < lines.count, lines[j].block.codeBlock { j += 1 }
                out += "<pre>" + lines[i..<j].map { HtmlEntities.escapeText($0.text) }.joined(separator: "\n") + "</pre>"
            } else if let h = b.header {
                out += "<h\(h)\(style(b))>\(inline(lines[i]))</h\(h)>"; j = i + 1
            } else if lines[i].runs.isEmpty {
                out += "<p\(style(b))><br/></p>"; j = i + 1
            } else {
                // multiLineParagraph: consecutive non-blank plain lines share one paragraph.
                while j < lines.count, isPlain(lines[j]), !lines[j].runs.isEmpty, lines[j].block == b { j += 1 }
                out += "<p\(style(b))>" + lines[i..<j].map { inline($0) }.joined(separator: "<br/>") + "</p>"
            }
            i = max(j, i + 1)
        }
        return out
    }

    private static func isPlain(_ l: RichLine) -> Bool {
        let b = l.block
        return b.list == nil && !b.blockquote && !b.codeBlock && b.header == nil
    }

    private static func style(_ b: RichBlock) -> String {
        var parts: [String] = []
        if let a = b.align { parts.append("text-align:\(a)") }
        if b.indent > 0, b.list == nil { parts.append("padding-left:\(b.indent * 3)em") }
        return parts.isEmpty ? "" : " style=\"\(parts.joined(separator: ";"))\""
    }

    /// Items at `indent` become `<li>`s; deeper items nest inside the preceding `<li>`.
    private static func renderList(_ lines: [RichLine], _ i: inout Int, upTo end: Int, indent: Int) -> String {
        let kind = lines[i].block.list ?? .bullet
        let tag = kind == .ordered ? "ol" : "ul"
        var s = "<\(tag)>"
        while i < end {
            let b = lines[i].block
            if b.indent < indent || (b.indent == indent && (b.list ?? .bullet) != kind) { break }
            if b.indent > indent { s += renderList(lines, &i, upTo: end, indent: b.indent); continue }
            s += "<li>" + inline(lines[i])
            i += 1
            if i < end, lines[i].block.indent > indent { s += renderList(lines, &i, upTo: end, indent: lines[i].block.indent) }
            s += "</li>"
        }
        return s + "</\(tag)>"
    }

    static func inline(_ line: RichLine) -> String { line.runs.map(run).joined() }

    private static func run(_ r: RichRun) -> String {
        let a = r.inline
        if let url = a.image {
            let w = a.imageWidth.map { " width=\"\($0)\"" } ?? ""
            return "<img src=\"\(HtmlEntities.escapeAttribute(url))\"\(w)/>"
        }
        var s = HtmlEntities.escapeText(r.text)
        if a.code { s = "<code>\(s)</code>" }
        if a.strike { s = "<s>\(s)</s>" }
        if a.underline { s = "<u>\(s)</u>" }
        if a.italic { s = "<em>\(s)</em>" }
        if a.bold { s = "<strong>\(s)</strong>" }
        var css: [String] = []
        if let c = a.color { css.append("color:\(c)") }
        if let c = a.background { css.append("background-color:\(c)") }
        if !css.isEmpty { s = "<span style=\"\(css.joined(separator: ";"))\">\(s)</span>" }
        if let href = a.link { s = "<a href=\"\(HtmlEntities.escapeAttribute(href))\">\(s)</a>" }
        return s
    }
}
