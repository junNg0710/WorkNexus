import CoreDomain
import Foundation

/// Saved copies of attachments ("Save as…", "Show in folder").
/// Ported from: lib/features/chat/data/repositories/chat_saved_copies.dart
struct ChatSavedCopies: Sendable {
    let local: ChatLocalDatasource
    let attachments: ChatAttachmentLoader
    let now: @Sendable () -> Date

    func saveTo(_ accountId: String, _ session: ChatSession?, _ content: MessageContent, _ targetPath: String) async -> Outcome<Void> {
        let source: String
        switch await attachments.localFile(accountId, session, content) { case .success(let p): source = p; case .failure(let f): return .failure(f) }
        do {
            if FileManager.default.fileExists(atPath: targetPath) { try FileManager.default.removeItem(atPath: targetPath) }
            try FileManager.default.copyItem(atPath: source, toPath: targetPath)
        } catch { return .failure(.storage("Could not save the file: \(error.localizedDescription)")) }
        let id = ChatAttachmentLoader.fileOf(content).id
        // Saved all the same; "Show in folder" just falls back to the cache.
        if id > 0 { try? await local.saveSavedFilePath(accountId, id, targetPath, at: now()) }
        return .success(())
    }

    func find(_ accountId: String, _ content: MessageContent) async -> String? {
        let id = ChatAttachmentLoader.fileOf(content).id
        guard id > 0, let path = try? await local.savedFilePath(accountId, id), FileManager.default.fileExists(atPath: path) else { return nil }
        return path
    }
}

/// Disk usage of the attachment cache per chat, and clearing it.
/// Ported from: lib/features/chat/data/repositories/chat_cache_manager.dart
struct ChatCacheManager: Sendable {
    let local: ChatLocalDatasource
    let files: ChatFileCache
    let attachments: ChatAttachmentLoader

    func setLimit(_ bytes: Int) { files.maxBytes = bytes }

    func usage() async -> Outcome<ChatCacheUsage> {
        do {
            var chats: [ChatCacheChatUsage] = []
            for accountId in try await local.chatAccountIds() {
                let sizes = files.sizes(accountId)
                if sizes.isEmpty { continue }
                var perChat: [String: [ChatMediaKind: Int]] = [:]
                for (name, owner) in try await owners(accountId) {
                    guard let size = sizes[name] else { continue }
                    perChat[owner.cgid, default: [:]][owner.kind, default: 0] += size
                }
                for (cgid, kinds) in perChat {
                    chats.append(ChatCacheChatUsage(accountId: accountId, chatGid: cgid, bytes: kinds.values.reduce(0, +), imageBytes: kinds[.image] ?? 0,
                                                    videoBytes: kinds[.video] ?? 0, fileBytes: kinds[.file] ?? 0))
                }
            }
            chats.sort { $0.bytes > $1.bytes }
            return .success(ChatCacheUsage(totalBytes: files.totalBytes(), limitBytes: files.maxBytes, chats: chats))
        } catch { return .failure(.storage("Could not measure the chat cache: \(error.localizedDescription)")) }
    }

    func clear(accountId: String?, chatGid: String?) async -> Outcome<Void> {
        guard let accountId, let chatGid else { files.clear(); attachments.clearMemory(); return .success(()) }
        do {
            let names = try await owners(accountId).filter { $0.value.cgid == chatGid }.map(\.key)
            files.delete(accountId, names)
            attachments.clearMemory(accountId: accountId)
            return .success(())
        } catch { return .failure(.storage("Could not clear the chat cache: \(error.localizedDescription)")) }
    }

    private func owners(_ accountId: String) async throws -> [String: (cgid: String, kind: ChatMediaKind)] {
        let parse = ParseMessageContent()
        var out: [String: (cgid: String, kind: ChatMediaKind)] = [:]
        for m in try await local.attachmentMessages(accountId) {
            let content = parse(m.contentType, m.content)
            guard let kind = chatMediaKind(of: content) else { continue }
            for name in ChatAttachmentLoader.diskNamesOf(content) { out[name] = (m.cgid, kind) }
        }
        return out
    }
}

/// Group and own avatars: pictures go through ZenTao web (`im-authorize`), then xxd is told.
/// Ported from: lib/features/chat/data/repositories/chat_avatar_service.dart
struct ChatAvatarService: Sendable {
    let http: any XxdHttpClient
    var backend = XxdBackend()
    typealias RequestAndStore = @Sendable (ChatSession, XxdRequest) async -> Outcome<Void>

    func setGroupAvatar(_ session: ChatSession?, _ chatGid: String, send: RequestAndStore, text: String?, color: String?, image: Data?) async -> Outcome<Void> {
        guard let session else { return .failure(.network("Chat is offline")) }
        let avatar: JSONValue
        if let image {
            let uri: URL
            switch await authorize(session, module: "file", method: "uploadChatAvatar") { case .success(let u): uri = u; case .failure(let f): return .failure(f) }
            switch await backend.uploadChatAvatar(uri, image: image, pinnedFingerprint: session.connection.credentials.pinnedFingerprint) {
            case .success(let id): avatar = ["type": "image", "data": ["imgId": .string(id)]]
            case .failure(let f): return .failure(f)
            }
        } else {
            avatar = ["type": "text", "data": ["bgColor": .string(color ?? ""), "customText": .string(text ?? "")]]
        }
        return await send(session, XxdRequest("chatsetavatar", params: [.string(chatGid), avatar]))
    }

    func setMyAvatar(_ session: ChatSession?, _ image: Data, crop: ChatAvatarCrop?) async -> Outcome<Void> {
        guard let session else { return .failure(.network("Chat is offline")) }
        let square: (png: Data, side: Int)
        switch ChatMedia.squareAvatarPng(image, crop: crop) { case .success(let s): square = s; case .failure(let f): return .failure(f) }
        let pin = session.connection.credentials.pinnedFingerprint
        let upload: URL
        switch await authorize(session, module: "my", method: "uploadAvatar") { case .success(let u): upload = u; case .failure(let f): return .failure(f) }
        let fileId: String
        switch await backend.uploadUserAvatar(upload, png: square.png, pinnedFingerprint: pin) { case .success(let id): fileId = id; case .failure(let f): return .failure(f) }
        // A fresh token for the second call, as for every `im-authorize`.
        let cropCall: URL
        switch await authorize(session, module: "user", method: "cropAvatar", params: [("imageID", fileId)]) { case .success(let u): cropCall = u; case .failure(let f): return .failure(f) }
        return await backend.cropUserAvatar(cropCall, size: square.side, pinnedFingerprint: pin)
    }

    private func authorize(_ session: ChatSession, module: String, method: String, params: [(String, String)] = []) async -> Outcome<URL> {
        let c = session.connection.credentials
        switch await http.fetchServerInfo(c) {
        case .failure(let f): return .failure(f)
        case .success(let info):
            guard let url = XxdBackend.authorizeURL(info, account: c.account, module: module, method: method, params: params) else {
                return .failure(.unexpected("ZenTao web is not configured"))
            }
            return .success(url)
        }
    }
}
