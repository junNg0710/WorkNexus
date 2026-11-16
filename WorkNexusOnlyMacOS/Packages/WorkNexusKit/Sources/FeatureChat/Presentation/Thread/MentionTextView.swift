/// Ported from: lib/features/chat/presentation/widgets/mention_text.dart
import CoreUI
import SwiftUI

/// Plain message text: `[@Name](@#id)` mentions as highlighted `@Name`, and web addresses as tappable links. Colours and
/// size follow the bubble.
struct MentionTextView: View {
    @Environment(\.appTheme) private var theme
    @Environment(\.chatBubbleInk) private var ink
    let text: String
    let ctx: ThreadContext

    static let mentionScheme = "worknexus-mention"

    var body: some View {
        Text(Self.attributed(text, ink: ink, font: theme.typography.font(size: ink.fontSize)))
            .foregroundStyle(ink.text.color)
            .lineSpacing(ink.fontSize * 0.2)
            .tint(ink.link.color)
            .textSelection(.enabled)
            .fixedSize(horizontal: false, vertical: true)
            .environment(\.openURL, OpenURLAction { url in
                if url.scheme == Self.mentionScheme, let id = url.host.flatMap(Int.init) { ctx.actions.openProfile(id) }
                else { ctx.openLink(url.absoluteString) }
                return .handled
            })
    }

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
