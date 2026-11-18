import SwiftUI

/// Image-related hooks shared by the body renderers (`MarkdownText`, `HtmlText`, `RichBodyText`).
public struct BodyImageHooks {
    /// Fetches inline images through an authenticated transport (ZenTao's assets are session-protected, behind
    /// self-signed TLS); without it images use the default network loader.
    public var loader: ImageBytesLoader?
    /// When it yields non-nil for an image whose bytes failed to load, a "copy link / open in browser" bar is shown.
    public var fallbackUrl: ImageUrlResolver?
    public var onOpenImage: ImageExternalOpener?
    public init(loader: ImageBytesLoader? = nil, fallbackUrl: ImageUrlResolver? = nil, onOpenImage: ImageExternalOpener? = nil) {
        self.loader = loader; self.fallbackUrl = fallbackUrl; self.onOpenImage = onOpenImage
    }
}

/// Draws `BodyBlock`s with the app's text tokens: headings scale from the body size (ratios follow GitLab's
/// rendered markdown), lists / quotes / tables / code nest, images load through `images`.
struct BodyBlocksView: View {
    @Environment(\.appTheme) private var theme
    let blocks: [BodyBlock]
    let fontSize: CGFloat
    let lineHeight: CGFloat
    let ink: Color
    let images: BodyImageHooks

    var body: some View {
        VStack(alignment: .leading, spacing: theme.spacing.s8) {
            ForEach(Array(blocks.enumerated()), id: \.offset) { _, b in
                BodyBlockView(block: b, fontSize: fontSize, lineHeight: lineHeight, ink: ink, images: images)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// Nested block content (list items, quotes); type-erased because the model is recursive.
private struct NestedBlocks: View {
    let blocks: [BodyBlock]; let fontSize: CGFloat; let lineHeight: CGFloat; let ink: Color; let images: BodyImageHooks
    var body: AnyView { AnyView(BodyBlocksView(blocks: blocks, fontSize: fontSize, lineHeight: lineHeight, ink: ink, images: images)) }
}

struct BodyBlockView: View {
    @Environment(\.appTheme) private var theme
    let block: BodyBlock; let fontSize: CGFloat; let lineHeight: CGFloat; let ink: Color; let images: BodyImageHooks
    static let headingScale: [CGFloat] = [1, 1.6, 1.4, 1.2, 1.1, 1, 1]

    private func nested(_ b: [BodyBlock], ink: Color? = nil) -> NestedBlocks {
        NestedBlocks(blocks: b, fontSize: fontSize, lineHeight: lineHeight, ink: ink ?? self.ink, images: images)
    }

    var body: some View {
        switch block {
        case .text(let s, let level):
            let size = fontSize * Self.headingScale[min(level, 6)]
            BodyInlineText(text: s, plainFont: theme.typography.font(size: size, weight: .semibold))
                .font(theme.typography.font(size: size, weight: level > 0 ? .semibold : .regular))
                .foregroundStyle(ink).lineSpacing(max(lineHeight - 1.2, 0) * fontSize)
                .textSelection(.enabled)
                // As tall as all its lines: measured shorter (selectable text with extra line spacing, in a list row) a long
                // comment overflowed its card and was drawn over the rows above and below it.
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
        case .image(let url, _, let width):
            if let loader = images.loader {
                InlineImage(url: url, loader: loader, fallbackUrl: images.fallbackUrl, onOpenImage: images.onOpenImage, width: width.map { CGFloat($0) })
            } else if let u = URL(string: url) {
                AsyncImage(url: u) { $0.resizable().scaledToFit() } placeholder: { ProgressView().controlSize(.small) }
                    .frame(maxHeight: 400, alignment: .leading)
            }
        case .code(let code):
            CodeBlock(code, fontSize: fontSize - 1).padding(.vertical, theme.spacing.s4)
        case .quote(let inner):
            HStack(spacing: theme.spacing.s10) {
                Rectangle().fill(theme.colors.line2).frame(width: theme.borders.thick)
                nested(inner, ink: theme.colors.tx2)
            }.fixedSize(horizontal: false, vertical: true)
        case .list(let ordered, let start, let items):
            VStack(alignment: .leading, spacing: theme.spacing.s4) {
                ForEach(Array(items.enumerated()), id: \.offset) { i, item in
                    HStack(alignment: .firstTextBaseline, spacing: theme.spacing.s6) {
                        Text(ordered ? "\(start + i)." : "•").font(theme.typography.font(size: fontSize)).foregroundStyle(theme.colors.tx2)
                            .frame(minWidth: theme.spacing.s16, alignment: .trailing)
                        nested(item)
                    }
                    .fixedSize(horizontal: false, vertical: true)
                }
            }
        case .table(let header, let rows):
            TableBlock(header: header, rows: rows, fontSize: fontSize, ink: ink)
        case .rule:
            Divider().overlay(theme.colors.line).padding(.vertical, theme.spacing.s4)
        }
    }
}

private struct TableBlock: View {
    @Environment(\.appTheme) private var theme
    let header: [AttributedString]; let rows: [[AttributedString]]; let fontSize: CGFloat; let ink: Color
    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            Grid(alignment: .leading, horizontalSpacing: 0, verticalSpacing: 0) {
                if !header.isEmpty { GridRow { ForEach(Array(header.enumerated()), id: \.offset) { _, c in TableCell(text: c, head: true, fontSize: fontSize, ink: ink) } } }
                ForEach(Array(rows.enumerated()), id: \.offset) { _, r in
                    GridRow { ForEach(Array(r.enumerated()), id: \.offset) { _, c in TableCell(text: c, head: false, fontSize: fontSize, ink: ink) } }
                }
            }
            .overlay(Rectangle().stroke(theme.colors.line, lineWidth: theme.borders.hairline))
        }
    }
}

private struct TableCell: View {
    @Environment(\.appTheme) private var theme
    let text: AttributedString; let head: Bool; let fontSize: CGFloat; let ink: Color
    var body: some View {
        Text(text).font(theme.typography.font(size: fontSize, weight: head ? .semibold : .regular)).foregroundStyle(ink)
            .padding(.horizontal, theme.spacing.s10).padding(.vertical, theme.spacing.s6)
            .frame(minWidth: 60, maxWidth: .infinity, alignment: .leading)
            .background(head ? theme.colors.panel2 : .clear)
            .overlay(Rectangle().stroke(theme.colors.line, lineWidth: theme.borders.hairline))
    }
}

/// Wraps rendered body content with link handling (taps go to `onLinkTap`, default the browser) and tint.
struct BodyLinkScope<Content: View>: View {
    @Environment(\.appTheme) private var theme
    let linkColor: Color?; let onLinkTap: ((String) -> Void)?; let linkStyle: BodyLinkStyle; let content: Content
    init(linkColor: Color?, onLinkTap: ((String) -> Void)?, linkStyle: BodyLinkStyle = BodyLinkStyle(), @ViewBuilder content: () -> Content) {
        self.linkColor = linkColor; self.onLinkTap = onLinkTap; self.linkStyle = linkStyle; self.content = content()
    }
    var body: some View {
        content.tint(linkColor ?? theme.colors.accent)
            .environment(\.bodyLinkStyle, linkStyle)
            .environment(\.openURL, OpenURLAction { url in
                let target = url.absoluteString
                if let onLinkTap { onLinkTap(target) } else { openLinkExternally(target) }
                return .handled
            })
    }
}
