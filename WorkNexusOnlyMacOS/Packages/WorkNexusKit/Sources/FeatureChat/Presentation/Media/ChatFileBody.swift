/// Ported from: lib/features/chat/presentation/widgets/chat_file_body.dart
import AppKit
import CoreDomain
import CoreUI
import SwiftUI

/// A file message: its extension badge, name and size, with "Open file" / "Show in folder" / "Save as…". A click downloads it
/// (progress on the badge, cancel on hover) and then opens it with the default app. Own files being sent show send progress.
struct ChatFileBody: View {
    @Environment(\.appTheme) private var theme
    @Environment(\.chatServices) private var services
    let message: ChatMessage
    let file: FileContent
    @State private var cached = false
    @State private var uploadProgress: Double?
    @State private var error: String?

    private var key: TransferKey { TransferKey(accountId: message.accountId, content: .file(file)) }
    private var sending: Bool { message.sendState == .pending }

    var body: some View {
        let transfers = AttachmentTransfers.shared
        let downloading = transfers.progress(key)
        HStack(alignment: .center, spacing: theme.spacing.s12) {
            ChatFileBadge(fileName: file.name, busy: sending || downloading != nil, progress: sending ? uploadProgress : downloading,
                          onCancel: cancel, cancelHelp: sending ? appString("chatCancelUpload", "Cancel sending") : appString("chatCancelDownload", "Cancel download"))
            VStack(alignment: .leading, spacing: theme.spacing.s2) {
                Text(file.name).font(theme.typography.bodyStrong).foregroundStyle(theme.colors.tx).lineLimit(2).truncationMode(.middle)
                Text(statusLine(downloading)).font(theme.typography.meta).foregroundStyle(theme.colors.tx3)
                if message.sendState == .sent, downloading == nil {
                    HStack(spacing: theme.spacing.s4) {
                        ChatFileActionButton(title: appString("chatOpenFile", "Open file"), systemImage: "arrow.up.forward.app", action: open)
                        ChatFileActionButton(title: appString("chatShowInFolder", "Show in folder"), systemImage: "folder", action: reveal)
                        ChatFileActionButton(title: appString("chatSaveAs", "Save as…"), systemImage: "square.and.arrow.down", action: saveAs)
                    }
                }
                if message.sendState == .failed { ChatUploadOverlay(message: message) }
                if let error { Text(error).font(theme.typography.caption).foregroundStyle(theme.colors.red).lineLimit(2) }
            }
        }
        .padding(.vertical, theme.spacing.s2)
        .frame(minWidth: 220, alignment: .leading)
        .task(id: downloading == nil) { if let repo = services?.chat { cached = await transfers.isCached(key, repo) } }
        .task(id: sending) {
            guard sending, let repo = services?.chat else { return }
            for await p in repo.watchUploadProgress(messageGid: message.gid) { uploadProgress = p }
        }
    }

    private func statusLine(_ downloading: Double?) -> String {
        let size = AttachmentActions.byteCount(file.size)
        if sending { return "\(appString("chatUploading", "Uploading…")) · \(size)" }
        if let downloading { return "\(appString("chatDownloading", "Downloading…")) \(Int(downloading * 100))% · \(size)" }
        return "\(size) · \(cached ? appString("chatFileOnDevice", "On this device") : appString("chatFileOnCloud", "Available on Cloud"))"
    }

    private func cancel() {
        guard let repo = services?.chat else { return }
        if sending { Task { _ = await repo.cancelUpload(accountId: message.accountId, messageGid: message.gid) } }
        else { AttachmentTransfers.shared.cancel(key, repo) }
    }

    private func report(_ r: Outcome<Void>?) { if case .failure(let f)? = r, !isCancelled(f) { error = f.message } }

    private func open() {
        guard let repo = services?.chat else { return }
        error = nil
        Task {
            switch await AttachmentTransfers.shared.download(key, repo) {
            case .success(let path)?: NSWorkspace.shared.open(URL(fileURLWithPath: path))
            case .failure(let f)? where !isCancelled(f): error = f.message
            default: break
            }
        }
    }

    private func reveal() {
        guard let repo = services?.chat else { return }
        error = nil
        Task { report(await AttachmentActions.reveal(key, repo)) }
    }

    private func saveAs() {
        guard let repo = services?.chat else { return }
        error = nil
        Task {
            // Downloaded first, so the copy comes from the file on this device.
            if case .failure(let f)? = await AttachmentTransfers.shared.download(key, repo), !isCancelled(f) { error = f.message; return }
            report(await AttachmentActions.saveAs(key, name: file.name, repo))
        }
    }
}
