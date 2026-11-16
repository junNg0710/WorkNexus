import CoreDomain
import Foundation

/// Downloads, caches (memory LRU for images + disk) and uploads chat attachments.
/// Ported from: lib/features/chat/data/repositories/chat_attachment_loader.dart
final class ChatAttachmentLoader: @unchecked Sendable {
    private struct Progress: Sendable { var key: String; var done: Double }
    private struct Memory { var items: [(key: String, bytes: Data)] = []; var total = 0 }

    private let http: any XxdHttpClient
    private let files: ChatFileCache
    private let maxCacheBytes: Int
    private let memory = Locked(Memory())
    private let inflight = Locked<[String: Task<Outcome<Data>, Never>]>([:])
    private let cancels = Locked<[String: ChatCancelToken]>([:])
    private let progress = Broadcast<Progress>()

    init(http: any XxdHttpClient, files: ChatFileCache, maxCacheBytes: Int = 64 * 1024 * 1024) {
        self.http = http; self.files = files; self.maxCacheBytes = maxCacheBytes
    }

    func cancel(_ accountId: String, _ content: MessageContent) {
        guard let key = Self.key(accountId, content) else { return }
        cancels.current[key]?.cancel()
    }

    func watchProgress(_ accountId: String, _ content: MessageContent) -> AsyncStream<Double> {
        guard let key = Self.key(accountId, content) else { return AsyncStream { $0.finish() } }
        let source = progress.stream()
        return AsyncStream { cont in
            let task = Task { for await p in source where p.key == key { cont.yield(p.done) }; cont.finish() }
            cont.onTermination = { _ in task.cancel() }
        }
    }

    func isCached(_ accountId: String, _ content: MessageContent) -> Bool {
        if case .image(let i) = content, i.inlineBase64 != nil { return true }
        guard let key = Self.key(accountId, content) else { return false }
        if memory.current.items.contains(where: { $0.key == key }) { return true }
        let (id, name, _) = Self.fileOf(content)
        return files.open(accountId, Self.diskName(id, name)) != nil
    }

    /// The bytes of an attachment (or its `thumb_` preview): memory, then disk, then the server.
    func load(_ accountId: String, _ session: ChatSession?, _ content: MessageContent, thumbnail: Bool = false) async -> Outcome<Data> {
        if case .image(let i) = content, let b64 = i.inlineBase64 {
            guard let d = Data(base64Encoded: b64, options: .ignoreUnknownCharacters) else { return .failure(.parse("Broken inline image")) }
            return .success(d)
        }
        let (fileId, name, time) = Self.fileOf(content)
        guard fileId > 0, !name.isEmpty else { return .failure(.notFound("This message has no attachment")) }
        // Only images the server made a preview for have a `thumb_` file.
        let isImage: Bool, hasThumb: Bool
        if case .image(let i) = content { isImage = true; hasThumb = i.hasThumb } else { isImage = false; hasThumb = false }
        let thumb = thumbnail && isImage && hasThumb
        let disk = Self.diskName(fileId, name, thumbnail: thumb)
        let key = "\(accountId)/\(disk)"
        if let hit = recall(key) { return .success(hit) }
        if let onDisk = files.read(accountId, disk) {
            // Only images are worth keeping in memory: a video or a file is read once and would push the images out.
            if isImage { remember(key, onDisk) }
            return .success(onDisk)
        }
        guard let session, let xxd = await session.onlineSession(), let sessionId = xxd.sessionId else { return .failure(.network("Chat is offline")) }
        let expected: Int? = {
            switch content {
            case .image(let i): return thumb || i.size <= 0 ? nil : i.size
            case .file(let f): return f.size <= 0 ? nil : f.size
            default: return nil
            }
        }()
        if let running = inflight.current[key] { return await running.value }
        let task = Task { [self] in
            await download(accountId, session, xxd, sessionId, key: key, disk: disk, fileId: fileId, name: name, time: time,
                           thumb: thumb, expected: expected, image: isImage)
        }
        inflight.with { $0[key] = task }
        let result = await task.value
        inflight.with { $0[key] = nil }
        cancels.with { $0[key] = nil }
        return result
    }

    private func download(_ accountId: String, _ session: ChatSession, _ xxd: XxdSession, _ sessionId: String, key: String, disk: String,
                          fileId: Int, name: String, time: Int, thumb: Bool, expected: Int?, image: Bool) async -> Outcome<Data> {
        let c = session.connection.credentials
        let token = ChatCancelToken()
        cancels.with { $0[key] = token }
        let url = http.fileDownloadURL(server: c.server, userId: xxd.userId, sessionId: sessionId, fileId: fileId, fileName: name,
                                       fileTime: time, serverName: c.serverName, thumbnail: thumb, preview: false)
        let hub = progress
        let result = await http.download(url, pinnedFingerprint: c.pinnedFingerprint, onProgress: { received, total in
            if let all = total ?? expected, all > 0 { hub.send(Progress(key: key, done: min(1, max(0, Double(received) / Double(all))))) }
        }, cancel: token)
        if case .success(let bytes) = result {
            if image { remember(key, bytes) }
            files.write(accountId, disk, bytes)
        }
        return result
    }

