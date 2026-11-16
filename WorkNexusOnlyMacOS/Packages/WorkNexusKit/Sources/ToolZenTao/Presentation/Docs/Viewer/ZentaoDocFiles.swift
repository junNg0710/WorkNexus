/// Ported from: lib/tools/zentao/presentation/widgets/zentao_doc_files.dart
import CoreDomain
import CoreUI
import SwiftUI

/// A document's attached files. A file the app can show (Markdown, text, an image) opens in place under its row with the
/// eye - a tap on the row does the same; any file saves to Downloads with the download button.
struct ZentaoDocFiles: View {
    @Environment(\.appTheme) private var theme
    let docs: ZentaoDocsState; let account: Account; let files: [TicketAttachment]
    /// Shows the first file in place from the start: a document that is only an attachment then reads like any other.
    var openFirst = false

    var body: some View {
        VStack(alignment: .leading, spacing: theme.spacing.s6) {
            Text("\(appString("attachments", "Attachments")) · \(files.count)".uppercased())
                .font(theme.typography.label).foregroundStyle(theme.colors.tx3)
                .padding(.bottom, theme.spacing.s2)
            ForEach(Array(files.enumerated()), id: \.element.id) { i, file in
                ZentaoDocFileRow(docs: docs, account: account, file: file, initiallyOpen: openFirst && i == 0)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct ZentaoDocFileRow: View {
    @Environment(\.appTheme) private var theme
    @Environment(\.toasts) private var toasts
    @State private var saving = false
    @State private var open: Bool
    @State private var hovering = false
    let docs: ZentaoDocsState; let account: Account; let file: TicketAttachment
    private let kind: ZentaoFilePreview

    init(docs: ZentaoDocsState, account: Account, file: TicketAttachment, initiallyOpen: Bool) {
        self.docs = docs; self.account = account; self.file = file
        kind = ZentaoFilePreview.of(file)
        _open = State(initialValue: initiallyOpen && kind != .none)
    }

    private var previewable: Bool { kind != .none }

    var body: some View {
        let c = theme.colors
        let subtitle = [formatFileSize(file.size), (file.addedBy ?? "").isEmpty ? nil : file.addedBy].compactMap { $0 }.joined(separator: " · ")
        VStack(alignment: .leading, spacing: theme.spacing.s8) {
            HStack(spacing: theme.spacing.s10) {
                Image(systemName: "paperclip").font(.system(size: theme.sizes.icon16)).foregroundStyle(c.accent)
                VStack(alignment: .leading, spacing: theme.spacing.s2) {
                    Text(file.title).font(theme.typography.paragraph).foregroundStyle(c.tx).lineLimit(1)
                    if !subtitle.isEmpty { Text(subtitle).font(theme.typography.caption).foregroundStyle(c.tx3) }
                }
                Spacer(minLength: theme.spacing.s8)
                if previewable {
                    ZentaoDocToolButton(systemImage: open ? "eye.slash" : "eye", help: open ? appString("docsHidePreview", "Hide the preview")
                                        : appString("docsPreviewFile", "Show the file here"), selected: open, small: true) { open.toggle() }
                }
                ZentaoDocToolButton(systemImage: "arrow.down.to.line", help: appString("docsDownloadFile", "Save to Downloads"),
                                    loading: saving, small: true) { Task { await save() } }
            }
            .padding(.horizontal, theme.spacing.s8).padding(.vertical, theme.spacing.s6)
            .background(hovering ? c.sel : c.panel2, in: RoundedRectangle(cornerRadius: theme.radii.md))
            .overlay(RoundedRectangle(cornerRadius: theme.radii.md).stroke(c.line, lineWidth: theme.borders.hairline))
            .contentShape(RoundedRectangle(cornerRadius: theme.radii.md))
            .onHover { hovering = $0 }
            .onTapGesture { if previewable { open.toggle() } else { Task { await save() } } }
            if open { ZentaoDocFilePreview(docs: docs, account: account, file: file, kind: kind) }
        }
    }

    private func save() async {
        if saving { return }
        saving = true
        let res = await docs.repo.saveFile(account: account, file: file)
        saving = false
        switch res {
        case .success(let path):
            toasts?.show(appString("savedToDownloads", "Saved to Downloads"))
            revealInFileManager(path)
        case .failure: toasts?.show(appString("saveFailed", "Couldn't save the file"), kind: .error)
        }
    }
}
