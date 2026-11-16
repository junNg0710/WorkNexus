/// Ported from: lib/tools/zentao/presentation/widgets/zentao_doc_body.dart
import CoreDomain
import CoreUI
import SwiftUI

/// What the page's blocks load images through: the account's authenticated session, with the document's site as the
/// "copy link / open in browser" fallback.
struct ZentaoDocImages {
    let account: Account; let repo: ZenTaoDocRepository

    var loader: ImageBytesLoader { { [repo, account] url in await repo.fetchImage(account: account, url: url) } }
    var fallbackUrl: ImageUrlResolver {
        let base = account.baseUrl
        return { url in
            guard let base, !base.isEmpty, let root = URL(string: base.hasSuffix("/") ? base : base + "/") else { return nil }
            return URL(string: url, relativeTo: root)?.absoluteURL.absoluteString
        }
    }
    var openImage: ImageExternalOpener { { url in await MainActor.run { _ = openExternally(url) } } }
}

/// A ZenTao document's HTML body, styled as a reference page rather than a comment: code goes through
/// `ZentaoDocCodeBlock`, tables get a ruled grid with a shaded header row, headings a rhythm with more air above than
/// below. Built whole (not lazily), so the page's length - and its scrollbar - is exact.
struct ZentaoDocBlockList: View {
    let blocks: [ZentaoDocBlock]; let reader: ZentaoDocReader; let images: ZentaoDocImages
    var color: Color?
    /// Inside a list item: paragraphs sit close, the list carries the space.
    var tight = false
    /// Space between the blocks (a table cell's paragraphs and images).
    var spacing: CGFloat = 0

    var body: some View {
        VStack(alignment: .leading, spacing: spacing) {
            ForEach(Array(blocks.enumerated()), id: \.offset) { _, b in
                ZentaoDocBlockView(block: b, reader: reader, images: images, color: color, tight: tight)
            }
        }
    }
}

/// Nested blocks (list items, quotes); type-erased because the model is recursive.
struct NestedBlocks: View {
    let blocks: [ZentaoDocBlock]; let reader: ZentaoDocReader; let images: ZentaoDocImages; let color: Color?; var tight = false
    var spacing: CGFloat = 0
    var body: AnyView { AnyView(ZentaoDocBlockList(blocks: blocks, reader: reader, images: images, color: color, tight: tight, spacing: spacing)) }
}

struct ZentaoDocBlockView: View {
    @Environment(\.appTheme) private var theme
    @Environment(\.zentaoDocAlign) private var align
    let block: ZentaoDocBlock; let reader: ZentaoDocReader; let images: ZentaoDocImages; var color: Color?; var tight = false

    var body: some View {
        let s = theme.spacing
        switch block {
        case .text(let runs, let level, _):
            ZentaoDocTextBlock(runs: runs, level: level, reader: reader, color: color)
                .padding(.top, level > 0 ? ZentaoDocText.spaceAbove(level, theme) : 0)
                .padding(.bottom, level > 0 ? s.s12 : (tight ? 0 : s.s16))
        case .image(let url):
            InlineImage(url: url, loader: images.loader, fallbackUrl: images.fallbackUrl, onOpenImage: images.openImage)
                .frame(maxWidth: .infinity, alignment: align.alignment)
                .padding(.bottom, tight ? s.s4 : s.s16)
        case .code(let code, let matches):
            ZentaoDocCodeBlock(code: code, fontSize: theme.typography.proseSize - 1.5, matches: matches, reader: reader)
                .padding(.top, s.s4).padding(.bottom, s.s12)
        case .quote(let inner):
            HStack(spacing: s.s10) {
                Rectangle().fill(theme.colors.line2).frame(width: theme.borders.thick)
                NestedBlocks(blocks: inner, reader: reader, images: images, color: theme.colors.tx2)
            }
            .fixedSize(horizontal: false, vertical: true).padding(.bottom, s.s16)
        case .list(let ordered, let start, let items):
            VStack(alignment: .leading, spacing: s.s4) {
                ForEach(Array(items.enumerated()), id: \.offset) { i, item in
                    HStack(alignment: .firstTextBaseline, spacing: s.s6) {
                        Text(ordered ? "\(start + i)." : "•").font(theme.typography.font(size: theme.typography.proseSize))
                            .foregroundStyle(theme.colors.tx2).frame(minWidth: s.s20, alignment: .trailing)
                        NestedBlocks(blocks: item, reader: reader, images: images, color: color, tight: true)
                    }
                }
            }
            .padding(.leading, s.s8).padding(.bottom, s.s16)
        case .table(let rows):
            ZentaoDocTable(rows: rows, reader: reader, images: images).padding(.top, s.s8).padding(.bottom, s.s20)
        case .aligned(let a, let inner):
            NestedBlocks(blocks: inner, reader: reader, images: images, color: color, tight: tight)
                .environment(\.zentaoDocAlign, a)
        case .rule:
            Divider().overlay(theme.colors.line).padding(.vertical, s.s24)
        }
    }
}
