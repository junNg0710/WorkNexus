import Foundation

/// Ported from: package:html (parseFragment / outerHtml / querySelectorAll) as used by
/// lib/core/widgets/html_editing_controller.dart. A small lenient HTML parser: enough for ZenTao's
/// rich-text editor output (tables, lists, images, inline styles), with implied end tags for
/// `p`, `li`, `tr`, `td`, `th`, and no dependency beyond Foundation.
public final class HtmlNode {
    public enum Kind { case element, text }

    public let kind: Kind
    /// Lower-cased tag name ("" for text, "#fragment" for the root).
    public var name: String
    public var attributes: [(name: String, value: String)] = []
    public var text: String
    public var children: [HtmlNode] = []
    public weak var parent: HtmlNode?

    public init(element name: String, attributes: [(name: String, value: String)] = []) {
        kind = .element; self.name = name; self.attributes = attributes; text = ""
    }
    public init(text: String) { kind = .text; name = ""; self.text = text }

    public var isElement: Bool { kind == .element }

    public func attr(_ key: String) -> String? { attributes.first { $0.name == key }?.value }
    public func hasAttr(_ key: String) -> Bool { attributes.contains { $0.name == key } }
    public func setAttr(_ key: String, _ value: String) {
        if let i = attributes.firstIndex(where: { $0.name == key }) { attributes[i].value = value }
        else { attributes.append((key, value)) }
    }

    public func append(_ child: HtmlNode) { child.parent = self; children.append(child) }

    /// Parses `html` into a fragment root whose children are the top-level nodes.
    public static func parseFragment(_ html: String) -> HtmlNode { var p = HtmlParser(html); return p.parse() }

    /// Descendant elements named in `names`, in document order.
    public func elements(named names: Set<String>) -> [HtmlNode] {
        var out: [HtmlNode] = []
        for c in children where c.isElement {
            if names.contains(c.name) { out.append(c) }
            out += c.elements(named: names)
        }
        return out
    }

    /// Concatenated text of this node and its descendants.
    public var textContent: String { kind == .text ? text : children.map(\.textContent).joined() }

    public var innerHTML: String { children.map { $0.outerHTML }.joined() }

    public var outerHTML: String {
        if kind == .text { return HtmlEntities.escapeText(text) }
        if name == "#fragment" { return innerHTML }
        var s = "<\(name)"
        for a in attributes { s += " \(a.name)=\"\(HtmlEntities.escapeAttribute(a.value))\"" }
        s += ">"
        if HtmlParser.voidElements.contains(name) { return s }
        let raw = name == "script" || name == "style"
        return s + (raw ? children.map(\.text).joined() : innerHTML) + "</\(name)>"
    }

    /// Replaces this node, in its parent, with `nodes`.
    public func replace(with nodes: [HtmlNode]) {
        guard let parent, let i = parent.children.firstIndex(where: { $0 === self }) else { return }
        parent.children.replaceSubrange(i...i, with: nodes)
        nodes.forEach { $0.parent = parent }
        self.parent = nil
    }
}

enum HtmlEntities {
    static let named: [String: String] = [
        "amp": "&", "lt": "<", "gt": ">", "quot": "\"", "apos": "'", "nbsp": "\u{A0}", "copy": "©", "reg": "®",
        "hellip": "…", "mdash": "—", "ndash": "–", "laquo": "«", "raquo": "»", "lsquo": "‘", "rsquo": "’",
        "ldquo": "“", "rdquo": "”", "bull": "•", "middot": "·", "times": "×", "divide": "÷", "deg": "°",
        "trade": "™", "euro": "€", "pound": "£", "yen": "¥", "cent": "¢", "sect": "§", "para": "¶",
        "larr": "←", "rarr": "→", "uarr": "↑", "darr": "↓", "check": "✓", "ensp": "\u{2002}", "emsp": "\u{2003}",
        "thinsp": "\u{2009}", "zwnj": "\u{200C}", "zwj": "\u{200D}",
    ]

    static func decode(_ s: String) -> String {
        guard s.contains("&") else { return s }
        var out = ""
        var i = s.startIndex
        while i < s.endIndex {
            let ch = s[i]
            if ch == "&", let semi = s[i...].prefix(12).firstIndex(of: ";") {
                let body = String(s[s.index(after: i)..<semi])
                if let v = value(of: body) { out += v; i = s.index(after: semi); continue }
            }
            out.append(ch); i = s.index(after: i)
        }
        return out
    }

    private static func value(of body: String) -> String? {
        if body.hasPrefix("#") {
            let digits = body.dropFirst()
            let code = digits.first == "x" || digits.first == "X" ? UInt32(digits.dropFirst(), radix: 16) : UInt32(digits)
            return code.flatMap(UnicodeScalar.init).map { String($0) }
        }
        return named[body]
    }

    static func escapeText(_ s: String) -> String {
        s.replacingOccurrences(of: "&", with: "&amp;").replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;").replacingOccurrences(of: "\u{A0}", with: "&nbsp;")
    }
    static func escapeAttribute(_ s: String) -> String {
        s.replacingOccurrences(of: "&", with: "&amp;").replacingOccurrences(of: "\"", with: "&quot;")
            .replacingOccurrences(of: "\u{A0}", with: "&nbsp;")
    }
}

