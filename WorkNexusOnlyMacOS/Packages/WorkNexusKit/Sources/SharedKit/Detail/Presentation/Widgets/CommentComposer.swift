import CoreDomain
import CoreUI
import SwiftUI

/// Ported from: lib/shared/detail/presentation/widgets/comment_composer.dart
/// Write-a-comment box under the timeline: the rich-text editor for ZenTao (HTML in, images uploaded through the
/// `DetailExtensions.uploadImage` hook), a plain text field for the Git providers. Posting goes through the
/// provider; on success the box clears and the DB stream shows the comment, on failure a toast.
public struct CommentComposer: View {
    @Environment(\.appTheme) private var theme
    @Environment(\.toasts) private var toasts
    let controller: DetailController; let ticket: Ticket; let model: TicketDetailModel
    @State private var text = ""
    @State private var html = HtmlEditingController()
    @State private var editorId = UUID()
    @State private var posting = false
    /// The files-upload id of this composer; a new one after each posted comment.
    @State private var uid = String(Int(Date().timeIntervalSince1970 * 1_000_000), radix: 16)

    public init(controller: DetailController, ticket: Ticket, model: TicketDetailModel) {
        self.controller = controller; self.ticket = ticket; self.model = model
    }

    private var rich: Bool { ticket.providerType == .zentao }

    private func post() {
        let body = rich ? html.html : text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !body.isEmpty, !posting else { return }
        posting = true
        Task {
            let ok = await model.postComment(ticket, body: body)
            posting = false
            if ok {
                if rich { html = HtmlEditingController(); editorId = UUID(); uid = String(Int(Date().timeIntervalSince1970 * 1_000_000), radix: 16) } else { text = "" }
            } else {
                toasts?.show(appString("commentPostFailed", "Couldn't post comment"), kind: .error)
            }
        }
    }

    /// Uploads a comment image under this composer's id when the host gave a uid-aware hook, else its plain hook.
    private var uploader: EditorImageUploader? {
        let ticket = ticket, uid = uid
        if let up = controller.extensions.uploadImageWithUid { return { data, name in await up(ticket, uid, data, name) } }
        return controller.extensions.uploadImage.map { up in { data, name in await up(ticket, data, name) } }
    }

    public var body: some View {
        let c = theme.colors
        let hint = appString("writeCommentHint", "Write a comment…")
        VStack(alignment: .trailing, spacing: theme.spacing.s8) {
            if rich {
                RichTextEditor(controller: html, imageLoader: { [controller, ticket] url in await controller.fetchImage(ticket, url) },
                               onUploadImage: uploader,
                               minHeight: 96, placeholder: hint)
                    .id(editorId)
            } else {
                TextField(hint, text: $text, axis: .vertical).lineLimit(2...8).textFieldStyle(.plain)
                    .font(theme.typography.body).padding(theme.spacing.s8)
                    .background(c.panel2, in: RoundedRectangle(cornerRadius: theme.radii.md))
                    .overlay(RoundedRectangle(cornerRadius: theme.radii.md).stroke(c.line, lineWidth: theme.borders.hairline))
            }
            HStack(spacing: theme.spacing.s6) {
                if posting { ProgressView().controlSize(.small) }
                AppButton(appString("commentAction", "Comment"), kind: .primary, action: post).disabled(posting)
            }
        }
    }
}
