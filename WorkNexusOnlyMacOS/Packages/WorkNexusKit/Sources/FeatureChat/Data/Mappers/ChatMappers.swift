import Foundation
import GRDB

/// xxd packet data → column values, and rows → domain entities (the data boundary: rule 3.3).
/// Ported from: lib/features/chat/data/mappers/chat_mappers.dart
enum ChatMappers {
    static let notificationContentType = "notification"

    // MARK: xxd → rows

    static func conversationValues(_ accountId: String, _ chat: JSONObject) -> ColumnValues {
        var v = ColumnValues()
        let info = chat["lastMessageInfo"]?.object
        v.set("accountId", accountId)
        v.set("gid", chat["gid"]?.string ?? "")
        v.set("type", text(chat["type"]))
        v.set("name", text(chat["name"]))
        v.set("lastActiveAt", date(chat["lastActiveTime"]))
        v.set("lastMessageId", int(chat["lastMessage"]))
        if let idx = info.flatMap({ int($0["index"]) }) { v.set("lastMessageIndex", idx) }
        v.set("lastReadIndex", int(chat["lastReadMessageIndex"]) ?? 0)
        v.set("hidden", chat["hide"] == .bool(true))
        v.set("archived", (int(chat["archiveDate"]) ?? 0) > 0 || (int(chat["dismissDate"]) ?? 0) > 0)
        if chat.contains("pinnedMessages") { v.set("pinnedJson", pinnedJson(chat["pinnedMessages"])) }
        if chat.contains("admins") { v.set("adminsJson", pinnedJson(chat["admins"])) }
        if chat.contains("committers") { v.set("committers", text(chat["committers"])) }
        if chat.contains("category") { v.set("category", text(chat["category"])) }
        if chat.contains("adminInvite") { v.set("adminInvite", flag(chat["adminInvite"])) }
        if chat.contains("public") { v.set("isPublic", flag(chat["public"])) }
        v.set("ownedBy", trimmed(chat["ownedBy"]))
        if let star = chat["star"] { v.set("starred", star == .bool(true) || star == .int(1) || star == .string("1")) }
        if case .object? = chat["avatar"] { v.set("avatarJson", chat["avatar"]!.serialized()) }
        v.set("createdAt", date(chat["createdDate"]))
        return v
    }

    /// The pinned/admin id list as stored: a JSON array of ints.
    static func pinnedJson(_ pinned: JSONValue?) -> String {
        JSONValue.array((pinned?.array ?? []).compactMap { int($0) }.map { .int($0) }).serialized()
    }

    static func ids(fromJson json: String) -> [Int] {
        guard let v = try? JSONValue.parse(json), let a = v.array else { return [] }
        return a.compactMap { int($0) }
    }

    /// The chat's `lastMessageInfo` when it is a whole message.
    static func lastMessage(of chat: JSONObject) -> JSONObject? {
        guard case .object(let info)? = chat["lastMessageInfo"], info["gid"]?.string != nil else { return nil }
        return info
    }

    static func messageValues(_ accountId: String, _ m: JSONObject) -> ColumnValues {
        var v = ColumnValues()
        let content = m["content"]
        v.set("accountId", accountId)
        v.set("gid", m["gid"]?.string ?? "")
        v.set("cgid", m["cgid"]?.string ?? "")
        v.set("serverId", int(m["id"]))
        v.set("messageIndex", int(m["index"]))
        v.set("senderId", int(m["user"]) ?? int(m["senderId"]) ?? 0)
        v.set("sentAt", date(m["date"]) ?? Date())
        v.set("contentType", m["contentType"].flatMap { $0.isNull ? nil : JS.toString($0) } ?? "plain")
        switch content {
        case .string(let s)?: v.set("content", s)
        case nil, .null?: v.set("content", "")
        case let c?: v.set("content", c.serialized())
        }
        v.set("sendState", SendState.sent.rawValue)
        v.set("deleted", m["deleted"] == .bool(true))
        v.set("replyToId", replyTo(of: m["data"]))
        // Left alone when absent, so a partial copy (a chat's `lastMessageInfo`) never clears a stored notice's flag.
        if m.contains("type") { v.set("broadcast", m["type"] == .string("broadcast")) }
        return v
    }

    static func xuanbotGid(_ selfUserId: Int) -> String { "\(selfUserId)&xuanbot" }

    static func notificationValues(_ accountId: String, _ data: JSONValue?, selfUserId: Int) -> [ColumnValues] {
        let items: [JSONValue]
        switch data {
        case .array(let a)?: items = a
        case .object(let o)? where o["cgid"] != nil && !(o["cgid"]!.isNull): items = [.object(o)]
        case .object(let o)?: items = o.keys.compactMap { o[$0] }
        default: items = []
        }
        let bot = xuanbotGid(selfUserId)
        return items.compactMap { item in
            guard case .object(let o) = item else { return nil }
            var v = ColumnValues()
            v.set("accountId", accountId)
            v.set("gid", o["gid"].flatMap { $0.isNull ? nil : JS.toString($0) } ?? "notification-\(o["id"].map { JS.toString($0) } ?? "null")")
            let cgid = o["cgid"]?.string
            v.set("cgid", (cgid?.isEmpty == false && cgid != "notification") ? cgid! : bot)
            v.set("senderId", 0)
            v.set("sentAt", date(o["date"]) ?? Date())
            v.set("contentType", notificationContentType)
            v.set("content", item.serialized())
            v.set("sendState", SendState.sent.rawValue)
            return v
        }
    }

