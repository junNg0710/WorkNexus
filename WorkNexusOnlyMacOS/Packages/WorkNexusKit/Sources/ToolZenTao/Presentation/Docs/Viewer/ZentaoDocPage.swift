/// Ported from: lib/tools/zentao/presentation/widgets/zentao_doc_page.dart
import CoreDomain
import CoreUI
import SwiftUI

/// The top of each outlined block from the viewport's top, by heading index: what the reader tracks the heading being
/// read from.
struct ZentaoHeadingTopsKey: PreferenceKey {
    static let defaultValue: [Int: CGFloat] = [:]
    static func reduce(value: inout [Int: CGFloat], nextValue: () -> [Int: CGFloat]) { value.merge(nextValue()) { $1 } }
}

private struct ScrollMetrics: Equatable { var offset: CGFloat; var viewport: CGFloat; var atEnd: Bool }

/// The scrolling page of a document: its header, the prepared body (`blocks`), its files. It tells the `reader` which
/// heading is being read as it scrolls, for the outline.
struct ZentaoDocPage: View {
    @Environment(\.appTheme) private var theme
    @State private var position = ScrollPosition()
    let docs: ZentaoDocsState; let account: Account; let doc: ZenTaoDoc; let blocks: [ZentaoDocBlock]
    let layout: ZentaoDocLayout; let reader: ZentaoDocReader
    /// Width kept free on the right (the outline sits there, over the page).
    var rightInset: CGFloat = 0

    static let space = "zentaoDocPage"
    /// The reading column's width (a long-form document, ~80 characters).
    static let reading: CGFloat = 780

    var body: some View {
        let s = theme.spacing
        let lead = s.s40 * 2
        let images = ZentaoDocImages(account: account, repo: docs.repo)
        GeometryReader { box in
            // The column is centred by padding, not by a narrower box, so the wheel scrolls the page wherever the pointer is.
            let side = max(s.s40, (box.size.width - rightInset - Self.reading) / 2)
            ScrollViewReader { proxy in
                ScrollView {
                    VStack(alignment: .leading, spacing: 0) {
                        // Room for the floating tools above the title.
                        ZentaoDocHeader(accountId: account.id, doc: doc, dateFormat: docs.settings.dateFormat)
                            .padding(.top, s.s40 + s.s8).padding(.bottom, s.s24)
                        if doc.hasBody {
                            ForEach(Array(blocks.enumerated()), id: \.offset) { i, block in
                                ZentaoDocBlockView(block: block, reader: reader, images: images).id(i).background(probe(i))
                            }
                        } else if doc.isAttachment && doc.files.isEmpty {
                            Text(appString("docsAttachmentOnly", "This document is an attached file."))
                                .font(theme.typography.font(size: theme.typography.proseSize)).foregroundStyle(theme.colors.tx3)
                        }
                        if !doc.files.isEmpty {
                            ZentaoDocFiles(docs: docs, account: account, files: doc.files, openFirst: doc.isAttachment && !doc.hasBody)
                                .padding(.top, s.s24)
                        }
                        Color.clear.frame(height: s.s40)
                    }
                    .padding(.leading, side).padding(.trailing, side + rightInset)
                }
                .scrollPosition($position)
                .coordinateSpace(.named(Self.space))
                .onScrollGeometryChange(for: ScrollMetrics.self) { g in
                    ScrollMetrics(offset: g.contentOffset.y, viewport: g.containerSize.height,
                                  atEnd: g.contentOffset.y + g.containerSize.height >= g.contentSize.height - 1)
                } action: { _, m in
                    docs.readingOffsets[doc.id] = m.offset
                    reader.track(viewportHeight: m.viewport, atEnd: m.atEnd, lead: lead)
                }
                .onPreferenceChange(ZentaoHeadingTopsKey.self) { tops in
                    MainActor.assumeIsolated { reader.track(tops: tops, lead: lead) }
                }
                .onChange(of: reader.scrollRequest) { _, request in
                    guard let request else { return }
                    withAnimation(.easeOut(duration: 0.25)) { proxy.scrollTo(request.block, anchor: request.anchor) }
                }
                .task {
                    // Back on a document left half read: its place again.
                    if let y = docs.readingOffsets[doc.id], y > 0 { position.scrollTo(y: y) }
                }
            }
        }
        // One selection across title, text, tables and code, so any part of the page can be dragged over and copied.
        .textSelection(.enabled)
        .environment(\.openURL, OpenURLAction { url in
            openLinkExternally(url.absoluteString) ? .handled : .systemAction
        })
    }

    /// Reports where block `i` sits when it holds outlined headings.
    @ViewBuilder private func probe(_ i: Int) -> some View {
        let anchors = i < layout.anchorsOfBlock.count ? layout.anchorsOfBlock[i] : []
        if !anchors.isEmpty {
            GeometryReader { g in
                Color.clear.preference(key: ZentaoHeadingTopsKey.self,
                                       value: Dictionary(uniqueKeysWithValues: anchors.map { ($0, g.frame(in: .named(Self.space)).minY) }))
            }
        }
    }
}
