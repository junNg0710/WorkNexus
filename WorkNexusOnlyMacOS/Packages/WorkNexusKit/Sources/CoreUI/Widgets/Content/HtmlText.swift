import CoreDomain
import SwiftUI

/// Ported from: lib/core/widgets/html_text.dart
/// Renders a provider's HTML as it is — ZenTao's descriptions and comments come from its rich-text editor — in
/// the app's text style. `images.loader` fetches `<img>`s through an authenticated transport (ZenTao's assets
/// are session-protected, behind self-signed TLS), with the same loading / broken / "open in browser" states as
/// Markdown. `onLinkTap` nil opens web links in the browser.
public struct HtmlText: View {
    @Environment(\.appTheme) private var theme
    let html: String; let fontSize: CGFloat; let height: CGFloat
    let images: BodyImageHooks; let onLinkTap: ((String) -> Void)?

    public init(_ html: String, fontSize: CGFloat = 13, height: CGFloat = 1.6,
                images: BodyImageHooks = BodyImageHooks(), onLinkTap: ((String) -> Void)? = nil) {
        self.html = html; self.fontSize = fontSize; self.height = height; self.images = images; self.onLinkTap = onLinkTap
    }

    public var body: some View {
        if html.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            Text("—").font(theme.typography.font(size: fontSize)).foregroundStyle(theme.colors.tx3)
        } else {
            BodyLinkScope(linkColor: nil, onLinkTap: onLinkTap) {
                BodyBlocksView(blocks: HtmlBlocks.parse(html), fontSize: fontSize, lineHeight: height, ink: theme.colors.tx, images: images)
            }
        }
    }
}

/// Ported from: lib/core/widgets/rich_body_text.dart
/// A description or comment in the format its provider wrote it: HTML (ZenTao) through `HtmlText`, Markdown
/// (GitHub, GitLab) through `MarkdownText`. `html` says which (see `isHtmlBody(_:_:)`).
public struct RichBodyText: View {
    let text: String; let html: Bool; let fontSize: CGFloat; let height: CGFloat; let images: BodyImageHooks
    public init(_ text: String, html: Bool, fontSize: CGFloat = 13, height: CGFloat = 1.6, images: BodyImageHooks = BodyImageHooks()) {
        self.text = text; self.html = html; self.fontSize = fontSize; self.height = height; self.images = images
    }
    public var body: some View {
        if html { HtmlText(text, fontSize: fontSize, height: height, images: images) }
        else { MarkdownText(text, fontSize: fontSize, height: height, images: images) }
    }
}

/// Ported from: lib/core/util/body_format.dart
/// Whether a description or comment `text` from `provider` is HTML: ZenTao keeps its rich-text editor's HTML as
/// written; everything else is Markdown (where an inline tag is still Markdown).
public func isHtmlBody(_ provider: ProviderType, _ text: String) -> Bool {
    provider == .zentao && text.range(
        of: #"<(?:p|div|br|span|img|strong|b|em|i|u|ul|ol|li|table|tr|td|th|h[1-6]|a|pre|code|blockquote|font|hr)\b[^>]*>"#,
        options: [.regularExpression, .caseInsensitive]) != nil
}
