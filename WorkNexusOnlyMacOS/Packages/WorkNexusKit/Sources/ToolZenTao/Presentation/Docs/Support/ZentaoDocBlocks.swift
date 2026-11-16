/// Ported from: lib/tools/zentao/presentation/widgets/zentao_doc_body.dart (the HTML walk `flutter_widget_from_html_core`
/// did there: here the prepared DOM becomes a block list the reader draws, headings carrying their outline index and
/// find matches their own run).
import CoreUI
import Foundation

/// A stretch of text with one inline style. `find` is the index of the find match it is (nil: not a match).
public struct ZentaoRun: Equatable, Sendable {
    public var text: String
    public var bold = false, italic = false, code = false, strike = false, underline = false
    public var link: String?
    public var find: Int?
    /// Colours from `font` / `span` / `style` (text and background) and sub- / superscript.
    public var color: ZentaoColor?
    public var background: ZentaoColor?
    public var script: ZentaoScript?
    public init(_ text: String, bold: Bool = false, italic: Bool = false, code: Bool = false, strike: Bool = false,
                underline: Bool = false, link: String? = nil, find: Int? = nil, color: ZentaoColor? = nil,
                background: ZentaoColor? = nil, script: ZentaoScript? = nil) {
        self.text = text; self.bold = bold; self.italic = italic; self.code = code; self.strike = strike
        self.underline = underline; self.link = link; self.find = find
        self.color = color; self.background = background; self.script = script
    }
}

/// One block of a document body.
public indirect enum ZentaoDocBlock: Equatable, Sendable {
    /// A paragraph (`level` 0) or heading (1...6); an outlined heading carries its `anchor`.
    case text([ZentaoRun], level: Int, anchor: Int?)
    case image(url: String)
    /// A `<pre>`: its code and the find matches in it.
    case code(String, matches: [ZentaoFindRange])
    case quote([ZentaoDocBlock])
    case list(ordered: Bool, start: Int, items: [[ZentaoDocBlock]])
    /// A table: rows of cells; a cell holds blocks (text, images, lists ...) and may span columns / rows.
    case table(rows: [[ZentaoDocCell]])
    case rule
    /// Blocks laid out centred or right (`text-align`, `align`, `<center>`).
    case aligned(ZentaoDocAlign, [ZentaoDocBlock])
}

/// A table cell (`td` / `th`).
public struct ZentaoDocCell: Equatable, Sendable {
    public var blocks: [ZentaoDocBlock]
    public var colspan = 1
    public var rowspan = 1
    /// A `th`: shaded and bold.
    public var header = false
    public var align: ZentaoDocAlign?
    public var background: ZentaoColor?
    public init(blocks: [ZentaoDocBlock], colspan: Int = 1, rowspan: Int = 1, header: Bool = false,
                align: ZentaoDocAlign? = nil, background: ZentaoColor? = nil) {
        self.blocks = blocks; self.colspan = max(colspan, 1); self.rowspan = max(rowspan, 1)
        self.header = header; self.align = align; self.background = background
    }
}

public extension ZentaoDocBlock {
    /// The outline anchors and find-match indices drawn inside this block (and its nested blocks).
    var landmarks: (anchors: [Int], matches: [Int]) {
        var anchors: [Int] = [], matches: [Int] = []
        func runs(_ rs: [ZentaoRun]) { rs.forEach { if let f = $0.find { matches.append(f) } } }
        func visit(_ b: ZentaoDocBlock) {
            switch b {
            case .text(let rs, _, let anchor): if let anchor { anchors.append(anchor) }; runs(rs)
            case .code(_, let ms): matches += ms.map(\.index)
            case .quote(let inner): inner.forEach(visit)
            case .list(_, _, let items): items.forEach { $0.forEach(visit) }
            case .table(let rows): rows.forEach { $0.forEach { $0.blocks.forEach(visit) } }
            case .aligned(_, let inner): inner.forEach(visit)
            case .image, .rule: break
            }
        }
        visit(self)
        return (anchors, matches)
    }
}

