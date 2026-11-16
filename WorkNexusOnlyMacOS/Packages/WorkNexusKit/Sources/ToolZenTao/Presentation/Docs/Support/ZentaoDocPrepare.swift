/// Ported from: lib/tools/zentao/presentation/util/zentao_doc_prepare.dart
import CoreUI
import Foundation

/// A heading of a document, for its outline: `index` is the one its marker (`<zt-anchor data-heading>`) carries,
/// which the reader scrolls to.
public struct ZentaoDocHeading: Equatable, Sendable {
    public var level: Int
    public var text: String
    public var index: Int
    public init(level: Int, text: String, index: Int) { self.level = level; self.text = text; self.index = index }
}

/// A find match inside a `<pre>` or inline `<code>`, as its index and range (UTF-16 offsets) in that element's text.
public struct ZentaoFindRange: Equatable, Sendable {
    public var index: Int
    public var start: Int
    public var end: Int
    public init(index: Int, start: Int, end: Int) { self.index = index; self.start = start; self.end = end }
}

/// A document body ready for the reader: the DOM `root` with its headings anchored and the find matches marked,
/// the `headings` in order, and `matchCount`.
public struct ZentaoDocPrepared {
    public var root: HtmlNode
    public var headings: [ZentaoDocHeading]
    public var matchCount: Int
    public var html: String { root.innerHTML }
}

/// The tag a find match is wrapped in; its `data-find` is its index (0..).
public let zentaoFindTag = "mark"
public let zentaoFindAttr = "data-find"
/// The empty marker put at the start of each outlined heading; its `data-heading` is the heading's index.
public let zentaoAnchorTag = "zt-anchor"
public let zentaoAnchorAttr = "data-heading"
/// More matches than this are left unmarked: a one-letter search in a long document would otherwise turn every
/// other word into a mark.
public let zentaoFindLimit = 500

/// Prepares `html` for reading: headings `h1`-`h4` get a marker (`<zt-anchor data-heading="N">`) and become the
/// outline; every case-insensitive match of `query` in the text - code included - is wrapped in
/// `<mark data-find="N">`, in reading order.
public func prepareZentaoDocHtml(_ html: String, query: String = "") -> ZentaoDocPrepared {
    let root = HtmlNode.parseFragment(html)
    if html.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
        return ZentaoDocPrepared(root: root, headings: [], matchCount: 0)
    }
    var headings: [ZentaoDocHeading] = []
    for h in root.elements(named: ["h1", "h2", "h3", "h4"]) {
        let text = h.textContent.split(whereSeparator: \.isWhitespace).joined(separator: " ")
        if text.isEmpty { continue }
        let marker = HtmlNode(element: zentaoAnchorTag, attributes: [(zentaoAnchorAttr, "\(headings.count)")])
        h.insert(marker, at: 0)
        headings.append(ZentaoDocHeading(level: Int(h.name.dropFirst()) ?? 1, text: text, index: headings.count))
    }

    var count = 0
    let q = query.trimmingCharacters(in: .whitespacesAndNewlines)
    if !q.isEmpty {
        for node in textNodes(of: root) {
            if count >= zentaoFindLimit { break }
            let text = node.text as NSString
            guard let parent = node.parent, let at = parent.children.firstIndex(where: { $0 === node }) else { continue }
            var pieces: [HtmlNode] = []
            var from = 0
            var search = NSRange(location: 0, length: text.length)
            while count < zentaoFindLimit {
                let m = text.range(of: q, options: [.caseInsensitive, .literal], range: search)
                if m.location == NSNotFound { break }
                if m.location > from { pieces.append(HtmlNode(text: text.substring(with: NSRange(location: from, length: m.location - from)))) }
                let mark = HtmlNode(element: zentaoFindTag, attributes: [(zentaoFindAttr, "\(count)")])
                mark.append(HtmlNode(text: text.substring(with: m)))
                pieces.append(mark)
                count += 1
                from = m.location + m.length
                search = NSRange(location: from, length: text.length - from)
            }
            if pieces.isEmpty { continue }
            if from < text.length { pieces.append(HtmlNode(text: text.substring(from: from))) }
            parent.children.replaceSubrange(at...at, with: pieces)
            pieces.forEach { $0.parent = parent }
            node.parent = nil
        }
    }
    return ZentaoDocPrepared(root: root, headings: headings, matchCount: count)
}

/// Every text node under `root`, in document order (collected first, as marking replaces them).
private func textNodes(of root: HtmlNode) -> [HtmlNode] {
    var out: [HtmlNode] = []
    func walk(_ n: HtmlNode) {
        for child in n.children {
            if child.kind == .text { out.append(child) } else { walk(child) }
        }
    }
    walk(root)
    return out
}

/// The marks under `e` (a `<pre>` or inline `<code>`), as their indices and ranges in `e`'s text.
public func zentaoFindRanges(_ e: HtmlNode) -> [ZentaoFindRange] {
    var out: [ZentaoFindRange] = []
    var offset = 0
    func walk(_ n: HtmlNode) {
        for child in n.children {
            if child.kind == .text {
                offset += (child.text as NSString).length
            } else {
                let index = child.name == zentaoFindTag ? Int(child.attr(zentaoFindAttr) ?? "") : nil
                let start = offset
                walk(child)
                if let index { out.append(ZentaoFindRange(index: index, start: start, end: offset)) }
            }
        }
    }
    walk(e)
    return out
}

extension HtmlNode {
    /// Inserts `node` as the child at `index`.
    func insert(_ node: HtmlNode, at index: Int) {
        node.parent = self
        children.insert(node, at: min(index, children.count))
    }
}
