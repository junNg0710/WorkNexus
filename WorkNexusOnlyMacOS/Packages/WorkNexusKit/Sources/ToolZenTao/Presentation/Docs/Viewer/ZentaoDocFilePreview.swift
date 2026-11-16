/// Ported from: lib/tools/zentao/presentation/widgets/zentao_doc_file_preview.dart
import AppKit
import CoreDomain
import CoreUI
import SwiftUI

/// An attached file shown in place, under its row: Markdown rendered as a page, other text as numbered code, an image as
/// itself. Downloaded once, when first shown.
struct ZentaoDocFilePreview: View {
    @Environment(\.appTheme) private var theme
    @State private var bytes: ZentaoLoad<Data> = .loading
    let docs: ZentaoDocsState; let account: Account; let file: TicketAttachment; let kind: ZentaoFilePreview

    var body: some View {
        Group {
            switch bytes {
            case .loading: ProgressView().controlSize(.small).frame(maxWidth: .infinity).padding(.vertical, theme.spacing.s24)
            case .failed:
                VStack(spacing: theme.spacing.s8) {
                    Text(appString("docsPreviewFailed", "Couldn't load the file")).font(theme.typography.paragraph).foregroundStyle(theme.colors.red)
                    AppButton(appString("retry", "Retry"), systemImage: "arrow.clockwise") { bytes = .loading; Task { await load() } }
                }
                .frame(maxWidth: .infinity).padding(.vertical, theme.spacing.s12)
            case .loaded(let data): shown(data)
            }
        }
        .task(id: file.id) { await load() }
    }

    private func load() async {
        switch await docs.repo.readFile(account: account, file: file) {
        case .success(let d): bytes = .loaded(d)
        case .failure(let f): bytes = .failed(f)
        }
    }

    @ViewBuilder private func shown(_ data: Data) -> some View {
        let text = String(decoding: data, as: UTF8.self)
        switch kind {
        case .markdown:
            MarkdownText(text, fontSize: theme.typography.proseSize, height: 1.6)
                .padding(theme.spacing.s20).frame(maxWidth: .infinity, alignment: .leading)
                .overlay(RoundedRectangle(cornerRadius: theme.radii.md).stroke(theme.colors.line, lineWidth: theme.borders.hairline))
        case .text:
            ZentaoDocCodeBlock(code: text.replacingOccurrences(of: "\n+$", with: "", options: .regularExpression),
                               fontSize: theme.typography.proseSize - 1.5)
        case .image:
            if let image = NSImage(data: data) {
                Image(nsImage: image).resizable().scaledToFit().clipShape(RoundedRectangle(cornerRadius: theme.radii.md))
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        case .none: EmptyView()
        }
    }
}