/// The page's top-level block of each heading anchor and each find match: what the reader scrolls to.
public struct ZentaoDocLayout: Equatable, Sendable {
    public var blockOfHeading: [Int: Int] = [:]
    public var blockOfMatch: [Int: Int] = [:]
    /// The heading anchors inside each top-level block (the page measures those blocks to know the heading being read).
    public var anchorsOfBlock: [[Int]] = []
    public init(_ blocks: [ZentaoDocBlock]) {
        for (i, b) in blocks.enumerated() {
            let l = b.landmarks
            anchorsOfBlock.append(l.anchors)
            l.anchors.forEach { blockOfHeading[$0] = i }
            l.matches.forEach { blockOfMatch[$0] = i }
        }
    }
}

public enum ZentaoDocBlocks {
    /// The blocks of a prepared body (`prepareZentaoDocHtml`).
    public static func build(_ root: HtmlNode) -> [ZentaoDocBlock] {
        var b = Builder()
        b.children(root, Style())
        return b.finish()
    }

    /// A `table` element as rows of cells. Only the table's own rows count (a table nested in a cell is part of that
    /// cell), through `thead` / `tbody` / `tfoot` too; a cell's content is whatever blocks its HTML holds.
    private static func table(_ n: HtmlNode, _ st: Style) -> ZentaoDocBlock {
        func rows(in node: HtmlNode) -> [HtmlNode] {
            node.children.filter(\.isElement).flatMap { c -> [HtmlNode] in
                switch c.name {
                case "tr": [c]
                case "thead", "tbody", "tfoot": rows(in: c)
                default: []
                }
            }
        }
        func span(_ cell: HtmlNode, _ attr: String) -> Int { max(Int(cell.attr(attr)?.trimmingCharacters(in: .whitespaces) ?? "") ?? 1, 1) }
        let tableCss = ZentaoCssStyle(n)
        var out: [[ZentaoDocCell]] = []
        for tr in rows(in: n) {
            let rowCss = ZentaoCssStyle(tr)
            let cells = tr.children.filter { $0.isElement && ($0.name == "td" || $0.name == "th") }.map { cell -> ZentaoDocCell in
                let css = ZentaoCssStyle(cell)
                var style = st
                if let c = css.color ?? rowCss.color ?? tableCss.color { style.color = c }
                if cell.name == "th" || css.bold == true || rowCss.bold == true { style.bold = true }
                if css.italic == true { style.italic = true }
                if css.underline == true { style.underline = true }
                if css.strike == true { style.strike = true }
                var b = Builder()
                b.children(cell, style)
                return ZentaoDocCell(blocks: b.finish(), colspan: span(cell, "colspan"), rowspan: span(cell, "rowspan"),
                                     header: cell.name == "th", align: css.align ?? rowCss.align ?? tableCss.align,
                                     background: css.background ?? rowCss.background)
            }
            if !cells.isEmpty { out.append(cells) }
        }
        return .table(rows: out)
    }

    private struct Style {
        var bold = false, italic = false, underline = false, strike = false, code = false
        var link: String?
        var find: Int?
        var pre = false
        var color: ZentaoColor?
        var background: ZentaoColor?
        var script: ZentaoScript?
    }

    private static let blockTags: Set<String> = ["p", "div", "section", "article", "header", "footer", "main", "aside",
                                                 "figure", "figcaption", "dl", "dt", "dd", "center"]
    /// Elements whose `text-align` lays their blocks out centred / right.
    private static let alignable: Set<String> = ["p", "div", "section", "article", "header", "footer", "main", "aside", "figure",
                                                 "figcaption", "center", "h1", "h2", "h3", "h4", "h5", "h6", "blockquote", "ul", "ol"]
    private static let skipped: Set<String> = ["script", "style", "head", "iframe", "video", "audio", "object", "embed",
                                               "svg", "canvas"]

    private struct Builder {
        var blocks: [ZentaoDocBlock] = []
        var runs: [ZentaoRun] = []
        var level = 0
        var anchor: Int?

        mutating func finish() -> [ZentaoDocBlock] { flush(); return blocks }

        mutating func flush() {
            let trimmed = Self.trimmed(runs)
            if !trimmed.isEmpty { blocks.append(.text(trimmed, level: level, anchor: level > 0 ? anchor : nil)) }
            runs = []; level = 0; anchor = nil
        }

