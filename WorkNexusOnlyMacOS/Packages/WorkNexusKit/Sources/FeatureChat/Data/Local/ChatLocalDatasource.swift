import CoreDomain
import CorePersistence
import Foundation
import GRDB

/// One message recorded against its conversation's counters.
struct RecordedMessage: Sendable {
    var serverId: Int?
    var index: Int?
    var sentAt: Date
    var fromSelf: Bool
    /// An emoji reply: moves the last message but is not unread.
    var reaction: Bool
}

/// SQLite access for chat (GRDB; the database is the single source of truth, rule 16). Raw SQL on the tables of
/// `ChatMigrations`; rows are decoded into the DTOs of `ChatRows.swift` and mapped to entities by `ChatMappers`.
/// Ported from: lib/features/chat/data/datasources/chat_local_datasource.dart
final class ChatLocalDatasource: @unchecked Sendable {
    let db: AppDatabase
    let timeline: ChatTimelineDatasource
    static let fold = FoldSearchText()
    let searchReady = Locked<Set<String>>([])

    init(db: AppDatabase) { self.db = db; timeline = ChatTimelineDatasource(db: db) }

    // MARK: accounts

    /// The WorkNexus account row (core table) this chat account belongs to.
    func account(_ accountId: String) async throws -> Account? {
        try await db.writer.read { d in
            guard let r = try Row.fetchOne(d, sql: "SELECT * FROM accounts WHERE id=?", arguments: [accountId]),
                  let type = ProviderType(rawValue: r["providerType"]) else { return nil }
            return Account(id: r["id"], workspaceId: r["workspaceId"], providerType: type, handle: r["handle"],
                           baseUrl: r["baseUrl"], credentialsRef: r["credentialsRef"])
        }
    }

