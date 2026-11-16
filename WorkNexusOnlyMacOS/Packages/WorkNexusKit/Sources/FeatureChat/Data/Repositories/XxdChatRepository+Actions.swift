import AVFoundation
import CoreDomain
import CoreUI
import Foundation

/// Sending, attachments and people/group actions.
extension XxdChatRepository {
    // MARK: sending

    public func sendText(accountId: String, chatGid: String, text: String, replyToId: Int?, markdown: Bool) async -> Outcome<Void> {
        await sender.sendText(accountId, chatGid, text, replyToId: replyToId, markdown: markdown)
    }

    public func sendEmoji(accountId: String, chatGid: String, code: String, replyToId: Int?) async -> Outcome<Void> {
        await sender.sendEmoji(accountId, chatGid, code, replyToId: replyToId)
    }

    public func sendCode(accountId: String, chatGid: String, code: String, language: String, name: String?, replyToId: Int?) async -> Outcome<Void> {
        await sender.sendCode(accountId, chatGid, code: code, language: language, name: name, replyToId: replyToId)
    }

    public func sendFile(accountId: String, chatGid: String, name: String, bytes: Data, mimeType: String?, replyToId: Int?) async -> Outcome<Void> {
        await sender.sendFile(accountId, chatGid, name: name, bytes: bytes, mimeType: mimeType, replyToId: replyToId)
    }

    public func pendingUploadBytes(messageGid: String) -> Data? { sender.pendingBytes(messageGid) }
    public func watchUploadProgress(messageGid: String) -> AsyncStream<Double> { sender.watchUploadProgress(messageGid) }
    public func cancelUpload(accountId: String, messageGid: String) async -> Outcome<Void> { await sender.cancelUpload(accountId, messageGid) }
    public func retract(accountId: String, messageGid: String) async -> Outcome<Void> { await sender.retract(accountId, messageGid) }
    public func retrySend(accountId: String, messageGid: String) async -> Outcome<Void> { await sender.retrySend(accountId, messageGid) }
    public func forwardMessage(accountId: String, messageGid: String, toChatGid: String) async -> Outcome<Void> {
        await sender.forward(accountId, messageGid, toChatGid)
    }

    public func sendTyping(accountId: String, chatGid: String, typing on: Bool) async -> Outcome<Void> {
        await typing.send(session(accountId), accountId, chatGid, typing: on)
    }

    // MARK: attachments

    public func attachmentFile(accountId: String, content: MessageContent) async -> Outcome<String> {
        await attachments.localFile(accountId, session(accountId), content)
    }

    public func loadAttachment(accountId: String, content: MessageContent, thumbnail: Bool) async -> Outcome<Data> {
        await attachments.load(accountId, session(accountId), content, thumbnail: thumbnail)
    }

    public func videoPlayback(accountId: String, content: MessageContent) async -> Outcome<ChatVideoPlayback> {
        await attachments.videoPlayback(accountId, session(accountId), content)
    }

    public func saveAttachmentCopy(accountId: String, content: MessageContent, targetPath: String) async -> Outcome<Void> {
        await savedCopies.saveTo(accountId, session(accountId), content, targetPath)
    }

    public func savedAttachmentCopy(accountId: String, content: MessageContent) async -> String? { await savedCopies.find(accountId, content) }
    public func cancelDownload(accountId: String, content: MessageContent) { attachments.cancel(accountId, content) }
    public func watchDownloadProgress(accountId: String, content: MessageContent) -> AsyncStream<Double> { attachments.watchProgress(accountId, content) }
    public func isAttachmentCached(accountId: String, content: MessageContent) async -> Bool { attachments.isCached(accountId, content) }
    public func cacheUsage() async -> Outcome<ChatCacheUsage> { await cacheManager.usage() }
    public func clearCache(accountId: String?, chatGid: String?) async -> Outcome<Void> { await cacheManager.clear(accountId: accountId, chatGid: chatGid) }

    public func videoDuration(accountId: String, video: MessageContent) async -> Outcome<TimeInterval> {
        guard attachments.isCached(accountId, video), let path = attachments.cachedPath(accountId, video) else { return .failure(.notFound("Video not downloaded")) }
        let cache = URL(fileURLWithPath: path + ".duration")
        if let ms = (try? String(contentsOf: cache, encoding: .utf8)).flatMap({ Int($0.trimmingCharacters(in: .whitespacesAndNewlines)) }) { return .success(Double(ms) / 1000) }
        guard let d = try? await AVURLAsset(url: URL(fileURLWithPath: path)).load(.duration), d.seconds.isFinite, d.seconds > 0 else {
            return .failure(.notFound("Unknown video length"))
        }
        try? "\(Int(d.seconds * 1000))".write(to: cache, atomically: true, encoding: .utf8)
        return .success(d.seconds)
    }