    static func replyTo(of data: JSONValue?) -> Int? {
        var decoded = data
        if case .string(let s)? = data, !s.isEmpty { decoded = try? JSONValue.parse(s) }
        guard case .object(let o)? = decoded else { return nil }
        return int(o["replyTo"])
    }

    static func messageData(replyToId: Int?) -> String {
        replyToId.map { JSONValue.object(JSONObject([("replyTo", .int($0))])).serialized() } ?? ""
    }

    static func userValues(_ accountId: String, _ u: JSONObject) -> ColumnValues {
        var v = ColumnValues()
        v.set("accountId", accountId)
        v.set("userId", int(u["id"]) ?? 0)
        v.set("account", text(u["account"]))
        v.set("realname", text(u["realname"]))
        if case .string(let a)? = u["avatar"], !a.isEmpty { v.set("avatar", a) } else { v.set("avatar", nil) }
        v.set("deleted", u["deleted"] == .bool(true))
        v.set("email", trimmed(u["email"])); v.set("mobile", trimmed(u["mobile"]))
        v.set("phone", trimmed(u["phone"])); v.set("role", trimmed(u["role"]))
        if u.contains("status") { v.set("status", trimmed(u["status"])) }
        return v
    }

    /// The other user of a `a&b` one-to-one gid.
    static func peer(of gid: String, selfUserId: Int?) -> Int? {
        let ids = gid.split(separator: "&", omittingEmptySubsequences: false).compactMap { Int($0) }
        guard ids.count == 2 else { return nil }
        return ids[0] == selfUserId ? ids[1] : ids[0]
    }

    // MARK: rows → domain

    static func conversation(_ row: ChatConversationRow, last: ChatMessageRow?, selfUserId: Int?) -> ChatConversation {
        let type = ChatType(rawValue: row.type) ?? .other
        // Sending reads the chat: the server's read mark only moves when the chat is marked read, so without this your
        // own last message counted as unread.
        let mineLast = last != nil && selfUserId != nil && last!.senderId == selfUserId
        let unread = mineLast ? 0 : row.lastMessageIndex - row.lastReadIndex
        let peer = type == .one2one ? Self.peer(of: row.gid, selfUserId: selfUserId) : nil
        return ChatConversation(
            accountId: row.accountId, gid: row.gid, type: type, name: row.name, unreadCount: max(0, unread),
            lastActiveAt: row.lastActiveAt, lastMessage: last.map { message($0, selfUserId: selfUserId) }, peerUserId: peer,
            isMyCloud: peer != nil && peer == selfUserId, hidden: row.hidden, archived: row.archived, starred: row.starred,
            muted: row.muted, pinnedMessageIds: ids(fromJson: row.pinnedJson), adminIds: ids(fromJson: row.adminsJson),
            committers: row.committers, category: row.category, adminInvite: row.adminInvite, isPublic: row.isPublic,
            ownerAccount: row.ownedBy, avatarJson: row.avatarJson, createdAt: row.createdAt)
    }

    private static let parse = ParseMessageContent()
    private static let reactionRow = IsReactionRow()

    static func message(_ row: ChatMessageRow, selfUserId: Int?) -> ChatMessage {
        let retracted = reactionRow.retracted(replyToId: row.replyToId, deleted: row.deleted, contentType: row.contentType, content: row.content)
        return ChatMessage(
            accountId: row.accountId, gid: row.gid, chatGid: row.cgid, senderId: row.senderId, sentAt: row.sentAt,
            content: retracted ? .emoji("") : parse(row.contentType, row.content), isMine: selfUserId != nil && row.senderId == selfUserId,
            sendState: SendState(rawValue: row.sendState) ?? .sent, serverId: row.serverId, index: row.messageIndex,
            replyToId: row.replyToId, deleted: row.deleted, isNotice: row.broadcast)
    }

    static func user(_ r: ChatUserRow) -> ChatUser {
        ChatUser(accountId: r.accountId, userId: r.userId, account: r.account, realname: r.realname, avatarUrl: r.avatar,
                 deleted: r.deleted, email: r.email, mobile: r.mobile, phone: r.phone, role: r.role, status: r.status)
    }

    // MARK: JSON scalars

    static func int(_ v: JSONValue?) -> Int? {
        switch v { case .int(let i)?: i; case .double(let d)?: d.isFinite ? Int(d) : nil; case .string(let s)?: Int(s); default: nil }
    }

    /// xxd sends flags as `true`, `1`, `"1"` (ZenTao's enum('0','1')) or their opposites.
    static func flag(_ v: JSONValue?) -> Bool { v == .bool(true) || v == .int(1) || v == .string("1") || v == .double(1) }

    /// `'${v ?? ''}'`
    static func text(_ v: JSONValue?) -> String { v.flatMap { $0.isNull ? nil : JS.toString($0) } ?? "" }

    /// Trimmed non-empty text, else nil.
    static func trimmed(_ v: JSONValue?) -> String? {
        guard let v, !v.isNull else { return nil }
        let s = JS.toString(v).trimmingCharacters(in: .whitespacesAndNewlines)
        return s.isEmpty ? nil : s
    }

    /// Unix seconds or milliseconds → Date; nil for missing or non-positive.
    static func date(_ v: JSONValue?) -> Date? {
        guard let n = int(v), n > 0 else { return nil }
        return Date(timeIntervalSince1970: n < 100_000_000_000 ? Double(n) : Double(n) / 1000)
    }
}
