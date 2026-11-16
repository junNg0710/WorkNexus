import AppKit
import CoreDomain
import CoreTools
import CoreUI
import SwiftUI

/// Ported from: lib/shared/detail/presentation/widgets/{attachment_kinds,attachment_viewer_dialog,attachment_viewer_header,
/// attachment_storage_panel}.dart (list part)
/// The ticket's files: one row each (icon, name, size, who added it); a click opens the viewer.
public struct AttachmentList: View {
    @Environment(\.appTheme) private var theme
    let controller: DetailController; let ticket: Ticket; let attachments: [TicketAttachment]
    public init(controller: DetailController, ticket: Ticket, attachments: [TicketAttachment]) {
        self.controller = controller; self.ticket = ticket; self.attachments = attachments
    }
    public var body: some View {
        if !attachments.isEmpty {
            VStack(alignment: .leading, spacing: theme.spacing.s6) {
                DetailSectionTitle(appString("attachments", "Attachments"), count: attachments.count)
                ForEach(attachments) { a in
                    let ext = AttachmentKinds.ext(of: a)
                    let icon = AttachmentKinds.video.contains(ext) ? "play.rectangle" : (AttachmentKinds.image.contains(ext) ? "photo" : "doc")
                    HoverSurface(onTap: { controller.openAttachment(ticket, a) }, fill: theme.colors.panel2, border: theme.showOutline ? theme.colors.line : nil) {
                        HStack(spacing: theme.spacing.s8) {
                            Image(systemName: icon).font(.system(size: theme.sizes.icon16)).foregroundStyle(theme.colors.accent)
                            Text(a.title).font(theme.typography.paragraph).foregroundStyle(theme.colors.tx).lineLimit(1)
                                .frame(maxWidth: .infinity, alignment: .leading)
                            if let size = formatFileSize(a.size) { Text(size).font(theme.typography.caption).foregroundStyle(theme.colors.tx3) }
                            if let by = a.addedBy, !by.isEmpty { Text(by).font(theme.typography.caption).foregroundStyle(theme.colors.tx3) }
                        }
                        .padding(.horizontal, theme.spacing.s10).padding(.vertical, theme.spacing.s8)
                    }
                }
            }
        }
    }
}

/// Previews an attachment: images enlarged (zoom with the wheel or a pinch, drag, double-click), videos played in
/// `AppVideoPlayerView` (streamed when the provider can, else from the downloaded copy), anything else offers "open".
/// Downloads through the sync service (cached for the session); Save copies it to Downloads. The frame follows the
/// window (`AdaptiveViewerFrame`) and a video can take the window full screen.
public struct AttachmentViewerDialog: View {
    @Environment(\.appTheme) private var theme
    @Environment(\.toasts) private var toasts
    let controller: DetailController; let request: AttachmentRequest; let onClose: () -> Void
    @State private var path: String?
    @State private var loading = true
    @State private var saving = false
    @State private var expanded = false

    public init(controller: DetailController, request: AttachmentRequest, onClose: @escaping () -> Void) {
        self.controller = controller; self.request = request; self.onClose = onClose
    }

    private var ext: String { AttachmentKinds.ext(of: request.attachment) }
    private var isVideo: Bool { AttachmentKinds.video.contains(ext) }

    /// The one download of the file, shared by the preview and Save.
    private func download() async -> String? {
        if let path { return path }
        let p = await controller.cacheAttachment(request.ticket, request.attachment)
        path = p
        return p
    }

    private func save() {
        guard !saving else { return }
        saving = true
        Task {
            var saved: String?
            if let path = await download(), let c = controller.services.ticketDetail as? SyncCoordinator {
                saved = await c.saveAttachmentToDownloads(cachedPath: path, name: request.attachment.title)
            }
            saving = false
            if let saved { NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: saved)]) }
            toasts?.show(saved != nil ? appString("savedToDownloads", "Saved to Downloads") : appString("saveFailed", "Couldn't save"),
                         kind: saved != nil ? .success : .error)
        }
    }

    private func toggleExpanded() { expanded.toggle(); AppWindowFullScreen.toggle() }

    private func videoSource() -> AppVideoSource {
        let controller = controller, ticket = request.ticket, att = request.attachment
        return AppVideoSource(
            title: att.title, fileExtension: ext, sizeBytes: att.size,
            stream: { await (controller.services.ticketDetail as? SyncCoordinator)?.attachmentStream(ticket, att) },
            download: { await controller.cacheAttachment(ticket, att) })
    }

    public var body: some View {
        let c = theme.colors
        let a = request.attachment
        AdaptiveViewerFrame(expanded: expanded) {
            VStack(spacing: 0) {
                HStack(spacing: theme.spacing.s8) {
                    Text(a.title).font(theme.typography.bodyStrong).foregroundStyle(c.tx).lineLimit(1)
                    if let size = formatFileSize(a.size) { Text(size).font(theme.typography.caption).foregroundStyle(c.tx3) }
                    Spacer()
                    if saving { ProgressView().controlSize(.small) }
                    AppIconButton("square.and.arrow.down", help: appString("save", "Save")) { save() }
                    AppIconButton("xmark", help: appString("close", "Close"), action: onClose)
                }
                .padding(theme.spacing.s12)
                .overlay(alignment: .bottom) { Rectangle().fill(c.line).frame(height: theme.borders.hairline) }
                Group {
                    if isVideo { AppVideoPlayerView(source: videoSource(), expanded: expanded, onToggleExpand: toggleExpanded).id(a.id) }
                    else if loading { ProgressView().controlSize(.regular) }
                    else if let path, AttachmentKinds.image.contains(ext), let img = NSImage(contentsOfFile: path) {
                        ZoomableImage(image: img, minScale: 1, maxScale: 5, inset: theme.spacing.s12)
                    } else {
                        VStack(spacing: theme.spacing.s8) {
                            Text(path == nil ? appString("attachmentLoadFailed", "Couldn't load the attachment") : appString("previewUnavailable", "No preview available"))
                                .font(theme.typography.body).foregroundStyle(path == nil ? c.red : c.tx2)
                            if let path { AppButton(appString("openInBrowser", "Open"), kind: .primary) { NSWorkspace.shared.open(URL(fileURLWithPath: path)) } }
                        }
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        // A video streams, so it is only downloaded whole to save it (or when streaming fails); the rest is shown from the file.
        .task { if !isVideo { _ = await download() }; loading = false }
        .onExitCommand { if expanded { toggleExpanded() } else { onClose() } }
        .onDisappear { if expanded { AppWindowFullScreen.exit() } }
    }
}
