import CoreDomain
import Foundation

/// Sending: optimistic pending row, (upload,) `messagesend`, echo ingest; retry, retract, forward, cancel upload.
/// Ported from: lib/features/chat/data/repositories/chat_sender.dart
final class ChatSender: @unchecked Sendable {
    typealias Ingest = @Sendable (String, ChatSession, XxdResponse) async -> Void

    private struct Pending { var name: String; var bytes: Data; var mimeType: String? }
    private let local: ChatLocalDatasource
    private let attachments: ChatAttachmentLoader
    private let session: @Sendable (String) -> ChatSession?
    private let ingest: Ingest
    private let now: @Sendable () -> Date
    private let pendingUploads = Locked<[String: Pending]>([:])
    private let uploadCancels = Locked<[String: ChatCancelToken]>([:])
    private let progress = Broadcast<(gid: String, sent: Double)>()

    init(local: ChatLocalDatasource, attachments: ChatAttachmentLoader, session: @escaping @Sendable (String) -> ChatSession?,
         ingest: @escaping Ingest, now: @escaping @Sendable () -> Date) {
        self.local = local; self.attachments = attachments; self.session = session; self.ingest = ingest; self.now = now
    }

    func pendingBytes(_ gid: String) -> Data? { pendingUploads.current[gid]?.bytes }

    func watchUploadProgress(_ gid: String) -> AsyncStream<Double> {
        let source = progress.stream()
        return AsyncStream { cont in
            let task = Task { for await p in source where p.gid == gid { cont.yield(p.sent) }; cont.finish() }
            cont.onTermination = { _ in task.cancel() }
        }
    }

    // MARK: text-like messages

    func sendText(_ accountId: String, _ chatGid: String, _ text: String, replyToId: Int?, markdown: Bool) async -> Outcome<Void> {
        await sendInline(accountId, chatGid, contentType: markdown ? "text" : "plain", content: text, replyToId: replyToId)
    }

    func sendEmoji(_ accountId: String, _ chatGid: String, _ code: String, replyToId: Int?) async -> Outcome<Void> {
        await sendInline(accountId, chatGid, contentType: "image",
                         content: JSONValue.object(JSONObject([("type", "emoji"), ("content", .string(code))])).serialized(), replyToId: replyToId)
    }

    func sendCode(_ accountId: String, _ chatGid: String, code: String, language: String, name: String?, replyToId: Int?) async -> Outcome<Void> {
        await sendInline(accountId, chatGid, contentType: "code",
                         content: JSONValue.object(JSONObject([("lang", .string(language)), ("code", .string(code)), ("name", .string(name ?? ""))])).serialized(),
                         replyToId: replyToId)
    }

    func forward(_ accountId: String, _ messageGid: String, _ toChatGid: String) async -> Outcome<Void> {
        guard let row = try? await local.message(accountId, messageGid) else { return .failure(.notFound("No such message")) }
        return await sendInline(accountId, toChatGid, contentType: row.contentType, content: row.content, replyToId: nil)
    }

    private func sendInline(_ accountId: String, _ chatGid: String, contentType: String, content: String, replyToId: Int?) async -> Outcome<Void> {
        let gid = UUID().uuidString.lowercased()
        do { try await local.insertMessage(pendingRow(accountId, gid, chatGid, contentType, content, replyToId)) }
        catch { return .failure(.storage("Could not queue the message: \(error.localizedDescription)")) }
        return await deliver(accountId, gid)
    }

    private func pendingRow(_ accountId: String, _ gid: String, _ chatGid: String, _ type: String, _ content: String, _ replyTo: Int?) async -> ColumnValues {
        var v = ColumnValues()
        v.set("accountId", accountId); v.set("gid", gid); v.set("cgid", chatGid); v.set("senderId", await selfId(accountId))
        v.set("sentAt", now()); v.set("contentType", type); v.set("content", content)
        v.set("sendState", SendState.pending.rawValue); v.set("replyToId", replyTo)
        return v
    }

    // MARK: files

    func sendFile(_ accountId: String, _ chatGid: String, name: String, bytes: Data, mimeType: String?, replyToId: Int?) async -> Outcome<Void> {
        let gid = UUID().uuidString.lowercased()
        let mime = mimeType ?? ChatMedia.mimeType(forFileName: name)
        let isImage = ChatMedia.isImageMime(mime)
        // Placeholder until the upload returns the stored file's id; an image's size already shapes its bubble.
        var o = JSONObject([("name", .string(name)), ("size", .int(bytes.count))])
        if isImage, let d = ChatMedia.imageSize(bytes) { o["width"] = .int(d.width); o["height"] = .int(d.height) }
        do { try await local.insertMessage(pendingRow(accountId, gid, chatGid, isImage ? "image" : "file", JSONValue.object(o).serialized(), replyToId)) }
        catch { return .failure(.storage("Could not queue the file: \(error.localizedDescription)")) }
        pendingUploads.with { $0[gid] = Pending(name: name, bytes: bytes, mimeType: mime) }
        return await uploadAndDeliver(accountId, chatGid, gid)
    }

