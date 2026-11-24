/// Ported from: lib/features/chat/presentation/widgets/mention_text.dart
import CoreDomain
import CoreUI
import SwiftUI

/// Plain message text: `[@Name](@#id)` mentions as highlighted `@Name`, and web addresses as tappable links. Colours and
/// size follow the bubble. While the chat is searched, the words searched are marked where they are found.
struct MentionTextView: View {
    @Environment(\.appTheme) private var theme
    @Environment(\.chatBubbleInk) private var ink
    let text: String
    let ctx: ThreadContext

    static let mentionScheme = "worknexus-mention"

    var body: some View {
        let shown = Self.cachedAttributed(text, ink: ink, font: theme.typography.font(size: ink.fontSize),
                                          marks: SearchTerms.parse(ctx.state.searchQuery), markColor: theme.colors.yellow.opacity(0.4))
        Text(shown)
            .foregroundStyle(ink.text.color)
            .lineSpacing(ink.fontSize * 0.2)
            .tint(ink.link.color)
            .textSelection(.enabled)
            .fixedSize(horizontal: false, vertical: true)
            .linkPointer(shown, font: theme.typography.nsFont(size: ink.fontSize), lineSpacing: ink.fontSize * 0.2)
            .environment(\.openURL, OpenURLAction { url in
                if url.scheme == Self.mentionScheme, let id = url.host.flatMap(Int.init) { ctx.actions.openProfile(id) }
                else { ctx.openLink(url.absoluteString) }
                return .handled
            })
    }

    /// `attributed`, worked out once per text and look: rows redraw often while the list scrolls. With `marks` (the words
    /// of the in-chat search), the places they are found get `markColor` behind them.
    static func cachedAttributed(_ text: String, ink: ChatBubbleInk, font: Font, marks: [String] = [], markColor: Color = .clear) -> AttributedString {
        let plainKey = "\(ink.fontSize)|\(ink.link.color)|\(text)"
        let key = (marks.isEmpty ? plainKey : "\(marks.joined(separator: "\u{1}"))\u{2}\(markColor)|\(plainKey)") as NSString
        if let kept = attributedCache.object(forKey: key) { return kept.value }
        var value = marks.isEmpty ? attributed(text, ink: ink, font: font) : cachedAttributed(text, ink: ink, font: font)
        if !marks.isEmpty {
            var found = AttributeContainer()
            found.backgroundColor = markColor
            value.mark(marks, with: found)
        }
        attributedCache.setObject(AttributedBox(value), forKey: key)
        return value
    }

    private final class AttributedBox { let value: AttributedString; init(_ v: AttributedString) { value = v } }
    nonisolated(unsafe) private static let attributedCache: NSCache<NSString, AttributedBox> = { let c = NSCache<NSString, AttributedBox>(); c.countLimit = 2000; return c }()

    /// The text as styled runs (mentions bold in the link colour, addresses underlined links).
    static func attributed(_ text: String, ink: ChatBubbleInk, font: Font) -> AttributedString {
        var out = AttributedString()
        for token in ChatTextLabels.tokens(text) {
            switch token {
            case .text(let s):
                out += AttributedString(s)
            case .mention(let name, let id):
                var a = AttributedString("@\(name)")
                a.font = font.weight(.semibold)
                a.foregroundColor = ink.link.color
                a.link = URL(string: "\(mentionScheme)://\(id)")
                out += a
            case .url(let u):
                var a = AttributedString(u)
                a.foregroundColor = ink.link.color
                a.underlineStyle = .single
                a.link = URL(string: u)
                out += a
            }
        }
        out.font = font
        return out
    }
}
