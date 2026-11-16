/// Ported from: lib/features/chat/presentation/widgets/link_preview_card.dart
import CoreDomain
import CoreUI
import SwiftUI

/// A preview of the web page a message links to — site, title, description and a square image — at a fixed height. While
/// loading it shows skeleton lines; when the page has nothing to show, its address.
struct LinkPreviewCard: View {
    @Environment(\.appTheme) private var theme
    @Environment(\.chatBubbleInk) private var ink
    let ctx: ThreadContext
    let url: String
    /// Fixed card height: the space is reserved as soon as a message has a link, so the list never jumps when the preview
    /// arrives (or turns out empty).
    static let height: CGFloat = 72
    @State private var preview: LinkPreview?
    @State private var loading = true

    var body: some View {
        ChatLinkCardFrame(onTap: { ctx.openLink(url) }, height: Self.height) {
            HStack(spacing: 0) {
                Group { if loading { LinkPreviewSkeleton() } else { LinkPreviewLines(url: url, preview: preview) } }
                    .frame(maxWidth: .infinity, alignment: .leading)
                if let image = preview?.imageUrl, let u = URL(string: image) {
                    AsyncImage(url: u) { $0.resizable().scaledToFill() } placeholder: { Color.clear }
                        .frame(width: Self.height, height: Self.height).clipped()
                        .padding(.trailing, -theme.spacing.s10)
                }
            }
        }
        .task(id: url) {
            guard let repo = ctx.services.linkPreviews else { loading = false; return }
            preview = await LoadLinkPreview(repo)(url).value ?? nil
            loading = false
        }
    }
}

/// Site, title, description — one line each; the address when the page has no preview.
private struct LinkPreviewLines: View {
    @Environment(\.appTheme) private var theme
    @Environment(\.chatBubbleInk) private var ink
    let url: String
    let preview: LinkPreview?

    var body: some View {
        let site = ChatColor.readable(ink.link, on: ink.quoteSurface, towards: ink.text).color
        VStack(alignment: .leading, spacing: 0) {
            Text(preview?.siteName ?? ChatTextLabels.linkHost(url)).font(theme.typography.label).foregroundStyle(site)
            Text(preview?.title ?? url).font(theme.typography.bodyStrong).foregroundStyle(ink.text.color)
            if let d = preview?.description { Text(d).font(theme.typography.paragraph).foregroundStyle(ink.text.color) }
        }
        .lineLimit(1).truncationMode(.tail)
    }
}

private struct LinkPreviewSkeleton: View {
    @Environment(\.appTheme) private var theme
    @Environment(\.chatBubbleInk) private var ink

    var body: some View {
        VStack(alignment: .leading, spacing: theme.spacing.s4) {
            ForEach([0.3, 0.8, 0.6], id: \.self) { f in
                GeometryReader { g in
                    RoundedRectangle(cornerRadius: theme.radii.xs).fill(ink.text.opacity(0.08).color).frame(width: g.size.width * f)
                }
                .frame(height: theme.spacing.s10)
            }
        }
    }
}