struct HtmlParser {
    static let voidElements: Set<String> = ["br", "img", "hr", "input", "meta", "link", "area", "base", "col", "embed", "source", "track", "wbr"]
    private static let closesParagraph: Set<String> = [
        "address", "article", "aside", "blockquote", "details", "div", "dl", "fieldset", "figure", "footer", "form",
        "h1", "h2", "h3", "h4", "h5", "h6", "header", "hr", "main", "nav", "ol", "p", "pre", "section", "table", "ul",
    ]
    private static let rawText: Set<String> = ["script", "style"]

    private let chars: [Character]
    private var pos = 0
    private let root = HtmlNode(element: "#fragment")
    private var stack: [HtmlNode] = []

    init(_ html: String) { chars = Array(html) }

    private var current: HtmlNode { stack.last ?? root }

    mutating func parse() -> HtmlNode {
        var text = ""
        func flush(_ p: inout HtmlParser) {
            if !text.isEmpty { p.current.append(HtmlNode(text: HtmlEntities.decode(text))); text = "" }
        }
        while pos < chars.count {
            let c = chars[pos]
            guard c == "<", pos + 1 < chars.count else { text.append(c); pos += 1; continue }
            let n = chars[pos + 1]
            if n == "!" || n == "?" {
                flush(&self)
                if match("<!--") { skip(past: "-->") } else { skip(past: ">") }
            } else if n == "/", pos + 2 < chars.count, chars[pos + 2].isLetter {
                flush(&self); endTag()
            } else if n.isLetter {
                flush(&self); startTag()
            } else { text.append(c); pos += 1 }
        }
        flush(&self)
        return root
    }

    private func match(_ s: String) -> Bool {
        let a = Array(s)
        return pos + a.count <= chars.count && Array(chars[pos..<pos + a.count]) == a
    }

    private mutating func skip(past s: String) {
        let a = Array(s)
        while pos < chars.count {
            if pos + a.count <= chars.count, Array(chars[pos..<pos + a.count]) == a { pos += a.count; return }
            pos += 1
        }
    }

    private mutating func endTag() {
        pos += 2
        var name = ""
        while pos < chars.count, chars[pos] != ">", !chars[pos].isWhitespace { name.append(chars[pos]); pos += 1 }
        skip(past: ">")
        name = name.lowercased()
        if let i = stack.lastIndex(where: { $0.name == name }) { stack.removeSubrange(i...) }
    }

    private mutating func startTag() {
        pos += 1
        var name = ""
        while pos < chars.count, !chars[pos].isWhitespace, chars[pos] != ">", chars[pos] != "/" { name.append(chars[pos]); pos += 1 }
        name = name.lowercased()
        var attrs: [(name: String, value: String)] = []
        while pos < chars.count {
            while pos < chars.count, chars[pos].isWhitespace { pos += 1 }
            guard pos < chars.count else { break }
            if chars[pos] == ">" { pos += 1; break }
            if chars[pos] == "/" { pos += 1; continue }
            var key = ""
            while pos < chars.count, !chars[pos].isWhitespace, chars[pos] != "=", chars[pos] != ">", chars[pos] != "/" {
                key.append(chars[pos]); pos += 1
            }
            while pos < chars.count, chars[pos].isWhitespace { pos += 1 }
            var value = ""
            if pos < chars.count, chars[pos] == "=" {
                pos += 1
                while pos < chars.count, chars[pos].isWhitespace { pos += 1 }
                if pos < chars.count, chars[pos] == "\"" || chars[pos] == "'" {
                    let q = chars[pos]; pos += 1
                    while pos < chars.count, chars[pos] != q { value.append(chars[pos]); pos += 1 }
                    pos += 1
                } else {
                    while pos < chars.count, !chars[pos].isWhitespace, chars[pos] != ">" { value.append(chars[pos]); pos += 1 }
                }
            }
            if !key.isEmpty, !attrs.contains(where: { $0.name == key.lowercased() }) {
                attrs.append((key.lowercased(), HtmlEntities.decode(value)))
            }
        }
        closeImplied(for: name)
        let el = HtmlNode(element: name, attributes: attrs)
        current.append(el)
        if Self.voidElements.contains(name) { return }
        if Self.rawText.contains(name) {
            var raw = ""
            let close = Array("</\(name)")
            while pos < chars.count {
                if pos + close.count <= chars.count, String(chars[pos..<pos + close.count]).lowercased() == String(close) { break }
                raw.append(chars[pos]); pos += 1
            }
            if !raw.isEmpty { el.append(HtmlNode(text: raw)) }
            skip(past: ">")
            return
        }
        stack.append(el)
    }

    /// Pops what an opening `name` tag implicitly ends (`<p>` before a block, `<li>` before `<li>`, cells, rows).
    private mutating func closeImplied(for name: String) {
        func popTo(_ target: Set<String>, stopAt: Set<String>) {
            for i in stride(from: stack.count - 1, through: 0, by: -1) {
                if stopAt.contains(stack[i].name) { return }
                if target.contains(stack[i].name) { stack.removeSubrange(i...); return }
            }
        }
        if Self.closesParagraph.contains(name) { popTo(["p"], stopAt: ["td", "th", "table", "caption", "li"]) }
        switch name {
        case "li": popTo(["li"], stopAt: ["ul", "ol"])
        case "tr": popTo(["tr"], stopAt: ["table", "thead", "tbody", "tfoot"])
        case "td", "th": popTo(["td", "th"], stopAt: ["tr", "table"])
        case "thead", "tbody", "tfoot": popTo(["thead", "tbody", "tfoot"], stopAt: ["table"])
        default: break
        }
    }
}