    private func uploadAndDeliver(_ accountId: String, _ chatGid: String, _ gid: String) async -> Outcome<Void> {
        guard let file = pendingUploads.current[gid] else { return await deliver(accountId, gid) }
        let cancel = ChatCancelToken()
        uploadCancels.with { $0[gid] = cancel }
        let hub = progress
        let uploaded = await attachments.upload(accountId, session(accountId), chatGid: chatGid, name: file.name, bytes: file.bytes, mimeType: file.mimeType,
                                                onProgress: { hub.send((gid, $0)) }, cancel: cancel)
        uploadCancels.with { $0[gid] = nil }
        // Cancelled as the upload finished: the message is already gone.
        if cancel.isCancelled { return .success(()) }
        switch uploaded {
        case .success(let v):
            pendingUploads.with { $0[gid] = nil }
            try? await local.setContent(accountId, gid, contentType: v.contentType, content: v.content)
            return await deliver(accountId, gid)
        case .failure(.cancelled): return .success(())   // `cancelUpload` already removed the message
        case .failure(let f):
            try? await local.setSendState(accountId, gid, .failed)
            return .failure(f)
        }
    }

    func cancelUpload(_ accountId: String, _ gid: String) async -> Outcome<Void> {
        let inFlight = uploadCancels.with { $0.removeValue(forKey: gid) }
        guard inFlight != nil || pendingUploads.current[gid] != nil else { return .failure(.notFound("Nothing is uploading")) }
        inFlight?.cancel()
        pendingUploads.with { $0[gid] = nil }
        do { try await local.deleteMessage(accountId, gid); return .success(()) }
        catch { return .failure(.storage("Could not remove the message: \(error.localizedDescription)")) }
    }

    // MARK: retract / retry / deliver

    func retract(_ accountId: String, _ messageGid: String) async -> Outcome<Void> {
        let session = session(accountId)
        guard let row = try? await local.message(accountId, messageGid) else { return .failure(.notFound("No such message")) }
        guard let session, await session.isOnline() else { return .failure(.network("Chat is offline")) }
        let msg = Self.wire(row, user: row.senderId, deleted: true)
        switch await session.connection.request(XxdRequest("messageretract", params: [.array([msg])])) {
        case .success(let reply): await session.enqueue { [ingest] in await ingest(accountId, session, reply) }; return .success(())
        case .failure(let f): return .failure(f)
        }
    }

    func retrySend(_ accountId: String, _ messageGid: String) async -> Outcome<Void> {
        guard let row = try? await local.message(accountId, messageGid), row.sendState == SendState.failed.rawValue else {
            return .failure(.notFound("No failed message to retry"))
        }
        try? await local.setSendState(accountId, messageGid, .pending)
        return await uploadAndDeliver(accountId, row.cgid, messageGid)
    }

    private func deliver(_ accountId: String, _ gid: String) async -> Outcome<Void> {
        let session = session(accountId)
        let row = try? await local.message(accountId, gid)
        guard let session, let row, let me = session.selfUserId else {
            try? await local.setSendState(accountId, gid, .failed)
            return .failure(.network("Chat is offline"))
        }
        switch await session.connection.request(XxdRequest("messagesend", params: [.array([Self.wire(row, user: me, deleted: false)])])) {
        case .success(let reply):
            // The echo is also ingested as a packet; storing it here as well makes the message "sent" even if that packet is late.
            await session.enqueue { [ingest] in await ingest(accountId, session, reply) }
            try? await local.setSendState(accountId, gid, .sent)
            return .success(())
        case .failure(let f):
            try? await local.setSendState(accountId, gid, .failed)
            return .failure(f)
        }
    }

    private static func wire(_ row: ChatMessageRow, user: Int, deleted: Bool) -> JSONValue {
        .object(JSONObject([("gid", .string(row.gid)), ("cgid", .string(row.cgid)), ("type", "normal"),
                            ("contentType", .string(row.contentType)), ("content", .string(row.content)), ("user", .int(user)),
                            ("data", .string(ChatMappers.messageData(replyToId: row.replyToId))), ("deleted", .bool(deleted))]))
    }

    private func selfId(_ accountId: String) async -> Int {
        if let s = session(accountId)?.selfUserId { return s }
        return ((try? await local.chatAccount(accountId))?.userId) ?? 0
    }
}
