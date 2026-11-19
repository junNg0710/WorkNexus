/// Not in the Flutter app.
import AppKit
import SwiftUI

/// Where the links of a text lie: lays the text out with TextKit — the same string, font, line spacing and width as the
/// `Text` drawing it — to tell whether a point is on a link. Selectable SwiftUI text does not say which run is under the
/// pointer, so this stands in for it; it can be a pixel or two off at a link's ends, which only matters for the cursor.
@MainActor
final class TextLinkHitTest {
    private let storage = NSTextStorage()
    private let layout = NSLayoutManager()
    private let container = NSTextContainer()
    private var key: (text: AttributedString, width: CGFloat)?

    init() {
        container.lineFragmentPadding = 0
        layout.addTextContainer(container)
        storage.addLayoutManager(layout)
    }

    /// Whether `point` (in the text's own coordinates, top-left origin) is on a link of `text` laid out `width` wide.
    func isOnLink(_ point: CGPoint, text: AttributedString, font: NSFont, lineSpacing: CGFloat, width: CGFloat) -> Bool {
        guard text.runs.contains(where: { $0.link != nil }), width > 0 else { return false }
        if key?.text != text || key?.width != width {
            storage.setAttributedString(Self.attributed(text, font: font, lineSpacing: lineSpacing))
            container.size = CGSize(width: width, height: .greatestFiniteMagnitude)
            key = (text, width)
        }
        layout.ensureLayout(for: container)
        guard layout.usedRect(for: container).contains(point) else { return false }
        var fraction: CGFloat = 0
        let glyph = layout.glyphIndex(for: point, in: container, fractionOfDistanceThroughGlyph: &fraction)
        // Past the last glyph of a line the nearest glyph is returned: only a point inside the glyph's box counts.
        let box = layout.boundingRect(forGlyphRange: NSRange(location: glyph, length: 1), in: container)
        guard box.insetBy(dx: -1, dy: -1).contains(point) else { return false }
        let index = layout.characterIndexForGlyph(at: glyph)
        guard index < storage.length else { return false }
        return storage.attribute(.link, at: index, effectiveRange: nil) != nil
    }

    /// The string as AppKit lays it out: the base font, bold and code runs in their faces, the line spacing.
    static func attributed(_ text: AttributedString, font: NSFont, lineSpacing: CGFloat) -> NSAttributedString {
        let out = NSMutableAttributedString()
        let paragraph = NSMutableParagraphStyle()
        paragraph.lineSpacing = lineSpacing
        for run in text.runs {
            var face = font
            if let intent = run.inlinePresentationIntent {
                if intent.contains(.code) { face = .monospacedSystemFont(ofSize: font.pointSize, weight: .regular) }
                if intent.contains(.stronglyEmphasized) { face = NSFontManager.shared.convert(face, toHaveTrait: .boldFontMask) }
                if intent.contains(.emphasized) { face = NSFontManager.shared.convert(face, toHaveTrait: .italicFontMask) }
            }
            var attributes: [NSAttributedString.Key: Any] = [.font: face, .paragraphStyle: paragraph]
            if let link = run.link { attributes[.link] = link }
            out.append(NSAttributedString(string: String(text[run.range].characters), attributes: attributes))
        }
        return out
    }
}

/// Shows the pointing hand over the links of a `Text` drawing `text`, and the usual text cursor elsewhere.
private struct LinkPointer: ViewModifier {
    let text: AttributedString
    let font: NSFont
    let lineSpacing: CGFloat
    @State private var hit = TextLinkHitTest()
    @State private var width: CGFloat = 0
    @State private var onLink = false

    func body(content: Content) -> some View {
        content
            .onGeometryChange(for: CGFloat.self, of: { $0.size.width }) { width = $0 }
            .onContinuousHover(coordinateSpace: .local) { phase in
                let over: Bool
                switch phase {
                case .active(let point): over = hit.isOnLink(point, text: text, font: font, lineSpacing: lineSpacing, width: width)
                case .ended: over = false
                }
                if over != onLink { onLink = over }
                // The text's own cursor (the I-beam) is put back on every move; ours goes over it while on a link.
                if over { NSCursor.pointingHand.set() }
            }
            .pointerStyle(onLink ? .link : nil)
    }
}

public extension View {
    /// The pointing hand over the links of `text`, which this view draws with `font` and `lineSpacing` (only text with a
    /// link tracks the pointer at all).
    @ViewBuilder func linkPointer(_ text: AttributedString, font: NSFont, lineSpacing: CGFloat = 0) -> some View {
        if text.runs.contains(where: { $0.link != nil }) {
            modifier(LinkPointer(text: text, font: font, lineSpacing: lineSpacing))
        } else {
            self
        }
    }
}

public extension AppTypography {
    /// The AppKit face of `font(size:weight:)`, for laying text out as the app draws it.
    func nsFont(size: CGFloat, weight: NSFont.Weight = .regular) -> NSFont {
        guard !family.isEmpty,
              let custom = NSFontManager.shared.font(withFamily: family, traits: weight >= .semibold ? .boldFontMask : [],
                                                     weight: 5, size: size) else {
            return .systemFont(ofSize: size, weight: weight)
        }
        return custom
    }
}