        /// `runs` without leading and trailing whitespace (and without runs that leaves empty).
        static func trimmed(_ input: [ZentaoRun]) -> [ZentaoRun] {
            var rs = input
            while let f = rs.first, f.text.allSatisfy(\.isWhitespace) { rs.removeFirst() }
            while let l = rs.last, l.text.allSatisfy(\.isWhitespace) { rs.removeLast() }
            if var f = rs.first { f.text = String(f.text.drop(while: \.isWhitespace)); rs[0] = f }
            if var l = rs.last { while let c = l.text.last, c.isWhitespace { l.text.removeLast() }; rs[rs.count - 1] = l }
            return rs
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
                if t.hasPrefix(" "), runs.last.map({ $0.text.last == " " || $0.text.last == "\n" }) ?? true { t.removeFirst() }
            }
            guard !t.isEmpty else { return }
            runs.append(ZentaoRun(t, bold: st.bold, italic: st.italic, code: st.code, strike: st.strike,
                                  underline: st.underline, link: st.link, find: st.find, color: st.color,
                                  background: st.background, script: st.script))
        }

        mutating func children(_ n: HtmlNode, _ st: Style) { for c in n.children { walk(c, st) } }

        mutating func sub(_ n: HtmlNode, _ st: Style) -> [ZentaoDocBlock] {
            var b = Builder()
            b.children(n, st)
            return b.finish()
        }

        mutating func walk(_ n: HtmlNode, _ st: Style, aligned: Bool = false) {
            if n.kind == .text { append(n.text, st); return }
            let name = n.name
            if ZentaoDocBlocks.skipped.contains(name) { return }
            var s = st
            let css = ZentaoCssStyle(n)
            if let c = css.color { s.color = c }
            if let b = css.background { s.background = b }
            if let b = css.bold { s.bold = b }
            if let i = css.italic { s.italic = i }
            if css.underline == true { s.underline = true }
            if css.strike == true { s.strike = true }
            if !aligned, let align = css.align, align != .left, ZentaoDocBlocks.alignable.contains(name) {
                flush()
                var b = Builder()
                b.walk(n, st, aligned: true)
                blocks.append(.aligned(align, b.finish()))
                return
            }
            switch name {
            case zentaoAnchorTag: anchor = Int(n.attr(zentaoAnchorAttr) ?? "")
            case zentaoFindTag: s.find = Int(n.attr(zentaoFindAttr) ?? ""); children(n, s)
            case "br": runs.append(ZentaoRun("\n"))
            case "hr": flush(); blocks.append(.rule)
            case "img":
                guard let src = n.attr("src")?.trimmingCharacters(in: .whitespaces), !src.isEmpty else { return }
                flush(); blocks.append(.image(url: src))
            case "h1", "h2", "h3", "h4", "h5", "h6":
                flush(); level = Int(name.dropFirst()) ?? 0; s.bold = true; children(n, s); flush()
            case "ul", "ol":
                flush()
                let items = n.children.filter { $0.isElement && $0.name == "li" }.map { sub($0, s) }
                blocks.append(.list(ordered: name == "ol", start: Int(n.attr("start") ?? "") ?? 1, items: items))
            case "blockquote": flush(); blocks.append(.quote(sub(n, s)))
            case "pre":
                flush()
                var raw = n.textContent
                while raw.hasSuffix("\n") { raw.removeLast() }
                blocks.append(.code(raw, matches: zentaoFindRanges(n)))
            case "table": flush(); blocks.append(ZentaoDocBlocks.table(n, s))
            case "strong", "b": s.bold = true; children(n, s)
            case "em", "i": s.italic = true; children(n, s)
            case "u", "ins": s.underline = true; children(n, s)
            case "s", "strike", "del": s.strike = true; children(n, s)
            case "sub": s.script = .sub; children(n, s)
            case "sup": s.script = .sup; children(n, s)
            case "code", "kbd", "samp": s.code = true; children(n, s)
            case "a": if let h = n.attr("href"), !h.isEmpty { s.link = h }; children(n, s)
            default:
                if ZentaoDocBlocks.blockTags.contains(name) { flush(); children(n, s); flush() } else { children(n, s) }
            }
        }
    }
}
