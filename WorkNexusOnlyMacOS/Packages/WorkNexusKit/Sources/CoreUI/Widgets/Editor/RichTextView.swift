import AppKit

/// Ported from: lib/core/widgets/rich_text_editor.dart (editor surface)
/// Draws what the text attributes cannot: list markers, the quote bar and the code-block backdrop.
final class RichLayoutManager: NSLayoutManager {
    var style: RichStyle?

    override func drawBackground(forGlyphRange glyphsToShow: NSRange, at origin: NSPoint) {
        super.drawBackground(forGlyphRange: glyphsToShow, at: origin)
        guard let storage = textStorage, let container = textContainers.first, let s = style else { return }
        let ns = storage.string as NSString
        let chars = characterRange(forGlyphRange: glyphsToShow, actualGlyphRange: nil)
        var at = ns.paragraphRange(for: NSRange(location: chars.location, length: 0)).location
        while at < NSMaxRange(chars), at < ns.length {
            let para = ns.paragraphRange(for: NSRange(location: at, length: 0))
            at = NSMaxRange(para)
            guard let block = (storage.attribute(.wnBlock, at: para.location, effectiveRange: nil) as? BlockBox)?.value else { continue }
            let glyphs = glyphRange(forCharacterRange: para, actualCharacterRange: nil)
            var rect = boundingRect(forGlyphRange: glyphs, in: container)
            rect.origin.x += origin.x; rect.origin.y += origin.y
            if block.codeBlock {
                s.codeBackground.setFill()
                NSBezierPath(roundedRect: rect.insetBy(dx: 0, dy: -1), xRadius: 3, yRadius: 3).fill()
            }
            if block.blockquote {
                s.quoteBar.setFill()
                NSRect(x: origin.x + CGFloat(block.indent) * RichAttributedBridge.indentStep + 4, y: rect.minY, width: 3, height: rect.height).fill()
            }
            if let kind = block.list { drawMarker(kind, block, para, glyphs, origin, storage, s) }
        }
    }

    private func drawMarker(_ kind: RichListKind, _ block: RichBlock, _ para: NSRange, _ glyphs: NSRange, _ origin: NSPoint,
                            _ storage: NSTextStorage, _ s: RichStyle) {
        guard glyphs.length > 0 else { return }
        var marker = "•"
        if kind == .ordered {
            // Number = position among the preceding consecutive items of this kind and indent.
            var n = 1, probe = para.location
            let ns = storage.string as NSString
            while probe > 0 {
                let prev = ns.paragraphRange(for: NSRange(location: probe - 1, length: 0))
                guard let b = (storage.attribute(.wnBlock, at: prev.location, effectiveRange: nil) as? BlockBox)?.value, b.list != nil else { break }
                if b.indent == block.indent, b.list == kind { n += 1 } else if b.indent < block.indent { break }
                probe = prev.location
            }
            marker = "\(n)."
        }
        let used = lineFragmentUsedRect(forGlyphAt: glyphs.location, effectiveRange: nil)
        let attrs: [NSAttributedString.Key: Any] = [.font: NSFont.systemFont(ofSize: s.size), .foregroundColor: s.ink.withAlphaComponent(0.7)]
        let w = (marker as NSString).size(withAttributes: attrs).width
        (marker as NSString).draw(at: NSPoint(x: origin.x + used.minX - w - 6, y: origin.y + used.minY), withAttributes: attrs)
    }
}

/// The editor's `NSTextView`: pastes a clipboard picture through `onPasteImage` before falling back to text.
final class RichNSTextView: NSTextView {
    /// Returns true when it consumed the paste (a picture was uploaded).
    var onPasteImage: (() async -> Bool)?
    /// Hint drawn while the editor is empty.
    var placeholder: String?
    var placeholderColor: NSColor = .secondaryLabelColor

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        guard string.isEmpty, let placeholder else { return }
        let font = (typingAttributes[.font] as? NSFont) ?? .systemFont(ofSize: 14)
        (placeholder as NSString).draw(at: NSPoint(x: textContainerInset.width + (textContainer?.lineFragmentPadding ?? 5), y: textContainerInset.height),
                                       withAttributes: [.font: font, .foregroundColor: placeholderColor])
    }

    /// Files dragged in are not text: the text view must not register for them, so the drag reaches the editor's
    /// `FileDropTarget` (which uploads images and attaches the rest) instead of inserting a path.
    override var acceptableDragTypes: [NSPasteboard.PasteboardType] {
        super.acceptableDragTypes.filter { $0 != .fileURL && $0 != NSPasteboard.PasteboardType("NSFilenamesPboardType") }
    }

    override func paste(_ sender: Any?) {
        guard let onPasteImage else { return super.paste(sender) }
        Task { @MainActor [weak self] in
            if await onPasteImage() { return }
            self?.pasteAsPlainText(sender)
        }
    }
}