    /// The account name ZenTao itself reports for this login (`profile.account` of the stored `GET /user` reply).
    /// xxd matches it case-sensitively, so chat must sign in with this, not with the handle as typed.
    /// Ported from: chat_local_datasource.dart `zenTaoAccountName`.
    func zenTaoAccountName(_ accountId: String) async throws -> String? {
        try await db.writer.read { d in
            guard try d.tableExists("zenTaoProfiles"),
                  let json = try String.fetchOne(d, sql: "SELECT profileJson FROM zenTaoProfiles WHERE accountId=?", arguments: [accountId]),
                  let data = json.data(using: .utf8),
                  let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let profile = root["profile"] as? [String: Any],
                  let name = (profile["account"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines), !name.isEmpty else { return nil }
            return name
        }
    }

    func chatAccount(_ accountId: String) async throws -> ChatAccountRow? {
        try await db.writer.read { d in try Row.fetchOne(d, sql: "SELECT * FROM chatAccounts WHERE accountId=?", arguments: [accountId]).map(ChatAccountRow.init) }
    }

    /// Writes the given fields of the chat account row (others keep their value).
    func saveChatAccount(_ accountId: String, serverUrl: String?? = nil, pinnedFingerprint: String?? = nil, userId: Int?? = nil) async throws {
        var v = ColumnValues()
        v.set("accountId", accountId)
        if let serverUrl { v.set("serverUrl", serverUrl) }
        if let pinnedFingerprint { v.set("pinnedFingerprint", pinnedFingerprint) }
        if let userId { v.set("userId", userId) }
        let (sql, args) = v.upsertSQL(table: "chatAccounts", keys: ["accountId"])
        try await db.writer.write { try $0.execute(sql: sql, arguments: args) }
    }

    func pinnedFingerprints() async throws -> [String] {
        try await db.writer.read { try String.fetchAll($0, sql: "SELECT pinnedFingerprint FROM chatAccounts WHERE pinnedFingerprint IS NOT NULL AND pinnedFingerprint != ''") }
    }

    func chatAccountIds() async throws -> [String] {
        try await db.writer.read { try String.fetchAll($0, sql: "SELECT accountId FROM chatAccounts") }
    }

    func selfUserId(_ accountId: String) async throws -> Int? {
        try await db.writer.read { try Int.fetchOne($0, sql: "SELECT userId FROM chatAccounts WHERE accountId=?", arguments: [accountId]) }
    }

    // MARK: conversations

    /// Upserts conversations; a stored read marker is never moved backwards by a stale server value.
    func upsertConversations(_ rows: [ColumnValues]) async throws {
        try await db.writer.write { d in try Self.upsertConversations(d, rows) }
    }

    private static func upsertConversations(_ d: Database, _ rows: [ColumnValues]) throws {
        for r in rows {
            let (sql, args) = r.upsertSQL(table: "chatConversations", keys: ["accountId", "gid"],
                                          merge: ["lastReadIndex": "MAX(chatConversations.lastReadIndex, excluded.lastReadIndex)"])
            try d.execute(sql: sql, arguments: args)
        }
    }

    func upsertConversationsWithMessages(_ conversations: [ColumnValues], _ messages: [ColumnValues]) async throws {
        try await db.writer.write { d in
            try Self.upsertConversations(d, conversations)
            try Self.upsertMessages(d, messages, link: .keep)
        }
    }

    func conversation(_ accountId: String, _ gid: String) async throws -> ChatConversationRow? {
        try await db.writer.read { d in try Row.fetchOne(d, sql: "SELECT * FROM chatConversations WHERE accountId=? AND gid=?", arguments: [accountId, gid]).map { ChatConversationRow(row: $0) } }
    }

    /// Runs `work` in one write transaction.
    func transaction<T: Sendable>(_ work: @escaping @Sendable (Database) throws -> T) async throws -> T {
        try await db.writer.write(work)
    }

    /// Moves the conversation's last message / read counters for newly stored messages (never backwards; own messages
    /// read the chat; reactions move the read marker with the last message so they never count as unread).
    func recordMessages(_ accountId: String, _ cgid: String, _ messages: [RecordedMessage]) async throws {
        try await db.writer.write { d in try Self.recordMessages(d, accountId, cgid, messages) }
    }

    static func recordMessages(_ d: Database, _ accountId: String, _ cgid: String, _ messages: [RecordedMessage]) throws {
        guard let r = try Row.fetchOne(d, sql: "SELECT * FROM chatConversations WHERE accountId=? AND gid=?", arguments: [accountId, cgid]) else { return }
        let row = ChatConversationRow(row: r)
        var lastId = row.lastMessageId, lastIndex = row.lastMessageIndex, lastRead = row.lastReadIndex, lastActive = row.lastActiveAt
        // By index, whatever order a page came in: what each message adds to the unread count is decided oldest first.
        for m in messages.sorted(by: { ($0.index ?? 1 << 30) < ($1.index ?? 1 << 30) }) {
            if let s = m.serverId, s > (lastId ?? 0) { lastId = s; lastActive = m.sentAt }
            let before = lastIndex
            if let i = m.index, i > lastIndex { lastIndex = i }
            if m.index != nil && m.fromSelf { lastRead = lastIndex }
            else if m.reaction { lastRead += lastIndex - before }   // moving both by the same step leaves the count as it was
        }
        if lastId == row.lastMessageId, lastIndex == row.lastMessageIndex, lastRead == row.lastReadIndex, lastActive == row.lastActiveAt { return }
        try d.execute(sql: "UPDATE chatConversations SET lastMessageId=?, lastMessageIndex=?, lastReadIndex=?, lastActiveAt=? WHERE accountId=? AND gid=?",
                      arguments: [lastId, lastIndex, lastRead, lastActive, accountId, cgid])
    }

    func touchConversation(_ accountId: String, _ gid: String, at: Date) async throws {
        try await db.writer.write { try $0.execute(sql: "UPDATE chatConversations SET lastActiveAt=? WHERE accountId=? AND gid=? AND (lastActiveAt IS NULL OR lastActiveAt<?)", arguments: [at, accountId, gid, at]) }
    }

    /// Moves the read marker forward only.
    func setLastReadIndex(_ accountId: String, _ gid: String, _ index: Int) async throws {
        try await db.writer.write { try $0.execute(sql: "UPDATE chatConversations SET lastReadIndex=? WHERE accountId=? AND gid=? AND lastReadIndex<?", arguments: [index, accountId, gid, index]) }
    }

    private func setConversation(_ accountId: String, _ gid: String, _ column: String, _ value: any DatabaseValueConvertible) async throws {
        try await db.writer.write { try $0.execute(sql: "UPDATE chatConversations SET \(column)=? WHERE accountId=? AND gid=?", arguments: [value, accountId, gid]) }
    }
    func setChatAvatar(_ accountId: String, _ gid: String, json: String) async throws { try await setConversation(accountId, gid, "avatarJson", json) }
    func setPinned(_ accountId: String, _ gid: String, json: String) async throws { try await setConversation(accountId, gid, "pinnedJson", json) }
    func setStarred(_ accountId: String, _ gid: String, starred: Bool) async throws { try await setConversation(accountId, gid, "starred", starred) }
    func setMuted(_ accountId: String, _ gid: String, muted: Bool) async throws { try await setConversation(accountId, gid, "muted", muted) }
    func setChatName(_ accountId: String, _ gid: String, _ name: String) async throws { try await setConversation(accountId, gid, "name", name) }
    /// Archives a chat (or a dismissed group), taking it off the chat list.
    func setArchived(_ accountId: String, _ gid: String, archived: Bool) async throws { try await setConversation(accountId, gid, "archived", archived) }
    /// Replaces a group's admin ids (`json` is a JSON array).
    func setAdmins(_ accountId: String, _ gid: String, json: String) async throws { try await setConversation(accountId, gid, "adminsJson", json) }

    /// Updates a group's settings; a nil one is left as it is.
    func setGroupSettings(_ accountId: String, _ gid: String, committers: String? = nil, isPublic: Bool? = nil, adminInvite: Bool? = nil) async throws {
        var sets: [String] = [], args: [DatabaseValue] = []
        if let committers { sets.append("committers=?"); args.append(committers.databaseValue) }
        if let isPublic { sets.append("isPublic=?"); args.append(isPublic.databaseValue) }
        if let adminInvite { sets.append("adminInvite=?"); args.append(adminInvite.databaseValue) }
        guard !sets.isEmpty else { return }
        let arguments = StatementArguments(args + [accountId.databaseValue, gid.databaseValue])
        let sql = "UPDATE chatConversations SET \(sets.joined(separator: ", ")) WHERE accountId=? AND gid=?"
        try await db.writer.write { try $0.execute(sql: sql, arguments: arguments) }
    }

    /// Files chats `gids` under `category` ("" for none).
    func setCategory(_ accountId: String, _ gids: [String], _ category: String) async throws {
        guard !gids.isEmpty else { return }
        let marks = gids.map { _ in "?" }.joined(separator: ",")
        let arguments = StatementArguments([category, accountId] + gids)
        try await db.writer.write { try $0.execute(sql: "UPDATE chatConversations SET category=? WHERE accountId=? AND gid IN (\(marks))", arguments: arguments) }
    }

    /// Conversations with their last message, pinned first then newest activity, with the chat account's own user id.
    func watchConversations(_ accountId: String) -> AsyncStream<[ChatConversation]> {
        db.observe { d in
            let me = try Int.fetchOne(d, sql: "SELECT userId FROM chatAccounts WHERE accountId=?", arguments: [accountId])
            let rows = try Row.fetchAll(d, sql: """
                SELECT c.*, m.accountId AS m_accountId, m.gid AS m_gid, m.cgid AS m_cgid, m.serverId AS m_serverId,
                       m.messageIndex AS m_messageIndex, m.senderId AS m_senderId, m.sentAt AS m_sentAt, m.contentType AS m_contentType,
                       m.content AS m_content, m.sendState AS m_sendState, m.replyToId AS m_replyToId, m.deleted AS m_deleted,
                       m.detached AS m_detached, m.broadcast AS m_broadcast, m.searchText AS m_searchText
                FROM chatConversations c
                LEFT JOIN chatMessages m ON m.accountId = c.accountId AND m.cgid = c.gid AND m.serverId = c.lastMessageId
                WHERE c.accountId = ? ORDER BY c.starred DESC, c.lastActiveAt DESC
                """, arguments: [accountId])
            return rows.map { r in
                let last: ChatMessageRow? = r["m_gid"] == nil ? nil : ChatMessageRow(row: r, prefix: "m_")
                return ChatMappers.conversation(ChatConversationRow(row: r), last: last, selfUserId: me)
            }
        }.removingDuplicates()
    }

    // MARK: users

    func upsertUsers(_ rows: [ColumnValues]) async throws {
        try await db.writer.write { d in
            for r in rows {
                let (sql, args) = r.upsertSQL(table: "chatUsers", keys: ["accountId", "userId"])
                try d.execute(sql: sql, arguments: args)
            }
        }
    }

    func knownUserIds(_ accountId: String) async throws -> Set<Int> {
        try await db.writer.read { Set(try Int.fetchAll($0, sql: "SELECT userId FROM chatUsers WHERE accountId=?", arguments: [accountId])) }
    }

    func setUserStatus(_ accountId: String, _ userId: Int, _ status: String) async throws {
        try await db.writer.write { try $0.execute(sql: "UPDATE chatUsers SET status=? WHERE accountId=? AND userId=?", arguments: [status, accountId, userId]) }
    }

    func setUserAvatar(_ accountId: String, _ userId: Int, _ avatar: String?) async throws {
        try await db.writer.write { try $0.execute(sql: "UPDATE chatUsers SET avatar=? WHERE accountId=? AND userId=?", arguments: [avatar, accountId, userId]) }
    }

    func watchUsers(_ accountId: String) -> AsyncStream<[ChatUser]> {
        db.observe { d in try Row.fetchAll(d, sql: "SELECT * FROM chatUsers WHERE accountId=?", arguments: [accountId]).map { ChatMappers.user(ChatUserRow(row: $0)) } }
            .removingDuplicates()
    }

    func watchSelfUserId(_ accountId: String) -> AsyncStream<Int?> {
        db.observe { d in try Int.fetchOne(d, sql: "SELECT userId FROM chatAccounts WHERE accountId=?", arguments: [accountId]) }.removingDuplicates()
    }

    // MARK: saved copies

    func savedFilePath(_ accountId: String, _ fileId: Int) async throws -> String? {
        try await db.writer.read { try String.fetchOne($0, sql: "SELECT path FROM chatSavedFiles WHERE accountId=? AND fileId=?", arguments: [accountId, fileId]) }
    }

    func saveSavedFilePath(_ accountId: String, _ fileId: Int, _ path: String, at: Date) async throws {
        try await db.writer.write { try $0.execute(sql: "INSERT INTO chatSavedFiles (accountId,fileId,path,savedAt) VALUES (?,?,?,?) ON CONFLICT(accountId,fileId) DO UPDATE SET path=excluded.path, savedAt=excluded.savedAt", arguments: [accountId, fileId, path, at]) }
    }

    // MARK: translations

    func messageTranslation(_ accountId: String, _ gid: String, _ lang: String) async throws -> ChatMessageTranslation? {
        try await db.writer.read { d in try Self.translation(d, accountId, gid, lang) }
    }

    static func translation(_ d: Database, _ accountId: String, _ gid: String, _ lang: String) throws -> ChatMessageTranslation? {
        try Row.fetchOne(d, sql: "SELECT * FROM chatMessageTranslations WHERE accountId=? AND gid=? AND targetLang=?", arguments: [accountId, gid, lang]).map { r in
            let model: String = r["model"]
            return ChatMessageTranslation(accountId: accountId, gid: gid, targetLang: lang, text: r["translatedText"], model: model.isEmpty ? nil : model, createdAt: r["createdAt"], visible: r["visible"])
        }
    }

    func watchMessageTranslation(_ accountId: String, _ gid: String, _ lang: String) -> AsyncStream<ChatMessageTranslation?> {
        db.observe { try Self.translation($0, accountId, gid, lang) }.removingDuplicates()
    }

    func setMessageTranslationVisible(_ accountId: String, _ gid: String, _ lang: String, visible: Bool) async throws {
        try await db.writer.write { try $0.execute(sql: "UPDATE chatMessageTranslations SET visible=? WHERE accountId=? AND gid=? AND targetLang=?", arguments: [visible, accountId, gid, lang]) }
    }

    func saveMessageTranslation(_ t: ChatMessageTranslation) async throws {
        try await db.writer.write { try $0.execute(sql: "INSERT INTO chatMessageTranslations (accountId,gid,targetLang,translatedText,model,createdAt,visible) VALUES (?,?,?,?,?,?,?) ON CONFLICT(accountId,gid,targetLang) DO UPDATE SET translatedText=excluded.translatedText, model=excluded.model, createdAt=excluded.createdAt, visible=excluded.visible", arguments: [t.accountId, t.gid, t.targetLang, t.text, t.model ?? "", t.createdAt, t.visible]) }
    }
}
