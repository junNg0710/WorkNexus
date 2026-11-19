/// Ported from: lib/core/widgets/code_block.dart `_wrappedRows`.
import AppKit

/// How many rows code takes once wrapped to a width, and the height of one: a code message collapses by the rows it
/// fills, not its line breaks (one pasted JSON line can fill the screen as much as hundreds of short ones).
public enum CodeRows {
    /// The face code is set in (`Space Mono`, else the system's monospaced one).
    public static func font(size: CGFloat) -> NSFont {
        NSFont(name: "Space Mono", size: size)
            ?? NSFontManager.shared.font(withFamily: "Space Mono", traits: [], weight: 5, size: size)
            ?? .monospacedSystemFont(ofSize: size, weight: .regular)
    }

    public static func measure(_ code: String, font: NSFont, lineSpacing: CGFloat, width: CGFloat) -> (count: Int, rowHeight: CGFloat) {
        let layout = NSLayoutManager()
        let rowHeight = layout.defaultLineHeight(for: font)
        guard !code.isEmpty else { return (0, rowHeight) }
        let style = NSMutableParagraphStyle()
        style.lineSpacing = lineSpacing
        let storage = NSTextStorage(string: code, attributes: [.font: font, .paragraphStyle: style])
        let container = NSTextContainer(size: CGSize(width: width > 0 ? width : .greatestFiniteMagnitude, height: .greatestFiniteMagnitude))
        container.lineFragmentPadding = 0
        layout.addTextContainer(container)
        storage.addLayoutManager(layout)
        layout.ensureLayout(for: container)
        var count = 0
        layout.enumerateLineFragments(forGlyphRange: NSRange(location: 0, length: layout.numberOfGlyphs)) { _, _, _, _, _ in count += 1 }
        // A trailing line break opens one more (empty) row.
        if code.hasSuffix("\n") { count += 1 }
        return (count, rowHeight)
    }
}
