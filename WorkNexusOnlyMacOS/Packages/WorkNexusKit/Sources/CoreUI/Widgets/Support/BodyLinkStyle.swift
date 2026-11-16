import SwiftUI

/// Ported from: lib/core/widgets/markdown_text.dart (`isPlainLink`, `underlineLinksOnHover`, `inlineLinkBuilder`)
/// How inline links of a rendered body are drawn. A "plain" link (a chat mention) is the link colour, semibold, with no
/// underline until hovered; with `underlineOnHover` every link rests without an underline (GitLab / GitHub descriptions)
/// and gets one on hover; otherwise links are underlined. SwiftUI `Text` cannot report which link the pointer is on, so
/// hover is tracked per text block: pointing at the block underlines its links.
public struct BodyLinkStyle {
    public var isPlain: ((String) -> Bool)?
    public var underlineOnHover: Bool
    public init(isPlain: ((String) -> Bool)? = nil, underlineOnHover: Bool = false) {
        self.isPlain = isPlain; self.underlineOnHover = underlineOnHover
    }

    /// True when this style changes anything from the default (so a plain body skips the styling pass and hover tracking).
    var isCustom: Bool { isPlain != nil || underlineOnHover }

    /// Whether the link at `url` is drawn without an underline while not hovered.
    func restsWithoutUnderline(_ url: String) -> Bool { (isPlain?(url) ?? false) || underlineOnHover }

    /// `text` with every link run's underline (and, for plain links, weight) set for the hover state.
    func apply(to text: AttributedString, hovered: Bool, plainFont: Font? = nil) -> AttributedString {
        guard isCustom else { return text }
        var out = text
        for run in out.runs {
            guard let link = run.link else { continue }
            let url = link.absoluteString
            let resting = restsWithoutUnderline(url)
            out[run.range].underlineStyle = resting && !hovered ? nil : .single
            if isPlain?(url) ?? false, let plainFont { out[run.range].font = plainFont }
        }
        return out
    }
}

private struct BodyLinkStyleKey: EnvironmentKey { static let defaultValue = BodyLinkStyle() }

extension EnvironmentValues {
    var bodyLinkStyle: BodyLinkStyle {
        get { self[BodyLinkStyleKey.self] }
        set { self[BodyLinkStyleKey.self] = newValue }
    }
}

/// A block of rich inline text whose links follow the `bodyLinkStyle` of the enclosing `BodyLinkScope`.
struct BodyInlineText: View {
    @Environment(\.bodyLinkStyle) private var style
    @State private var hovered = false
    let text: AttributedString; let plainFont: Font?
    var body: some View {
        let shown = style.apply(to: text, hovered: hovered, plainFont: plainFont)
        if style.isCustom { Text(shown).onHover { hovered = $0 } } else { Text(shown) }
    }
}