    /// How to play a video: the cached file when it is on this device; otherwise a ranged source from the server, playable
    /// while it arrives (the Dart client streamed through a local proxy). Without a known size or a chat session it falls back
    /// to downloading the whole file first.
    func videoPlayback(_ accountId: String, _ session: ChatSession?, _ content: MessageContent) async -> Outcome<ChatVideoPlayback> {
        guard case .file(let file) = content else { return .failure(.notFound("This message has no video")) }
        let disk = Self.diskName(file.fileId, file.name)
        if file.fileId > 0, let cached = files.open(accountId, disk) { return .success(.file(cached)) }
        if file.size > 0, file.fileId > 0, !file.name.isEmpty, let session, let xxd = await session.onlineSession(), let sessionId = xxd.sessionId {
            let c = session.connection.credentials
            let url = http.fileDownloadURL(server: c.server, userId: xxd.userId, sessionId: sessionId, fileId: file.fileId, fileName: file.name,
                                           fileTime: file.time, serverName: c.serverName, thumbnail: false, preview: false)
            let cache = files
            return .success(.stream(UpstreamVideoSource(url: url, pin: c.pinnedFingerprint, fileName: file.name, length: Int64(file.size),
                                                        mimeType: file.mimeType) { temp in cache.adopt(accountId, disk, moving: temp) }))
        }
        switch await localFile(accountId, session, content) {
        case .success(let path): return .success(.file(URL(fileURLWithPath: path)))
        case .failure(let f): return .failure(f)
        }
    }

    func cachedPath(_ accountId: String, _ content: MessageContent) -> String? {
        let (id, name, _) = Self.fileOf(content)
        return id > 0 ? files.fileURL(accountId, Self.diskName(id, name)).path : nil
    }

    func localFile(_ accountId: String, _ session: ChatSession?, _ content: MessageContent) async -> Outcome<String> {
        let (id, name, _) = Self.fileOf(content)
        let disk = Self.diskName(id, name)
        if id > 0, let cached = files.open(accountId, disk) { return .success(cached.path) }
        if case .failure(let f) = await load(accountId, session, content) { return .failure(f) }
        guard let file = files.open(accountId, disk) else { return .failure(.storage("Could not save the attachment")) }
        return .success(file.path)
    }

    /// Uploads `bytes` and returns the message content (type + JSON) that carries the stored file.
    func upload(_ accountId: String, _ session: ChatSession?, chatGid: String, name: String, bytes: Data, mimeType: String?,
                onProgress: (@Sendable (Double) -> Void)?, cancel: ChatCancelToken?) async -> Outcome<(contentType: String, content: String)> {
        guard let session, let xxd = await session.onlineSession() else { return .failure(.network("Chat is offline")) }
        if let limit = xxd.uploadFileSize, limit > 0, bytes.count > limit {
            return .failure(.unexpected("File is larger than the server allows (\(limit / (1024 * 1024)) MB)"))
        }
        let c = session.connection.credentials
        switch await http.upload(server: c.server, token: xxd.token, userId: xxd.userId, chatGid: chatGid, fileName: name, bytes: bytes,
                                 mimeType: mimeType, serverName: c.serverName, pinnedFingerprint: c.pinnedFingerprint,
                                 onProgress: onProgress, cancel: cancel) {
        case .failure(let f): return .failure(f)
        case .success(let up):
            // The sender's copy is the file: no need to download it back.
            let disk = Self.diskName(up.id, name)
            remember("\(accountId)/\(disk)", bytes)
            files.write(accountId, disk, bytes)
            let isImage = ChatMedia.isImageMime(mimeType)
            var o = JSONObject([("name", .string(name)), ("size", .int(bytes.count)), ("send", true)])
            if let mimeType { o["type"] = .string(mimeType) }
            o["id"] = .int(up.id); o["time"] = .int(up.time)
            // Lets every client reserve the image's space before it loads.
            if isImage, let d = ChatMedia.imageSize(bytes) { o["width"] = .int(d.width); o["height"] = .int(d.height) }
            return .success((isImage ? "image" : "file", JSONValue.object(o).serialized()))
        }
    }

    func clearMemory(accountId: String? = nil) {
        memory.with { m in
            m.items.removeAll { accountId == nil || $0.key.hasPrefix("\(accountId!)/") }
            m.total = m.items.reduce(0) { $0 + $1.bytes.count }
        }
    }

    /// Every on-disk name one attachment can have (file, preview, cached video frame).
    static func diskNamesOf(_ content: MessageContent) -> [String] {
        let (id, name, _) = fileOf(content)
        guard id > 0 else { return [] }
        let original = diskName(id, name)
        return [original, diskName(id, name, thumbnail: true), "\(original).thumb.png"].map(ChatFileCache.diskName)
    }

    static func fileOf(_ content: MessageContent) -> (id: Int, name: String, time: Int) {
        switch content {
        case .image(let i): (i.fileId, i.name, i.time)
        case .file(let f): (f.fileId, f.name, f.time)
        default: (0, "", 0)
        }
    }

    static func diskName(_ id: Int, _ name: String, thumbnail: Bool = false) -> String { "\(id)\(thumbnail ? "_thumb" : "")_\(name)" }

    private static func key(_ accountId: String, _ content: MessageContent) -> String? {
        let (id, name, _) = fileOf(content)
        return id <= 0 ? nil : "\(accountId)/\(diskName(id, name))"
    }

    // MARK: memory LRU

    private func recall(_ key: String) -> Data? {
        memory.with { m in
            guard let i = m.items.firstIndex(where: { $0.key == key }) else { return nil }
            let item = m.items.remove(at: i)
            m.items.append(item)
            return item.bytes
        }
    }

    private func remember(_ key: String, _ bytes: Data) {
        guard bytes.count <= maxCacheBytes else { return }
        memory.with { m in
            if let i = m.items.firstIndex(where: { $0.key == key }) { m.total -= m.items[i].bytes.count; m.items.remove(at: i) }
            m.items.append((key, bytes)); m.total += bytes.count
            while m.total > maxCacheBytes, !m.items.isEmpty { m.total -= m.items.removeFirst().bytes.count }
        }
    }
}
