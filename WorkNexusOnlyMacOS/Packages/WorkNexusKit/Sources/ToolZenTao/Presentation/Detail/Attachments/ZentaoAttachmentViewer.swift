/// Ported from: lib/shared/detail/presentation/widgets/attachment_viewer_dialog.dart (as the ZenTao bug attachments use it)
import AVFoundation
import AppKit
import CoreDomain
import CoreUI
import SharedKit
import SwiftUI

/// What the viewer loaded for an attachment.
enum ZentaoAttachmentContent {
    case loading, failed
    case video(AppVideoSource)
    case image(NSImage)
    case text(String, markdown: Bool)
    case unsupported
}

/// Previews an attachment in place with the account's session: a video plays in `AppVideoPlayerView` (streamed from
/// ZenTao with the session as request headers, else downloaded whole), an image opens in a zoomable view, a text file
/// is downloaded through the authenticated client. Save puts the file in Downloads. The frame follows the window
/// (`AdaptiveViewerFrame`); a video can fill it and take the window full screen.
struct ZentaoAttachmentViewer: View {
    @Environment(\.appTheme) private var theme
    @Environment(\.toasts) private var toasts
    let deps: ZentaoDependencies; let ticket: Ticket; let attachment: TicketAttachment; let onClose: () -> Void
    @State private var content = ZentaoAttachmentContent.loading
    @State private var bytes: Data?
    @State private var saving = false
    @State private var expanded = false

    private var sync: SyncCoordinator? { deps.services.ticketDetail as? SyncCoordinator }

    private func adapter() async -> ProviderAdapter? {
        guard let account = await deps.account(id: ticket.accountId) else { return nil }
        return await deps.services.sync.adapter(for: account)
    }

    /// The file's bytes, downloaded once and kept for Save.
    private func download() async -> Data? {
        if let bytes { return bytes }
        guard let data = await adapter()?.downloadBytes(url: attachment.url) else { return nil }
        bytes = data
        return data
    }

    private func videoSource() -> AppVideoSource {
        let ticket = ticket, attachment = attachment, deps = deps
        return AppVideoSource(
            title: attachment.title, fileExtension: ZentaoFileKinds.ext(of: attachment), sizeBytes: attachment.size,
            stream: {
                if let sync = deps.services.ticketDetail as? SyncCoordinator, let r = await sync.attachmentStream(ticket, attachment) { return r }
                guard let account = await deps.account(id: ticket.accountId), let a = await deps.services.sync.adapter(for: account) else { return nil }
                return await a.streamRequest(url: attachment.streamUrl ?? attachment.url)
            },
            download: {
                if let sync = deps.services.ticketDetail as? SyncCoordinator { return await sync.cacheAttachment(ticket, attachment) }
                guard let account = await deps.account(id: ticket.accountId), let a = await deps.services.sync.adapter(for: account),
                      let data = await a.downloadBytes(url: attachment.url) else { return nil }
                let url = FileManager.default.temporaryDirectory.appendingPathComponent("\(attachment.id)_\(attachment.title)")
                return (try? data.write(to: url)) != nil ? url.path : nil
            })
    }

    private func load() async {
        switch ZentaoFileKinds.preview(of: attachment) {
        case .video: content = .video(videoSource())
        case .image:
            if let data = await download(), let img = NSImage(data: data) { content = .image(img) } else { content = .failed }
        case .text, .markdown:
            if let data = await download() {
                content = .text(String(decoding: data, as: UTF8.self), markdown: ZentaoFileKinds.preview(of: attachment) == .markdown)
            } else { content = .failed }
        case .none: content = .unsupported
        }
    }

    private func save() {
        guard !saving else { return }
        saving = true
        Task {
            let data = await download()
            let path = data.flatMap { ZentaoDownloads.save($0, as: attachment.title) }
            saving = false
            if let path { revealInFileManager(path) }
            toasts?.show(path != nil ? appString("savedToDownloads", "Saved to Downloads") : appString("saveFailed", "Couldn't save the file"),
                         kind: path != nil ? .success : .error)
        }
    }

    private func toggleExpanded() { expanded.toggle(); AppWindowFullScreen.toggle() }

    var body: some View {
        let c = theme.colors
        AdaptiveViewerFrame(expanded: expanded) {
            VStack(spacing: 0) {
                HStack(spacing: theme.spacing.s8) {
                    Text(attachment.title).font(theme.typography.bodyStrong).foregroundStyle(c.tx).lineLimit(1)
                    if let size = formatFileSize(attachment.size) { Text(size).font(theme.typography.caption).foregroundStyle(c.tx3) }
                    Spacer()
                    if saving { ProgressView().controlSize(.small) }
                    AppIconButton("square.and.arrow.down", help: appString("save", "Save"), action: save)
                    if !expanded { ViewerSizeButtons() }
                    AppIconButton("xmark", help: appString("close", "Close"), action: onClose)
                }
                .padding(theme.spacing.s12)
                .overlay(alignment: .bottom) { Rectangle().fill(c.line).frame(height: theme.borders.hairline) }
                ZentaoAttachmentBody(content: content, attachment: attachment, expanded: expanded, onToggleExpand: toggleExpanded, onSave: save)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .task { await load() }
        .onExitCommand { if expanded { toggleExpanded() } else { onClose() } }
        .onDisappear { if expanded { AppWindowFullScreen.exit() } }
    }
}

/// Builds the asset a player streams a ZenTao attachment from: the session rides in the request headers.
enum ZentaoMedia {
    static func asset(_ request: MediaRequest) -> AVURLAsset { AppVideoPlayerModel.asset(request) }
}

private struct ZentaoAttachmentBody: View {
    @Environment(\.appTheme) private var theme
    let content: ZentaoAttachmentContent; let attachment: TicketAttachment
    let expanded: Bool; let onToggleExpand: () -> Void; let onSave: () -> Void

    var body: some View {
        let c = theme.colors
        switch content {
        case .loading: ProgressView()
        case .video(let source): AppVideoPlayerView(source: source, expanded: expanded, onToggleExpand: onToggleExpand).id(attachment.id)
        case .image(let img): ZoomableImage(image: img, minScale: 1, maxScale: 5, inset: theme.spacing.s12)
        case .text(let text, let markdown):
            ScrollView {
                Group {
                    if markdown { MarkdownText(text, fontSize: 14) }
                    else { Text(text).font(theme.typography.mono).foregroundStyle(c.tx) }
                }
                .textSelection(.enabled).padding(theme.spacing.s16).frame(maxWidth: .infinity, alignment: .leading)
            }
        case .failed, .unsupported:
            VStack(spacing: theme.spacing.s8) {
                Text(content.isFailed ? appString("docsPreviewFailed", "Couldn't load the file") : appString("previewUnavailable", "Preview isn't available for this file type"))
                    .font(theme.typography.body).foregroundStyle(content.isFailed ? c.red : c.tx2)
                AppButton(appString("save", "Save"), systemImage: "square.and.arrow.down", kind: .primary, action: onSave)
            }
        }
    }
}

private extension ZentaoAttachmentContent {
    var isFailed: Bool { if case .failed = self { true } else { false } }
}
