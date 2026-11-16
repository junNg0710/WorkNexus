import Foundation

/// Ported from: lib/core/widgets/html_editing_controller.dart (the pure HTML-side helpers).
/// ZenTao stores rich text as HTML; the editor shows a flat document. Markup the editor cannot show (tables)
/// is flattened into marked rows on the way in and rebuilt on the way out.
public enum HtmlEditing {
    /// Marks the cell borders `|` of a table flattened by `preprocessTables`. Invisible in the editor, and
    /// nothing a user types, so `restoreTables` rebuilds only those tables.
    static let cellMark = "\u{2063}|"
    /// Stands for a line break inside a flattened cell; shown as `↵`, turned back into `<br/>`.
    static let cellBreak = "\u{2063}\u{21b5}"
    private static let cellLines = NSRegularExpression(#"<br\s*/?>|</p>\s*<p[^>]*>"#, options: [.caseInsensitive])
    private static let cellParagraph = NSRegularExpression(#"</?p[^>]*>"#, options: [.caseInsensitive])
    private static let brSplit = NSRegularExpression(#"<br\s*/?>"#)

    /// HTML → document (tables flattened, image widths moved into `style`); ends with a line break.
    static func document(from html: String) -> RichDocument {
        let source = html.trimmingCharacters(in: .whitespacesAndNewlines)
        if source.isEmpty { return RichDocument() }
        return HtmlToRich.convert(preprocessTables(widthsAsStyle(source)))
    }

    /// Converts HTML tables into row paragraphs separated by `<br>` so rows and cells do not fuse.
    static func preprocessTables(_ html: String) -> String {
        let doc = HtmlNode.parseFragment(html)
        let tables = doc.elements(named: ["table"])
        if tables.isEmpty { return html }
        for table in tables where table.parent != nil {
            var rows: [String] = []
            for tr in table.elements(named: ["tr"]) {
                let cells = tr.elements(named: ["th", "td"])
                if cells.isEmpty { continue }
                let texts = cells.map { c -> String in
                    var inner = c.innerHTML.trimmingCharacters(in: .whitespacesAndNewlines)
                    inner = cellLines.replacing(in: inner) { _ in cellBreak }
                    inner = cellParagraph.replacing(in: inner) { _ in "" }
                    return inner.isEmpty ? " " : inner
                }
                rows.append("\(cellMark) \(texts.joined(separator: " \(cellMark) ")) \(cellMark)")
            }
            if !rows.isEmpty { table.replace(with: HtmlNode.parseFragment("<p>\(rows.joined(separator: "<br>"))</p>").children) }
        }
        return doc.outerHTML
    }

    /// Rebuilds the `<table>`s `preprocessTables` flattened. The editor may have fused a row with the text
    /// around it onto one line, so whatever precedes the first mark or follows the last stays a paragraph.
    static func restoreTables(_ html: String) -> String {
        guard html.contains(cellMark) else { return html }
        let doc = HtmlNode.parseFragment(html)
        for p in doc.elements(named: ["p", "div"]) where p.parent != nil {
            let inner = p.innerHTML
            guard inner.contains(cellMark) else { continue }
            var buf = "", text: [String] = [], rows: [[String]] = []
            func flushText() { if !text.isEmpty { buf += "<p>\(text.joined(separator: "<br/>"))</p>" }; text = [] }
            func flushTable() {
                if rows.isEmpty { return }
                buf += "<table border=\"1\" cellpadding=\"4\" cellspacing=\"0\" style=\"border-collapse: collapse; width: 100%;\"><tbody>"
                for (r, row) in rows.enumerated() {
                    let tag = r == 0 ? "th" : "td"
                    buf += "<tr>" + row.map { "<\(tag)>\($0)</\(tag)>" }.joined() + "</tr>"
                }
                buf += "</tbody></table>"
                rows = []
            }
            func addText(_ line: String) {
                let plain = line.replacingOccurrences(of: "\u{2063}", with: "")
                if plain.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { return }
                flushTable(); text.append(plain)
            }
            for line in splitKeepingEmpty(inner, brSplit) {
                let parts = line.components(separatedBy: cellMark)
                // A row needs a mark on both sides of at least one cell.
                if parts.count < 3 { addText(line); continue }
                addText(parts[0]); flushText()
                rows.append(parts[1..<(parts.count - 1)].map {
                    $0.trimmingCharacters(in: .whitespacesAndNewlines).replacingOccurrences(of: cellBreak, with: "<br/>")
                })
                addText(parts[parts.count - 1])
            }
            flushTable(); flushText()
            p.replace(with: HtmlNode.parseFragment(buf).children)
        }
        return doc.outerHTML
    }

    private static func splitKeepingEmpty(_ s: String, _ rx: NSRegularExpression) -> [String] {
        let ns = s as NSString
        var out: [String] = [], at = 0
        for m in rx.matches(in: s) {
            out.append(ns.substring(with: NSRange(location: at, length: m.range.location - at)))
            at = m.range.location + m.range.length
        }
        out.append(ns.substring(from: at))
        return out
    }

    /// ZenTao sizes images with `<img width>`, which the converter ignores (it reads `style`); copies the
    /// attribute into the style so it survives.
    static func widthsAsStyle(_ html: String) -> String {
        let doc = HtmlNode.parseFragment(html)
        var changed = false
        for img in doc.elements(named: ["img"]) {
            guard let width = img.attr("width") else { continue }
            let style = img.attr("style") ?? ""
            if style.contains("width") { continue }
            let unit = width.allSatisfy(\.isNumber) && !width.isEmpty ? "px" : ""
            img.setAttr("style", "width:\(width)\(unit);\(style)")
            changed = true
        }
        return changed ? doc.outerHTML : html
    }

    private static let styleWidth = NSRegularExpression(#"(?:^|;)\s*width:\s*(\d+)px"#)

    /// Copies an image's `style` width into the `width` attribute ZenTao reads, leaving the rest as it was.
    static func widthsAsAttribute(_ html: String) -> String {
        guard html.contains("<img") else { return html }
        let doc = HtmlNode.parseFragment(html)
        var changed = false
        for img in doc.elements(named: ["img"]) where !img.hasAttr("width") {
            guard let w = styleWidth.firstMatch(in: img.attr("style") ?? "")?[1] else { continue }
            img.setAttr("width", w)
            changed = true
        }
        return changed ? doc.outerHTML : html
    }

    /// Whether `html` is only whitespace in empty paragraphs (`<p> </p>`).
    static func isBlankHtml(_ html: String) -> Bool {
        let doc = HtmlNode.parseFragment(html)
        guard doc.textContent.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return false }
        return doc.elements(named: Set(allElementNames(doc))).allSatisfy { ["p", "br", "div", "span"].contains($0.name) }
    }

    private static func allElementNames(_ n: HtmlNode) -> [String] {
        n.children.filter(\.isElement).flatMap { [$0.name] + allElementNames($0) }
    }

    /// The pixel width in an image's style string (`width:320px`), or nil.
    public static func imageStyleWidth(_ style: String?) -> String? {
        guard let style else { return nil }
        return NSRegularExpression(#"width:\s*(\d+)"#).firstMatch(in: style)?[1]
    }
}

/// Ported from: lib/core/widgets/html_editing_controller.dart (`HtmlEditingController`).
/// Holds rich text being edited, read from and written back as HTML — the format ZenTao's own editor stores
/// descriptions in. UI-free: the editor view mirrors `document`; clipboard access is injected.
public final class HtmlEditingController {
    private let initialHtml: String
    private let initialDocument: RichDocument
    /// The text being edited (Quill: `quill.document`). The editor view writes its changes here.
    public var document: RichDocument
    /// Caret position (UTF-16 offset) used to place a pasted image.
    public var selectionEnd = 0
    /// The clipboard's picture; nil until injected (tests) or installed by `RichTextEditor` (system pasteboard).
    public var readImage: (() async -> Data?)?
    /// The clipboard's plain text; nil until injected or installed by `RichTextEditor`.
    public var readClipboardText: (() -> String?)?

    /// Turns a pasted image into the URL to show it at (by uploading it); a pasted image is dropped while
    /// this is nil or returns nil.
    public var onImagePaste: ((Data) async -> String?)?

    /// - Parameters:
    ///   - readImage: the clipboard's picture (injectable for tests).
    ///   - readClipboardText: the clipboard's plain text.
    public init(html: String = "", readImage: (() async -> Data?)? = nil,
                readClipboardText: (() -> String?)? = nil) {
        initialHtml = html
        document = HtmlEditing.document(from: html)
        initialDocument = document
        self.readImage = readImage
        self.readClipboardText = readClipboardText
    }

    /// Pastes the clipboard's picture as an uploaded image, when it holds one and no text beyond (at most) its
    /// address; false leaves the paste to the editor. A browser's "Copy image" puts the picture next to an
    /// `<img>` pointing back at the web, which the editor would paste first — an image the provider never gets.
    public func pasteClipboardImage() async -> Bool {
        guard let upload = onImagePaste else { return false }
        let text = readClipboardText?()?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if !text.isEmpty, !Self.hasScheme(text) { return false }
        guard let read = readImage, let bytes = await read() else { return false }
        guard let url = await upload(bytes) else { return true }   // the uploader reports the failure
        document.insertImage(url, at: max(selectionEnd, 0))
        return true
    }

    private static func hasScheme(_ s: String) -> Bool {
        s.rangeOfCharacter(from: .whitespacesAndNewlines) == nil
            && s.range(of: #"^[A-Za-z][A-Za-z0-9+.\-]*:"#, options: .regularExpression) != nil
    }

    /// The text as HTML; empty when nothing but whitespace was written.
    public var html: String {
        // Untouched text goes back as it came, so markup the editor cannot represent (tables, classes, an
        // iframe) isn't rewritten or dropped by just opening it — unless it holds nothing at all.
        if document == initialDocument {
            return HtmlEditing.isBlankHtml(initialHtml) ? "" : HtmlEditing.widthsAsAttribute(initialHtml)
        }
        if document.plainText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, !document.hasEmbeds { return "" }
        return HtmlEditing.restoreTables(RichToHtml.convert(document))
    }
}