    public func pendingVideoThumbnail(messageGid: String, fileName: String) async -> Outcome<Data> {
        guard let bytes = sender.pendingBytes(messageGid) else { return .failure(.notFound("Not uploading")) }
        // The thumbnailers read a file: the picked bytes go to a scratch copy, removed with the frame cached beside it.
        let ext = (fileName as NSString).pathExtension
        let video = FileManager.default.temporaryDirectory.appendingPathComponent("worknexus-upload-\(messageGid)" + (ext.isEmpty ? "" : ".\(ext)"))
        defer { for f in [video, URL(fileURLWithPath: video.path + ".thumb.png")] { try? FileManager.default.removeItem(at: f) } }
        do { try bytes.write(to: video) } catch { return .failure(.storage("Could not preview the video: \(error.localizedDescription)")) }
        guard let frame = await VideoThumbnailer.shared.thumbnail(of: video.path) else { return .failure(.notFound("No preview frame")) }
        return .success(frame)
    }

    public func videoThumbnail(accountId: String, video: MessageContent) async -> Outcome<Data> {
        // Downloaded on request since: a frame can be made from the file once it is cached.
        if case .file(let f) = video, f.size > videoAutoDownloadBytes.current, !attachments.isCached(accountId, video) {
            return .failure(.notFound("Video too large to preview"))
        }
        // A frame made earlier outlives the video in the cache: no download.
        if let cached = attachments.cachedPath(accountId, video), let frame = VideoThumbnailer.shared.cachedThumbnail(of: cached) { return .success(frame) }
        switch await attachments.localFile(accountId, session(accountId), video) {
        case .failure(let f): return .failure(f)
        case .success(let path):
            guard let frame = await VideoThumbnailer.shared.thumbnail(of: path) else { return .failure(.notFound("No preview frame")) }
            return .success(frame)
        }
    }

    // MARK: people & groups

    public func roleNames(accountId: String) async -> Outcome<[String: String]> {
        if let names = roleNameCache.current[accountId] { return .success(names) }
        guard let session = session(accountId) else { return .failure(.network("Chat is offline")) }
        let reply: XxdResponse
        switch await session.connection.request(XxdRequest("sysgetdepts")) { case .success(let r): reply = r; case .failure(let f): return .failure(f) }
        // The official client reads `data.roles` (beside `data.depts`); the reply's own `roles` field is left empty by xxd 9.
        let data = Self.decodeRoles(reply.data)
        let nested = data?.object.flatMap { Self.decodeRoles($0["roles"]) }
        let roles = nested?.object?.isEmpty == false ? nested : Self.decodeRoles(reply.raw["roles"])
        var names: [String: String] = [:]
        for (k, v) in roles?.object?.pairs ?? [] { if case .string(let s) = v, !s.trimmingCharacters(in: .whitespaces).isEmpty { names[k.trimmingCharacters(in: .whitespaces)] = s.trimmingCharacters(in: .whitespaces) } }
        roleNameCache.with { $0[accountId] = names }
        return .success(names)
    }

    private static func decodeRoles(_ v: JSONValue?) -> JSONValue? {
        guard case .string(let s)? = v else { return v }
        return try? JSONValue.parse(s)
    }

    public func members(accountId: String, chatGid: String) async -> Outcome<[Int]> {
        guard let session = session(accountId) else { return .failure(.network("Chat is offline")) }
        let data: JSONValue?
        switch await session.connection.request(XxdRequest("chatGetMembers", params: [.string(chatGid)])) { case .success(let r): data = r.data; case .failure(let f): return .failure(f) }
        let raw = data?.object?["members"] ?? data
        guard let list = raw?.array else { return .failure(.parse("Unexpected chat members reply")) }
        // Members come as ids or as user objects depending on the server.
        let ids: [Int] = list.compactMap { m in
            switch m { case .int, .double, .string: ChatMappers.int(m); case .object(let o): ChatMappers.int(o["id"]); default: nil }
        }
        let known = (try? await local.knownUserIds(accountId)) ?? []
        session.fetchMissing(IngestFollowUp(userIds: Set(ids).subtracting(known)))
        return .success(ids)
    }

    public func memberCount(accountId: String, chatGid: String) async -> Outcome<Int> {
        switch await members(accountId: accountId, chatGid: chatGid) { case .success(let ids): .success(ids.count); case .failure(let f): .failure(f) }
    }

