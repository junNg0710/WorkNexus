/// Ported from: lib/features/chat/presentation/widgets/{chat_text_send,chat_file_send}.dart + chat_composer.dart (`_sendLargeEmoji`)
import CoreDomain
import Foundation

/// Sends from the open conversation through the Domain use cases. Everything answers the reply draft (cleared when sent), else
/// the thread root. Shared by the composer, the emoji/sticker panels and the code dialog.
@MainActor
struct ChatMessageSender {
    let state: ChatThreadState
    let chat: ChatRepository
    var stickers: StickerRepository?
    var markdown = false
    var threadRootId: Int?

    init(state: ChatThreadState, services: ChatServices, settings: ChatSettings, threadRootId: Int? = nil) {
        self.state = state; chat = services.chat; stickers = services.stickers
        markdown = settings.sendMarkdown; self.threadRootId = threadRootId
    }

    /// What the next send replies to: the picked message, else the thread root.
    var replyToId: Int? { state.replyDraft?.serverId ?? threadRootId }

    /// Takes the reply target and clears the draft, as a send leaves the input - and says a message is on its way.
    private func takeReply() -> Int? {
        let id = replyToId
        state.replyDraft = nil
        state.noteSent(inThread: threadRootId != nil)
        return id
    }

    func text(_ text: String) async -> Outcome<Void> {
        let reply = takeReply()
        return await SendTextMessage(chat)(accountId: state.accountId, chatGid: state.chatGid, text: text, replyToId: reply, markdown: markdown)
    }

    /// Sends `emoji` shown large, as the official client does. A large emoji cannot answer a message, so while replying (or in a
    /// thread) it goes as text with the reply instead.
    func largeEmoji(_ emoji: String) async -> Outcome<Void> {
        if replyToId != nil { return await text(emoji) }
        state.noteSent(inThread: false)
        return await SendLargeEmoji(chat)(accountId: state.accountId, chatGid: state.chatGid, emoji: emoji)
    }

    /// Sends the composer's text; a lone emoji goes large.
    func composed(message: String, plain: String?) async -> Outcome<Void> {
        if let plain, IsSingleEmoji()(plain) { return await largeEmoji(plain.trimmingCharacters(in: .whitespacesAndNewlines)) }
        return await text(message)
    }

    /// Sends each file in order; every file is tried, the first failure is reported.
    func files(_ files: [StagedFile]) async -> Outcome<Void> {
        let reply = takeReply()
        var first: Failure?
        for f in files {
            let r = await SendChatFile(chat)(accountId: state.accountId, chatGid: state.chatGid, name: f.name, bytes: f.data, mimeType: f.mimeType, replyToId: reply)
            if case .failure(let e) = r { first = first ?? e }
        }
        return first.map { .failure($0) } ?? .success(())
    }

    func sticker(_ sticker: ChatSticker) async -> Outcome<Void> {
        guard let stickers else { return .failure(.unexpected("Stickers are not available")) }
        let reply = takeReply()
        return await SendSticker(chat, stickers)(accountId: state.accountId, chatGid: state.chatGid, sticker: sticker, replyToId: reply)
    }

    func code(_ code: String, language: String, name: String?) async -> Outcome<Void> {
        let reply = takeReply()
        return await SendCodeMessage(chat)(accountId: state.accountId, chatGid: state.chatGid, code: code, language: language, name: name, replyToId: reply)
    }
}

/// Staging helpers shared by paste, drop and the file picker.
enum ChatStaging {
    /// `MIME type` from a file name's extension.
    static func mimeType(forName name: String) -> String? {
        let ext = (name as NSString).pathExtension.lowercased()
        let map = ["png": "image/png", "jpg": "image/jpeg", "jpeg": "image/jpeg", "gif": "image/gif", "webp": "image/webp",
                   "heic": "image/heic", "bmp": "image/bmp", "mp4": "video/mp4", "mov": "video/quicktime", "m4v": "video/x-m4v",
                   "webm": "video/webm", "pdf": "application/pdf", "txt": "text/plain", "json": "application/json", "zip": "application/zip"]
        return map[ext]
    }

    static func isImageName(_ name: String) -> Bool { mimeType(forName: name)?.hasPrefix("image/") ?? false }

    /// A `StagedFile` read from `url` (nil when it is not a readable regular file).
    static func staged(from url: URL) -> StagedFile? {
        var isDir: ObjCBool = false
        guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isDir), !isDir.boolValue,
              let data = try? Data(contentsOf: url) else { return nil }
        return StagedFile(name: url.lastPathComponent, data: data, mimeType: mimeType(forName: url.lastPathComponent))
    }
}
