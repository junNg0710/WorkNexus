import Foundation

/// Ported from: lib/tools/zentao/domain/usecases/render_zentao_doc_markdown.dart (package:html2md, ATX headings,
/// fenced code, `-` bullets). A compact converter for what ZenTao's editor emits - headings, paragraphs, emphasis,
/// links, images, lists, quotes, code blocks and GFM tables - not a full html2md replacement.
enum ZenTaoDocMarkdown {
    /// `doc` as Markdown: its title as a heading, then the body.
    @Sendable static func render(_ doc: ZenTaoDoc) -> String {
        let body = doc.html.trimmingCharacters(in: .whitespacesAndNewlines)
        var converted = body.isEmpty ? "" : convert(body)
        converted = converted.replacingRegex(#"\n{3,}"#, with: "\n\n").trimmingCharacters(in: .whitespacesAndNewlines)
        return converted.isEmpty ? "# \(doc.title)" : "# \(doc.title)\n\n\(converted)"
    }

    static func convert(_ html: String) -> String { blocks(HNode.parseFragment(html).children, indent: "") }

    private static let headings: [String: Int] = ["h1": 1, "h2": 2, "h3": 3, "h4": 4, "h5": 5, "h6": 6]

    /// Block-level content: each block is separated by a blank line.
    private static func blocks(_ nodes: [HNode], indent: String) -> String {
        var out = ""
        var inline = ""
        func flushInline() {
            let t = inline.trimmingCharacters(in: .whitespacesAndNewlines)
            if !t.isEmpty { out += "\(indent)\(t)\n\n" }
            inline = ""
        }
        for node in nodes {
            guard node.kind == .element else { inline += node.kind == .text ? collapse(node.text) : ""; continue }
            switch node.name {
            case "h1", "h2", "h3", "h4", "h5", "h6":
                flushInline(); out += "\(indent)\(String(repeating: "#", count: headings[node.name]!)) \(inlineText(node.children).trimmingCharacters(in: .whitespacesAndNewlines))\n\n"
            case "p", "div", "section", "article", "figure":
                flushInline()
                if node.children.contains(where: { isBlock($0) }) { out += blocks(node.children, indent: indent) }
                else { let t = inlineText(node.children).trimmingCharacters(in: .whitespacesAndNewlines); if !t.isEmpty { out += "\(indent)\(t)\n\n" } }
            case "ul", "ol": flushInline(); out += list(node, indent: indent) + "\n"
            case "blockquote":
                flushInline()
                let inner = blocks(node.children, indent: "").trimmingCharacters(in: .whitespacesAndNewlines)
                out += inner.split(separator: "\n", omittingEmptySubsequences: false).map { "\(indent)> \($0)" }.joined(separator: "\n") + "\n\n"
            case "pre": flushInline(); out += code(node, indent: indent)
            case "hr": flushInline(); out += "\(indent)---\n\n"
            case "table": flushInline(); out += table(node, indent: indent)
            default: inline += inlineText([node])
            }
        }
        flushInline()
        return out
    }

    private static func isBlock(_ n: HNode) -> Bool {
        n.kind == .element && (headings[n.name] != nil || ["p", "div", "ul", "ol", "blockquote", "pre", "hr", "table", "section", "article", "figure"].contains(n.name))
    }

    private static func collapse(_ s: String) -> String { s.replacingRegex(#"\s+"#, with: " ") }

    /// Inline content (emphasis, links, code, images, line breaks).
    private static func inlineText(_ nodes: [HNode]) -> String {
        var out = ""
        for n in nodes {
            switch n.kind {
            case .text: out += collapse(n.text)
            case .comment: break
            case .element:
                let inner = inlineText(n.children)
                switch n.name {
                case "strong", "b": out += inner.isEmpty ? "" : "**\(inner.trimmingCharacters(in: .whitespaces))**"
                case "em", "i": out += inner.isEmpty ? "" : "*\(inner.trimmingCharacters(in: .whitespaces))*"
                case "del", "s", "strike": out += "~~\(inner)~~"
                case "code": out += "`\(n.plainText)`"
                case "br": out += "  \n"
                case "a": out += n.attribute("href").map { "[\(inner)](\($0))" } ?? inner
                case "img": out += "![\(n.attribute("alt") ?? "")](\(n.attribute("src") ?? ""))"
                default: out += inner
                }
            }
        }
        return out
    }

    private static func list(_ node: HNode, indent: String) -> String {
        var out = ""
        var n = 0
        for item in node.children where item.kind == .element && item.name == "li" {
            n += 1
            let marker = node.name == "ol" ? "\(n)." : "-"
            let nested = item.children.filter { $0.kind == .element && ($0.name == "ul" || $0.name == "ol") }
            let own = item.children.filter { !($0.kind == .element && ($0.name == "ul" || $0.name == "ol")) }
            out += "\(indent)\(marker) \(inlineText(own).trimmingCharacters(in: .whitespacesAndNewlines))\n"
            for sub in nested { out += list(sub, indent: indent + "  ") }
        }
        return out
    }

    private static func code(_ pre: HNode, indent: String) -> String {
        let codeNode = pre.firstElement("code")
        let language = (codeNode?.classes ?? []).first { $0.hasPrefix("language-") }.map { String($0.dropFirst(9)) } ?? ""
        let text = (codeNode ?? pre).plainText.trimmingCharacters(in: CharacterSet(charactersIn: "\n"))
        return "\(indent)```\(language)\n\(text)\n\(indent)```\n\n"
    }

    private static func table(_ node: HNode, indent: String) -> String {
        let rows = node.elements("tr").map { tr in tr.children.filter { $0.kind == .element && ($0.name == "td" || $0.name == "th") }
            .map { inlineText($0.children).trimmingCharacters(in: .whitespacesAndNewlines).replacingOccurrences(of: "|", with: "\\|") } }
        guard let header = rows.first, !header.isEmpty else { return "" }
        var out = "\(indent)| \(header.joined(separator: " | ")) |\n\(indent)|\(header.map { _ in " --- " }.joined(separator: "|"))|\n"
        for row in rows.dropFirst() {
            let padded = row + Array(repeating: "", count: max(0, header.count - row.count))
            out += "\(indent)| \(padded.joined(separator: " | ")) |\n"
        }
        return out + "\n"
    }
}