    public func openDirectChat(accountId: String, userId: Int) async -> Outcome<String> {
        guard let session = session(accountId), let me = session.selfUserId else { return .failure(.network("Chat is offline")) }
        // The official client sorts the ids as strings ("40" < "9").
        let gid = ["\(me)", "\(userId)"].sorted().joined(separator: "&")
        if (try? await local.conversation(accountId, gid)) != nil { return .success(gid) }
        let params: [JSONValue] = [.string(gid), "", "one2one", [.int(me), .int(userId)], 0, false]
        switch await requestAndStore(accountId, session, XxdRequest("chatCreate", params: params)) { case .success: return .success(gid); case .failure(let f): return .failure(f) }
    }

    public func createGroupChat(accountId: String, name: String, memberIds: [Int]) async -> Outcome<String> {
        guard let session = session(accountId), let me = session.selfUserId else { return .failure(.network("Chat is offline")) }
        let gid = UUID().uuidString.lowercased()
        var seen = Set<Int>(), members: [JSONValue] = []
        for id in [me] + memberIds where seen.insert(id).inserted { members.append(.int(id)) }
        let params: [JSONValue] = [.string(gid), .string(name), "group", .array(members), 0, false]
        switch await requestAndStore(accountId, session, XxdRequest("chatCreate", params: params)) { case .success: return .success(gid); case .failure(let f): return .failure(f) }
    }

    public func refreshUsers(accountId: String) async -> Outcome<Void> {
        guard let session = session(accountId) else { return .failure(.network("Chat is offline")) }
        // An empty id list asks xxd for every user.
        return await requestAndStore(accountId, session, XxdRequest("usergetlist", params: [.array([])]))
    }

    public func setGroupAvatar(accountId: String, chatGid: String, text: String?, color: String?, image: Data?) async -> Outcome<Void> {
        await avatars.setGroupAvatar(session(accountId), chatGid, send: { [self] s, r in await requestAndStore(accountId, s, r) }, text: text, color: color, image: image)
    }

    public func setMyAvatar(accountId: String, image: Data, crop: ChatAvatarCrop?) async -> Outcome<Void> {
        if case .failure(let f) = await avatars.setMyAvatar(session(accountId), image, crop: crop) { return .failure(f) }
        // The new picture lives at a new URL, carried by the user list.
        if case .failure(let f) = await refreshUsers(accountId: accountId) { return .failure(f) }
        // ZenTao web sets the picture behind xxd's back, so nobody else hears of it: a `userupdate` (same status) is pushed to
        // every online user, whose clients then reload this user — picture included. Peers just see it later if this fails.
        if let s = session(accountId) { _ = await s.connection.request(userChange(s, presences.current[accountId] ?? .online)) }
        return .success(())
    }

    public func setMyPresence(accountId: String, presence: ChatPresence) async -> Outcome<Void> {
        guard let session = session(accountId), let me = session.selfUserId else { return .failure(.network("Chat is offline")) }
        let result = await requestAndStore(accountId, session, userChange(session, presence))
        if case .success = result {
            presences.with { $0[accountId] = presence }
            // The reply may omit the status; the dot should follow the pick anyway.
            try? await local.setUserStatus(accountId, me, presence.status)
        }
        return result
    }

    public func setChatStarred(accountId: String, chatGid: String, starred: Bool) async -> Outcome<Void> {
        guard let session = session(accountId) else { return .failure(.network("Chat is offline")) }
        // Moves at once; the server's reply confirms it (or the change is undone).
        try? await local.setStarred(accountId, chatGid, starred: starred)
        let result = await requestAndStore(accountId, session, XxdRequest("chatStar", params: [.bool(starred), .string(chatGid)]))
        if case .failure = result { try? await local.setStarred(accountId, chatGid, starred: !starred) }
        return result
    }

    public func setChatMuted(accountId: String, chatGid: String, muted: Bool) async -> Outcome<Void> {
        do { try await local.setMuted(accountId, chatGid, muted: muted); return .success(()) }
        catch { return .failure(.storage("Could not save: \(error.localizedDescription)")) }
    }

    public func setMessagePinned(accountId: String, chatGid: String, serverId: Int, pinned: Bool) async -> Outcome<Void> {
        guard let session = session(accountId), let me = session.selfUserId else { return .failure(.network("Chat is offline")) }
        return await requestAndStore(accountId, session, XxdRequest(pinned ? "chatPinMessages" : "chatUnpinMessages",
                                                                    params: [.string(chatGid), [.int(serverId)], .int(me)]))
    }
}
