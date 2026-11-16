import AppKit
import CoreDomain
import Foundation

/// Opening and saving the attachments listed in the files panels.
/// Ported from: lib/features/chat/presentation/widgets/attachment_download.dart
extension ChatShellModel {
    /// Downloads (when needed) and opens an attachment in its default app.
    func open(attachment content: MessageContent) async {
        guard !downloading.contains(content) else { return }
        downloading.insert(content); defer { downloading.remove(content) }
        switch await OpenChatAttachment(repository)(accountId: accountId, content: content) {
        case .success(let path): openURL(URL(fileURLWithPath: path))
        case .failure(let f): report(f)
        }
    }

    /// Asks where to save an attachment and copies it there.
    func save(attachment content: MessageContent, name: String) async {
        let panel = NSSavePanel()
        panel.nameFieldStringValue = name
        guard panel.runModal() == .OK, let url = panel.url else { return }
        if case .failure(let f) = await repository.saveAttachmentCopy(accountId: accountId, content: content, targetPath: url.path) { report(f) }
    }

    /// Asks for an image on disk; nil when cancelled or unreadable.
    func pickImageData() -> Data? {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.image]; panel.allowsMultipleSelection = false
        guard panel.runModal() == .OK, let url = panel.url else { return nil }
        return try? Data(contentsOf: url)
    }

    /// Makes the `crop` square of `image` your avatar (nil: the centre square).
    func setMyAvatar(_ image: Data, crop: ChatAvatarCrop? = nil) async -> Outcome<Void> {
        await repository.setMyAvatar(accountId: accountId, image: image, crop: crop)
    }
}
