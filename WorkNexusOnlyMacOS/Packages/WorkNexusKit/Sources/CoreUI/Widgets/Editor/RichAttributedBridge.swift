import AppKit

/// Ported from: lib/core/widgets/rich_text_editor.dart (the Quill document ↔ editor view mapping).
/// Maps the AppKit-free `RichDocument` to the `NSAttributedString` shown in the editor's `NSTextView`, and back.
/// Every character carries its `RichInline` and every paragraph its `RichBlock` as attribute boxes, so a round trip
/// keeps attributes the view cannot show (a colour written as `rgb(…)`, an image's width).

/// Typography the editor draws with (from the app theme).
struct RichStyle {
    var family: String
    var size: CGFloat
    var ink: NSColor
    var accent: NSColor
    var codeBackground: NSColor
    var quoteBar: NSColor
}

extension NSAttributedString.Key {
    static let wnInline = NSAttributedString.Key("wn.inline")
    static let wnBlock = NSAttributedString.Key("wn.block")
}

final class InlineBox: NSObject {
    let value: RichInline
    init(_ v: RichInline) { value = v }
    override func isEqual(_ object: Any?) -> Bool { (object as? InlineBox)?.value == value }
    override var hash: Int { value.link.hashValue ^ value.image.hashValue ^ (value.bold ? 1 : 0) ^ (value.italic ? 2 : 0) }
}

final class BlockBox: NSObject {
    let value: RichBlock
    init(_ v: RichBlock) { value = v }
    override func isEqual(_ object: Any?) -> Bool { (object as? BlockBox)?.value == value }
    override var hash: Int { (value.header ?? 0) ^ value.indent ^ (value.blockquote ? 4 : 0) }
}

enum RichAttributedBridge {
    static let indentStep: CGFloat = 22
    private static let headerScale: [CGFloat] = [1, 1.7, 1.45, 1.25, 1.1, 1, 1]

    static func color(_ css: String?) -> NSColor? {
        guard let css, let argb = ProviderColor.argb(fromHex: HtmlToRich.normalizeColor(css)) else { return nil }
        return NSColor(srgbRed: CGFloat((argb >> 16) & 0xFF) / 255, green: CGFloat((argb >> 8) & 0xFF) / 255,
                       blue: CGFloat(argb & 0xFF) / 255, alpha: 1)
    }

    static func font(_ inline: RichInline, _ block: RichBlock, _ s: RichStyle) -> NSFont {
        let size = s.size * headerScale[min(block.header ?? 0, 6)]
        var f: NSFont
        if inline.code || block.codeBlock {
            f = NSFont(name: "Space Mono", size: size * 0.9) ?? .monospacedSystemFont(ofSize: size * 0.9, weight: .regular)
        } else {
            f = (s.family.isEmpty ? nil : NSFont(name: s.family, size: size)) ?? .systemFont(ofSize: size)
        }
        var traits: NSFontTraitMask = []
        if inline.bold || block.header != nil { traits.insert(.boldFontMask) }
        if inline.italic { traits.insert(.italicFontMask) }
        if !traits.isEmpty { f = NSFontManager.shared.convert(f, toHaveTrait: traits) }
        return f
    }

    static func paragraphStyle(_ b: RichBlock) -> NSParagraphStyle {
        let p = NSMutableParagraphStyle()
        var head = CGFloat(b.indent) * indentStep
        if b.list != nil { head += indentStep }
        if b.blockquote || b.codeBlock { head += 14 }
        p.firstLineHeadIndent = head; p.headIndent = head
        p.paragraphSpacing = 4; p.lineSpacing = 2
        switch b.align { case "center": p.alignment = .center; case "right": p.alignment = .right; case "justify": p.alignment = .justified; default: break }
        return p
    }

    /// The attributes of one run in a paragraph with block attributes `block`.
    static func attributes(inline: RichInline, block: RichBlock, style s: RichStyle) -> [NSAttributedString.Key: Any] {
        var a: [NSAttributedString.Key: Any] = [
            .font: font(inline, block, s), .foregroundColor: color(inline.color) ?? s.ink,
            .paragraphStyle: paragraphStyle(block), .wnInline: InlineBox(inline), .wnBlock: BlockBox(block),
        ]
        if inline.underline { a[.underlineStyle] = NSUnderlineStyle.single.rawValue }
        if inline.strike { a[.strikethroughStyle] = NSUnderlineStyle.single.rawValue }
        if inline.code { a[.backgroundColor] = s.codeBackground }
        if let bg = color(inline.background) { a[.backgroundColor] = bg.withAlphaComponent(0.4) }
        if let link = inline.link, let url = URL(string: link) {
            a[.link] = url; a[.foregroundColor] = s.accent; a[.underlineStyle] = NSUnderlineStyle.single.rawValue
        }
        return a
    }

    /// The document as styled text; lines are joined by `\n` with no trailing break. Images become attachments
    /// holding `placeholder` (the editor swaps the loaded picture in).
    static func attributedString(from doc: RichDocument, style: RichStyle, placeholder: (RichInline) -> NSTextAttachment) -> NSAttributedString {
        let out = NSMutableAttributedString()
        for (i, line) in doc.lines.enumerated() {
            if line.runs.isEmpty && i < doc.lines.count - 1 {
                out.append(NSAttributedString(string: "\n", attributes: attributes(inline: RichInline(), block: line.block, style: style)))
                continue
            }
            for run in line.runs {
                let attrs = attributes(inline: run.inline, block: line.block, style: style)
                if run.inline.image != nil {
                    let att = NSMutableAttributedString(attachment: placeholder(run.inline))
                    att.addAttributes(attrs, range: NSRange(location: 0, length: att.length))
                    out.append(att)
                } else { out.append(NSAttributedString(string: run.text, attributes: attrs)) }
            }
            if i < doc.lines.count - 1 {
                // The break carries the block so an empty line and the line's end keep its attributes.
                out.append(NSAttributedString(string: "\n", attributes: attributes(inline: RichInline(), block: line.block, style: style)))
            }
        }
        return out
    }

    /// The editor's text as a document (the inverse of `attributedString`).
    static func document(from text: NSAttributedString) -> RichDocument {
        let ns = text.string as NSString
        var lines: [RichLine] = []
        var start = 0
        func line(_ range: NSRange, newlineAt: Int?) {
            let probe = range.length > 0 ? range.location : (newlineAt ?? max(range.location - 1, 0))
            let block = probe < text.length ? (text.attribute(.wnBlock, at: probe, effectiveRange: nil) as? BlockBox)?.value ?? RichBlock() : RichBlock()
            var runs: [RichRun] = []
            text.enumerateAttributes(in: range, options: []) { attrs, r, _ in
                let inline = (attrs[.wnInline] as? InlineBox)?.value ?? RichInline()
                let piece = ns.substring(with: r)
                if inline.image != nil || attrs[.attachment] != nil {
                    for ch in piece where ch == "\u{FFFC}" {
                        if let url = inline.image { runs.append(.image(url, width: inline.imageWidth)) }
                    }
                } else { runs.append(RichRun(piece, inline)) }
            }
            lines.append(RichLine(runs: runs, block: block))
        }
        while start <= ns.length {
            let nl = ns.range(of: "\n", range: NSRange(location: start, length: ns.length - start))
            if nl.location == NSNotFound { line(NSRange(location: start, length: ns.length - start), newlineAt: nil); break }
            line(NSRange(location: start, length: nl.location - start), newlineAt: nl.location)
            start = nl.location + 1
        }
        return RichDocument(lines: lines)
    }
}
