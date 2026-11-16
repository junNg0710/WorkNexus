import SwiftUI

/// Ported from: lib/core/widgets/markdown_text.dart
/// Renders GitHub-flavoured Markdown using the app's text tokens. Ticket bodies, translations and comments all
/// flow through here: GitHub/GitLab already speak Markdown, and ZenTao's HTML is converted at normalize time.
/// `images` fetches inline images through an authenticated transport; `linkColor` defaults to the accent
/// (override on accent backgrounds); `onLinkTap` nil opens web links in the browser. `isPlainLink` draws matching links
/// (chat mentions) in the link colour only, no underline until hovered; `underlineLinksOnHover` does so for every link.
public struct MarkdownText: View {
    @Environment(\.appTheme) private var theme
    let data: String; let fontSize: CGFloat; let color: Color?; let height: CGFloat
    let images: BodyImageHooks; let linkColor: Color?; let onLinkTap: ((String) -> Void)?
    let linkStyle: BodyLinkStyle

    public init(_ data: String, fontSize: CGFloat = 13, color: Color? = nil, height: CGFloat = 1.6,
                images: BodyImageHooks = BodyImageHooks(), isPlainLink: ((String) -> Bool)? = nil,
                underlineLinksOnHover: Bool = false, linkColor: Color? = nil, onLinkTap: ((String) -> Void)? = nil) {
        self.linkStyle = BodyLinkStyle(isPlain: isPlainLink, underlineOnHover: underlineLinksOnHover)
        self.data = data; self.fontSize = fontSize; self.color = color; self.height = height
        self.images = images; self.linkColor = linkColor; self.onLinkTap = onLinkTap
    }

    /// The blocks `data` renders to (normalized, bare URLs linkified).
    public static func blocks(for data: String) -> [BodyBlock] {
        let text = linkifyBareUrls(normalizeMarkdown(data.trimmingCharacters(in: .whitespacesAndNewlines)))
        return text.isEmpty ? [] : MarkdownBlocks.parse(text)
    }

    public var body: some View {
        let blocks = Self.blocks(for: data)
        if blocks.isEmpty {
            Text("—").font(theme.typography.font(size: fontSize)).foregroundStyle(theme.colors.tx3)
        } else {
            BodyLinkScope(linkColor: linkColor, onLinkTap: onLinkTap, linkStyle: linkStyle) {
                BodyBlocksView(blocks: blocks, fontSize: fontSize, lineHeight: height, ink: color ?? theme.colors.tx, images: images)
            }
        }
    }
}
