import Foundation

/// What an ingested packet showed to be missing locally: users to load, chats to fetch.
struct IngestFollowUp: Sendable {
    var userIds: Set<Int> = []
    var chatGids: Set<String> = []
    var isEmpty: Bool { userIds.isEmpty && chatGids.isEmpty }
}

/// Turns xxd packets into database writes (conversations, messages, users, read markers, pins, presence…).
/// Ported from: lib/features/chat/data/repositories/chat_packet_ingestor.dart
final class ChatPacketIngestor: @unchecked Sendable {
    private let local: ChatLocalDatasource
    private let reactionFlag = Locked(false)
    private let isReactionRow = IsReactionRow()

    init(local: ChatLocalDatasource) { self.local = local }

    /// Whether emoji replies count as reactions: they move the last message but never add unread.
    var reactions: Bool {
        get { reactionFlag.current }
        set { reactionFlag.with { $0 = newValue } }
    }

    func ingest(_ accountId: String, _ packet: XxdResponse, selfUserId: Int?) async throws -> IngestFollowUp {
        guard packet.isSuccess else { return IngestFollowUp() }
        let data = packet.data
        switch packet.apiName {
        case "chatgetlist":
            let chats = Self.objects(data)
            try await storeChats(accountId, chats)
            return IngestFollowUp(userIds: try await unknownUsers(accountId, Set(chats.compactMap { ChatMappers.peer(of: ChatMappers.text($0["gid"]), selfUserId: selfUserId) })))
        case "chatgetbygid", "chatcreate":
            guard case .object(let chat)? = data else { break }
            try await storeChats(accountId, [chat])
            let peer = ChatMappers.peer(of: ChatMappers.text(chat["gid"]), selfUserId: selfUserId)
            return IngestFollowUp(userIds: try await unknownUsers(accountId, peer.map { [$0] } ?? []))
        // A retracted/edited message arrives whole (e.g. `deleted: true`).
        case "messagesend", "messageretract", "messageupdate":
            if case .object(let o)? = data { return try await storeMessages(accountId, [o], selfUserId: selfUserId) }
            return try await storeMessages(accountId, Self.objects(data), selfUserId: selfUserId)
        case "chatsetlastreadmessagebyindex":
            // Pushed when this account reads a chat anywhere (including here).
            if case .object(let o)? = data, let gid = o["gid"]?.string, let id = ChatMappers.int(o["id"]) { try await local.setLastReadIndex(accountId, gid, id) }
        // Someone (un)pinned messages: the reply carries the full new list.
        case "chatpinmessages", "chatunpinmessages":
            if case .object(let o)? = data, let cgid = o["cgid"]?.string { try await local.setPinned(accountId, cgid, json: ChatMappers.pinnedJson(o["allPinned"])) }
        // Someone signed in (their user record, with `status`) or out.
        case "userlogin":
            if case .object(let o)? = data, o["id"] != nil { try await local.upsertUsers([ChatMappers.userValues(accountId, o)]) }
        // Someone (this account included) changed their status or picture; `userchange` on servers before 7.x.
        case "userupdate", "userchange":
            guard case .object(let o)? = data, let userId = ChatMappers.int(o["id"]) else { break }
            if let status = o["status"]?.string { try await local.setUserStatus(accountId, userId, status) }
            // A picture change is announced this way too; a reply without the picture gets the user reloaded.
            guard let avatar = o["avatar"]?.string else { return IngestFollowUp(userIds: [userId]) }
            try await local.setUserAvatar(accountId, userId, avatar.isEmpty ? nil : avatar)
        case "userlogout":
            if case .object(let o)? = data, let id = ChatMappers.int(o["id"]) { try await local.setUserStatus(accountId, id, "offline") }
        case "chatstar":
            if case .object(let o)? = data, let gid = o["gid"]?.string {
                let star = o["star"]
                try await local.setStarred(accountId, gid, starred: star == .bool(true) || star == .int(1))
            }
        case "chatsetavatar":
            if case .object(let o)? = data, let gid = o["gid"]?.string, case .object? = o["avatar"] { try await local.setChatAvatar(accountId, gid, json: o["avatar"]!.serialized()) }
        // ZenTao's notifications and xuanbot replies.
        case "syncnotifications":
            guard let me = selfUserId else { break }
            return try await storeNotifications(accountId, data, selfUserId: me)
        case "usergetlist":
            try await local.upsertUsers(Self.objects(data).filter { $0["id"] != nil }.map { ChatMappers.userValues(accountId, $0) })
        default: break
        }
        return IngestFollowUp()
    }

