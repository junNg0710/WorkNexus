/// Ported from: package:html parseFragment (used by zentao_doc_html.dart, zentao_doc_history_mapper.dart, zentao_doc_mapper.dart)
import Foundation

/// A tiny HTML fragment parser for the markup ZenTao hands back (document bodies, history sentences, change
/// lists). It stands in for Dart's `package:html` `parseFragment`: tags, attributes, text with entities
/// decoded, void elements and lenient closing - no full HTML5 error recovery.
final class HNode {
    enum Kind { case element, text, comment }
    let kind: Kind
    var name: String            // element local name (lower-case)
    var text: String            // text / comment content (entities decoded for text)
    var attributes: [(name: String, value: String)] = []
    var children: [HNode] = []
    weak var parent: HNode?

    init(element name: String) { kind = .element; self.name = name; text = "" }
    init(text: String) { kind = .text; name = ""; self.text = text }
    init(comment: String) { kind = .comment; name = ""; text = comment }

    static let voidElements: Set<String> = ["area", "base", "br", "col", "embed", "hr", "img", "input", "link", "meta", "source", "track", "wbr"]
    private static let rawText: Set<String> = ["script", "style"]

    /// The concatenated text of this node and its descendants.
    var plainText: String {
        switch kind {
        case .text: return text
        case .comment: return ""
        case .element: return children.map(\.plainText).joined()
        }
    }

    var classes: Set<String> {
        Set((attribute("class") ?? "").split(whereSeparator: { $0.isWhitespace }).map(String.init))
    }

    func attribute(_ n: String) -> String? { attributes.first { $0.name == n }?.value }
    func removeAttribute(_ n: String) { attributes.removeAll { $0.name == n } }

    func remove() {
        parent?.children.removeAll { $0 === self }
        parent = nil
    }

    /// Descendant elements named `tag`, in document order.
    func elements(_ tag: String) -> [HNode] {
        var out: [HNode] = []
        for c in children where c.kind == .element {
            if c.name == tag { out.append(c) }
            out.append(contentsOf: c.elements(tag))
        }
        return out
    }
    func firstElement(_ tag: String) -> HNode? { elements(tag).first }

    // MARK: Parsing

    /// Parses `html` into a fragment root whose children are the top-level nodes.
    static func parseFragment(_ html: String) -> HNode {
        let root = HNode(element: "#fragment")
        var stack = [root]
        let chars = Array(html)
        var i = 0
        var textBuffer = ""
        func flushText() {
            if textBuffer.isEmpty { return }
            let node = HNode(text: stack.last!.name.isEmpty || rawText.contains(stack.last!.name) ? textBuffer : decodeHtmlEntities(textBuffer))
            node.parent = stack.last; stack.last!.children.append(node); textBuffer = ""
        }
        while i < chars.count {
            let c = chars[i]
            guard c == "<" else { textBuffer.append(c); i += 1; continue }
            // Comment
            if html.hasPrefixAt(chars, i, "<!--") {
                flushText()
                var j = i + 4
                var body = ""
                while j < chars.count, !html.hasPrefixAt(chars, j, "-->") { body.append(chars[j]); j += 1 }
                let node = HNode(comment: body)
                node.parent = stack.last; stack.last!.children.append(node)
                i = min(j + 3, chars.count)
                continue
            }
            // Closing tag
            if i + 1 < chars.count, chars[i + 1] == "/" {
                var j = i + 2
                var name = ""
                while j < chars.count, chars[j] != ">" { name.append(chars[j]); j += 1 }
                flushText()
                let tag = name.trimmingCharacters(in: .whitespaces).lowercased()
                if let idx = stack.lastIndex(where: { $0.name == tag }), idx > 0 { stack.removeSubrange(idx...) }
                i = min(j + 1, chars.count)
                continue
            }
            // Opening tag
            guard i + 1 < chars.count, chars[i + 1].isLetter else { textBuffer.append(c); i += 1; continue }
            flushText()
            var j = i + 1
            var name = ""
            while j < chars.count, !chars[j].isWhitespace, chars[j] != ">", chars[j] != "/" { name.append(chars[j]); j += 1 }
            let el = HNode(element: name.lowercased())
            var selfClosing = false
            // Attributes
            while j < chars.count, chars[j] != ">" {
                if chars[j].isWhitespace { j += 1; continue }
                if chars[j] == "/" { selfClosing = true; j += 1; continue }
                var an = ""
                while j < chars.count, !chars[j].isWhitespace, chars[j] != "=", chars[j] != ">", chars[j] != "/" { an.append(chars[j]); j += 1 }
                var av = ""
                while j < chars.count, chars[j].isWhitespace { j += 1 }
                if j < chars.count, chars[j] == "=" {
                    j += 1
                    while j < chars.count, chars[j].isWhitespace { j += 1 }
                    if j < chars.count, chars[j] == "\"" || chars[j] == "'" {
                        let q = chars[j]; j += 1
                        while j < chars.count, chars[j] != q { av.append(chars[j]); j += 1 }
                        j += 1
                    } else {
                        while j < chars.count, !chars[j].isWhitespace, chars[j] != ">" { av.append(chars[j]); j += 1 }
                    }
                }
                if !an.isEmpty { el.attributes.append((an.lowercased(), decodeHtmlEntities(av))) }
            }
            i = min(j + 1, chars.count)
            el.parent = stack.last; stack.last!.children.append(el)
            if selfClosing || voidElements.contains(el.name) { continue }
            if rawText.contains(el.name) {
                var body = ""
                while i < chars.count, !html.hasPrefixAt(chars, i, "</\(el.name)") { body.append(chars[i]); i += 1 }
                if !body.isEmpty { let t = HNode(text: body); t.parent = el; el.children.append(t) }
                while i < chars.count, chars[i] != ">" { i += 1 }
                i = min(i + 1, chars.count)
                continue
            }
            stack.append(el)
        }
        flushText()
        return root
    }

    // MARK: Serializing

    /// The fragment's children as HTML (Dart `DocumentFragment.outerHtml`).
    var innerHtml: String { children.map(\.outerHtml).joined() }

    var outerHtml: String {
        switch kind {
        case .text:
            return escape(text, attribute: false)
        case .comment:
            return "<!--\(text)-->"
        case .element:
            var s = "<\(name)"
            for a in attributes { s += " \(a.name)=\"\(escape(a.value, attribute: true))\"" }
            s += ">"
            if Self.voidElements.contains(name) { return s }
            if Self.rawText.contains(name) { return s + children.map(\.text).joined() + "</\(name)>" }
            return s + children.map(\.outerHtml).joined() + "</\(name)>"
        }
    }

    private func escape(_ s: String, attribute: Bool) -> String {
        var out = s.replacingOccurrences(of: "&", with: "&amp;").replacingOccurrences(of: "\u{00A0}", with: "&nbsp;")
        if attribute { out = out.replacingOccurrences(of: "\"", with: "&quot;") }
        else { out = out.replacingOccurrences(of: "<", with: "&lt;").replacingOccurrences(of: ">", with: "&gt;") }
        return out
    }
}

private extension String {
    func hasPrefixAt(_ chars: [Character], _ i: Int, _ prefix: String) -> Bool {
        let p = Array(prefix)
        guard i + p.count <= chars.count else { return false }
        for k in 0..<p.count where chars[i + k] != p[k] { return false }
        return true
    }
}
