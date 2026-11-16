/// Ported from: lib/tools/zentao/presentation/widgets/zentao_doc_viewer.dart
import CoreDomain
import CoreUI
import SwiftUI

/// A body prepared for the page: its outline, its blocks, and where each heading and match sits - prepared again only
/// when the body or the query changes.
@MainActor
final class ZentaoDocPreparedCache {
    struct Result {
        var headings: [ZentaoDocHeading]; var blocks: [ZentaoDocBlock]; var layout: ZentaoDocLayout; var matchCount: Int
    }
    private var last: (html: String, query: String, result: Result)?

    func get(html: String, query: String) -> Result {
        if let last, last.html == html, last.query == query { return last.result }
        let p = prepareZentaoDocHtml(html, query: query)
        let blocks = ZentaoDocBlocks.build(p.root)
        let result = Result(headings: p.headings, blocks: blocks, layout: ZentaoDocLayout(blocks), matchCount: p.matchCount)
        last = (html, query, result)
        return result
    }
}

/// One document: its cached copy at once, fetched afresh when opened. A text document shows its HTML body; an
/// attachment document its files. Find in the document (Cmd+F / Ctrl+F) and its outline - beside the page when there is
/// room, in a popover otherwise - work on the body as prepared here.
struct ZentaoDocViewer: View {
    @Environment(\.appTheme) private var appTheme
    @State private var reader = ZentaoDocReader()
    @State private var cache = ZentaoDocPreparedCache()
    @State private var finding = false
    @State private var query = ""
    let docs: ZentaoDocsState; let account: Account; let docId: String

    var body: some View {
        // Every state sits on the reader's page, so switching documents never shows the window's (greyer) background
        // between two pages.
        ZentaoDocReaderTheme(docs: docs) { content }
            .task(id: docId) { await docs.observeDoc(accountId: account.id, docId: docId) }
            .task(id: docId) { await docs.ensure(fetch, account: account) }
    }

    private var fetch: ZentaoDocFetch { .doc(accountId: account.id, docId: docId) }

    @ViewBuilder private var content: some View {
        let sync = docs.sync(fetch)
        if let doc = docs.doc(accountId: account.id, docId: docId) {
            page(doc, syncing: sync.isLoading)
        } else if !docs.isDocAnswered(accountId: account.id, docId: docId) {
            // The cache answers within a frame: a spinner here would only blink.
            Color.clear
        } else if sync.isLoading {
            AppStateView(.loading)
        } else if case .notFound = sync.failure {
            AppStateView(.error("\(appString("docsUnreadable", "Can't open this document"))\n\(appString("docsUnreadableHint", "You may not have access to it, or it was deleted."))")) { refresh() }
        } else {
            AppStateView(.error(sync.failure?.message ?? appString("somethingWentWrong", "Something went wrong"))) { refresh() }
        }
    }

    private func refresh() { Task { await docs.ensure(fetch, account: account, force: true) } }

    private func openFind() { finding = true }
    private func closeFind() { finding = false; query = "" }

    private func page(_ doc: ZenTaoDoc, syncing: Bool) -> some View {
        let prepared = cache.get(html: doc.html, query: query)
        let outlineWidth = appTheme.sizes.toolPaneCompact
        let hasOutline = prepared.headings.count >= 2
        return GeometryReader { box in
            // Beside the page only with room for both.
            let beside = hasOutline && box.size.width >= ZentaoDocPage.reading + outlineWidth + appTheme.spacing.s40 * 2
            ZStack(alignment: .topTrailing) {
                // The page spans the whole width, so its scrollbar runs down the window's right edge; the outline sits
                // over the page's right margin, which the page leaves free for it.
                ZentaoDocPage(docs: docs, account: account, doc: doc, blocks: prepared.blocks, layout: prepared.layout,
                              reader: reader, rightInset: beside ? outlineWidth : 0)
                if beside {
                    ZentaoDocOutline(headings: prepared.headings, reader: reader)
                        .frame(width: outlineWidth).frame(maxHeight: .infinity, alignment: .top)
                        // Below the floating tools, clear of the page's scrollbar along the edge.
                        .padding(.top, appTheme.sizes.control36 + appTheme.spacing.s12).padding(.trailing, appTheme.spacing.s10)
                }
                // The find bar floats on the tools' line, to their left.
                HStack(alignment: .top, spacing: appTheme.spacing.s6) {
                    if finding {
                        ZentaoDocFindBar(reader: reader, query: query, onQuery: { query = $0 }, onClose: closeFind)
                    }
                    ZentaoDocToolbar(docs: docs, account: account, doc: doc, appDark: appTheme.colors.isDark, syncing: syncing,
                                     finding: finding, onRefresh: refresh, onFind: { finding ? closeFind() : openFind() },
                                     outline: hasOutline && !beside ? AnyView(ZentaoDocOutlineButton(headings: prepared.headings, reader: reader)) : nil,
                                     webUrl: Self.webUrl(account: account, docId: doc.id))
                }
                .padding(.top, appTheme.spacing.s8).padding(.trailing, appTheme.spacing.s10 + appTheme.spacing.s8)
            }
        }
        .onChange(of: PrepKey(html: doc.html, query: query), initial: true) {
            // The marks exist once the page is built from it.
            reader.layout = prepared.layout
            reader.resetMatches(prepared.matchCount)
            Task { reader.revealCurrent() }
        }
        .background { shortcuts }
    }

    private struct PrepKey: Equatable { var html: String; var query: String }

    /// Cmd+F and Ctrl+F open the find bar.
    private var shortcuts: some View {
        ZStack {
            Button("") { openFind() }.keyboardShortcut("f", modifiers: .command)
            Button("") { openFind() }.keyboardShortcut("f", modifiers: .control)
        }
        .opacity(0).allowsHitTesting(false)
    }

    /// The document on ZenTao's web (`doc-view-{id}.html`).
    static func webUrl(account: Account, docId: String) -> URL? {
        guard let base = account.baseUrl, !base.isEmpty, let root = URL(string: base.hasSuffix("/") ? base : base + "/") else { return nil }
        return URL(string: "doc-view-\(docId).html", relativeTo: root)?.absoluteURL
    }
}
