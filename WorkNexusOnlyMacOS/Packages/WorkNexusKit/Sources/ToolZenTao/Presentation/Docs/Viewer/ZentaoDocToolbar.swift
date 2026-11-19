/// Ported from: lib/tools/zentao/presentation/widgets/{zentao_doc_header,zentao_doc_export_button,zentao_doc_history_button}.dart
import AppKit
import CoreDomain
import CoreUI
import SwiftUI

/// The reader's tools, floating at the page's top right: find in the document, the outline (when it isn't beside the
/// page), history, export, copy as Markdown, copy its link, open on ZenTao's web, the page's light / dark switch and
/// refresh.
struct ZentaoDocToolbar: View {
    @Environment(\.appTheme) private var readerTheme
    @Environment(\.toasts) private var toasts
    let docs: ZentaoDocsState; let account: Account; let doc: ZenTaoDoc
    /// Whether the app itself is dark, which the page switch returns to.
    let appDark: Bool
    let syncing: Bool; let finding: Bool
    let onRefresh: () -> Void; let onFind: () -> Void
    /// The outline's popover button, when the outline isn't beside the page.
    var outline: AnyView?
    var webUrl: URL?

    var body: some View {
        let dark = readerTheme.colors.isDark
        ZentaoDocFloatingCard {
            HStack(spacing: 0) {
                ZentaoDocToolButton(systemImage: "magnifyingglass", help: appString("docsFind", "Find in document"), selected: finding, action: onFind)
                if let outline { outline }
                ZentaoDocHistoryButton(docs: docs, account: account, docId: doc.id)
                ZentaoDocToolButton(systemImage: "doc.on.doc", help: appString("docsCopyMarkdown", "Copy the document as Markdown")) {
                    copy(docs.markdown(doc), appString("docsCopied", "Document copied as Markdown"))
                }
                ZentaoDocExportButton(docs: docs, account: account, doc: doc)
                if let webUrl {
                    ZentaoDocToolButton(systemImage: "link", help: appString("copyLink", "Copy link")) {
                        copy(webUrl.absoluteString, appString("docsLinkCopied", "Link to the document copied"))
                    }
                    ZentaoDocToolButton(systemImage: "arrow.up.right.square", help: appString("docsOpenInZenTao", "Open in ZenTao")) {
                        _ = openExternally(webUrl.absoluteString)
                    }
                }
                ZentaoDocToolButton(systemImage: dark ? "sun.max" : "moon", help: dark ? appString("docsReadOnLight", "Read on a light page")
                                    : appString("docsReadOnDark", "Read on a dark page")) {
                    docs.toggleReaderBrightness(currentDark: dark, appDark: appDark)
                }
                ZentaoDocToolButton(systemImage: "arrow.clockwise", help: appString("refresh", "Refresh"), loading: syncing, action: onRefresh)
            }
        }
    }

    private func copy(_ text: String, _ message: String) {
        NSPasteboard.general.clearContents(); NSPasteboard.general.setString(text, forType: .string)
        toasts?.show(message)
    }
}

/// The reader's Export button: a menu of ZenTao's export choices - Markdown, HTML, a JSON backup - each saving the
/// document to Downloads and showing the file there.
struct ZentaoDocExportButton: View {
    @Environment(\.appTheme) private var theme
    @Environment(\.toasts) private var toasts
    @State private var saving = false
    let docs: ZentaoDocsState; let account: Account; let doc: ZenTaoDoc

    var body: some View {
        AppMenuButton(help: appString("docsExport", "Export"), items: {
            ZenTaoDocExportFormat.allCases.map { format in
                AppNativeMenu.Item(label(format), icon: icon(format)) { Task { await save(format) } }
            }
        }) {
            Group {
                if saving { ProgressView().controlSize(.small) }
                else { Image(systemName: "square.and.arrow.up").font(.system(size: theme.sizes.icon16)).foregroundStyle(theme.colors.tx2) }
            }
            .frame(width: theme.sizes.control32, height: theme.sizes.control32).contentShape(Rectangle())
        }
        .fixedSize().disabled(saving)
    }

    private func icon(_ f: ZenTaoDocExportFormat) -> String {
        switch f { case .markdown: "doc.text"; case .html: "chevron.left.forwardslash.chevron.right"; case .backup: "curlybraces" }
    }
    private func label(_ f: ZenTaoDocExportFormat) -> String {
        switch f {
        case .markdown: appString("docsExportMarkdown", "Export Markdown")
        case .html: appString("docsExportHtml", "Export HTML")
        case .backup: appString("docsExportBackup", "Export backup (.json)")
        }
    }

    private func save(_ format: ZenTaoDocExportFormat) async {
        saving = true
        let res = await docs.export(account: account, doc: doc, format: format)
        saving = false
        switch res {
        case .success(let path):
            toasts?.show(appString("savedToDownloads", "Saved to Downloads"))
            revealInFileManager(path)
        case .failure: toasts?.show(appString("saveFailed", "Couldn't save the file"), kind: .error)
        }
    }
}

/// The toolbar's history button: the document's history in a popover under it, closed by a tap outside it (or Escape).
struct ZentaoDocHistoryButton: View {
    @State private var open = false
    let docs: ZentaoDocsState; let account: Account; let docId: String

    var body: some View {
        ZentaoDocToolButton(systemImage: "clock.arrow.circlepath", help: appString("docsHistory", "History"), selected: open) { open.toggle() }
            .popover(isPresented: $open, arrowEdge: .bottom) {
                ZentaoDocHistoryPanel(docs: docs, account: account, docId: docId) { open = false }
                    // Wide enough for a diff's lines of code; a long history scrolls inside.
                    .frame(width: 480, height: 480)
            }
    }
}
