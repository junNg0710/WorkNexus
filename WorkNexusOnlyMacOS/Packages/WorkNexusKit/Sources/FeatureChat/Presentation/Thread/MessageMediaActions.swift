/// Not in the Flutter app.
import AppKit
import CoreDomain
import CoreUI
import SwiftUI

extension ThreadContext {
    /// What a picture, a video or a file adds to its message's menu: download it (a copy in the Downloads folder), save it
    /// somewhere else, show it in Finder, open it with its app - and, for a picture, copy it. Each one fetches the file
    /// first when it is not on this device yet (the message shows the progress). Not for a sticker, nor for a file that
    /// is not on the server yet.
    func mediaActions(for message: ChatMessage) -> [MessageAction] {
        guard !message.deleted, message.sendState == .sent else { return [] }
        let content = message.content
        let name: String, picture: Bool
        switch content {
        case .image(let image) where image.fileId > 0 && !IsStickerImage()(image): name = image.name; picture = true
        case .file(let file) where file.fileId > 0: name = file.name; picture = false
        default: return []
        }
        let key = TransferKey(accountId: message.accountId, content: content)
        let repo = services.chat, report = model.report, notify = model.notify
        /// Runs `work`, telling the reader when it failed (a download they cancelled is not a failure).
        func run(_ work: @escaping @MainActor () async -> Outcome<Void>?) -> () -> Void {
            { Task { @MainActor in if case .failure(let f)? = await work(), !isCancelled(f) { report(f.message) } } }
        }
        /// Fetches the file, then hands its path on.
        func withFile(_ then: @escaping @MainActor (String) -> Void) -> () -> Void {
            run {
                switch await AttachmentTransfers.shared.download(key, repo) {
                case .success(let path)?: then(path); return .success(())
                case .failure(let f)?: return .failure(f)
                case nil: return nil
                }
            }
        }
        var out = [
            MessageAction(id: "download", icon: "arrow.down.circle", title: L.download, sectionStart: true, run: run {
                switch await AttachmentActions.saveToDownloads(key, name: name, repo) {
                case .success?: notify(L.savedToDownloads); return .success(())
                case .failure(let f)?: return .failure(f)
                case nil: return nil
                }
            }),
            MessageAction(id: "saveAs", icon: "square.and.arrow.down", title: L.saveAs, run: run {
                // Fetched first, so the copy comes from the file on this device.
                if case .failure(let f)? = await AttachmentTransfers.shared.download(key, repo) { return .failure(f) }
                return await AttachmentActions.saveAs(key, name: name, repo)
            }),
            MessageAction(id: "showInFolder", icon: "folder", title: L.showInFolder, run: run { await AttachmentActions.reveal(key, repo) }),
            MessageAction(id: "openFile", icon: "arrow.up.forward.app", title: L.openFile, run: withFile { NSWorkspace.shared.open(URL(fileURLWithPath: $0)) }),
        ]
        if picture {
            out.append(MessageAction(id: "copyImage", icon: "photo.on.rectangle", title: L.copyImage, run: withFile { path in
                guard let data = try? Data(contentsOf: URL(fileURLWithPath: path)) else { return }
                copyImageToClipboard(data)
                notify(L.copied)
            }))
        }
        return out
    }
}