    func storeNotifications(_ accountId: String, _ data: JSONValue?, selfUserId: Int) async throws -> IngestFollowUp {
        let rows = ChatMappers.notificationValues(accountId, data, selfUserId: selfUserId)
        guard !rows.isEmpty else { return IngestFollowUp() }
        let bot = ChatMappers.xuanbotGid(selfUserId)
        if rows.contains(where: { $0.string("cgid") == bot }), try await local.conversation(accountId, bot) == nil {
            try await storeChats(accountId, [JSONObject([("gid", .string(bot)), ("type", "bot"), ("name", "Xuanbot")])])
        }
        try await local.upsertMessages(rows)
        for r in rows {
            if let cgid = r.string("cgid"), let at = r.date("sentAt") {
                try await local.touchConversation(accountId, cgid, at: at)
            }
        }
        return IngestFollowUp()
    }

    /// Stores messages (history pages and live pushes) and moves their chats' counters, one transaction per call.
    func storeMessages(_ accountId: String, _ messages: [JSONObject], selfUserId: Int?, link: MessageLink = .keep) async throws -> IngestFollowUp {
        let valid = messages.filter { $0["gid"]?.string != nil && $0["cgid"]?.string != nil }
        guard !valid.isEmpty else { return IngestFollowUp() }
        var rows: [ColumnValues] = []
        for m in valid { rows.append(try await keepReactionContent(accountId, ChatMappers.messageValues(accountId, m))) }
        // Per chat, so a 50-message page is one batch, one read and one write per chat.
        var byChat: [String: [RecordedMessage]] = [:]
        let reactionsOn = reactions
        for r in rows {
            let type = r.string("contentType") ?? "", content = r.string("content") ?? ""
            byChat[r.string("cgid")!, default: []].append(RecordedMessage(
                serverId: r.int("serverId"), index: r.int("messageIndex"), sentAt: r.date("sentAt") ?? Date(),
                fromSelf: r.int("senderId") == selfUserId,
                reaction: reactionsOn && isReactionRow(replyToId: r.int("replyToId"), deleted: r.bool("deleted") ?? false, contentType: type, content: content)))
        }
        let unknown: Set<String> = try await local.transaction { [rows, byChat] d in
            try ChatLocalDatasource.upsertMessages(d, rows, link: link)
            var unknown: Set<String> = []
            for (cgid, recorded) in byChat {
                if try Int.fetchOne(d, sql: "SELECT 1 FROM chatConversations WHERE accountId=? AND gid=?", arguments: [accountId, cgid]) == nil { unknown.insert(cgid); continue }
                try ChatLocalDatasource.recordMessages(d, accountId, cgid, recorded)
            }
            return unknown
        }
        let senders = Set(rows.compactMap { $0.int("senderId") })
        return IngestFollowUp(userIds: try await unknownUsers(accountId, senders), chatGids: unknown)
    }

    /// A retracted reaction arrives as an empty deleted row: keep the stored emoji so the retraction still reads as one.
    private func keepReactionContent(_ accountId: String, _ row: ColumnValues) async throws -> ColumnValues {
        let deleted = row.bool("deleted") ?? false
        let content = row.string("content") ?? ""
        guard deleted, content.isEmpty, row.int("replyToId") != nil, let gid = row.string("gid"),
              let stored = try await local.message(accountId, gid),
              isReactionRow(replyToId: stored.replyToId, deleted: stored.deleted, contentType: stored.contentType, content: stored.content) else { return row }
        var r = row
        r.set("contentType", stored.contentType)
        r.set("content", stored.content)
        return r
    }

    private func storeChats(_ accountId: String, _ chats: [JSONObject]) async throws {
        let valid = chats.filter { $0["gid"]?.string != nil }
        let last = valid.compactMap { chat -> ColumnValues? in
            guard let m = ChatMappers.lastMessage(of: chat), m["cgid"]?.string != nil else { return nil }
            return ChatMappers.messageValues(accountId, m)
        }
        try await local.upsertConversationsWithMessages(valid.map { ChatMappers.conversationValues(accountId, $0) }, last)
    }

    private func unknownUsers(_ accountId: String, _ ids: Set<Int>) async throws -> Set<Int> {
        let wanted = ids.filter { $0 > 0 }
        if wanted.isEmpty { return [] }
        return wanted.subtracting(try await local.knownUserIds(accountId))
    }

    static func objects(_ data: JSONValue?) -> [JSONObject] {
        (data?.array ?? []).compactMap { $0.object }
    }
}
