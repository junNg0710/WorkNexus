import CoreDomain
import Foundation
import GRDB

/// Message reads/writes of `ChatLocalDatasource`.
extension ChatLocalDatasource {
    private static let escapeLike = RX(#"[\\%_]"#)

    // MARK: writes

    func upsertMessages(_ rows: [ColumnValues], link: MessageLink = .keep) async throws {
        try await db.writer.write { d in try Self.upsertMessages(d, rows, link: link) }
    }

    static func upsertMessages(_ d: Database, _ rows: [ColumnValues], link: MessageLink) throws {
        for var r in rows.map(withSearchText) {
            switch link {
            case .keep: break
            case .linked: r.set("detached", false)
            case .detached:
                // New rows start detached; one already in the timeline stays there.
                var fresh = r
                fresh.set("detached", true)
                let (sql, args) = fresh.upsertSQL(table: "chatMessages", keys: ["accountId", "gid"], insertOrIgnore: true)
                try d.execute(sql: sql, arguments: args)
            }
            // Revisiting a chat fetches its newest page again. Identical rows must not wake the live queries.
            let (sql, args) = r.upsertSQL(table: "chatMessages", keys: ["accountId", "gid"], skipUnchanged: true)
            try d.execute(sql: sql, arguments: args)
        }
    }

    func insertMessage(_ row: ColumnValues) async throws {
        let r = Self.withSearchText(row)
        let cols = r.pairs.map(\.0).joined(separator: ","), marks = r.pairs.map { _ in "?" }.joined(separator: ",")
        try await db.writer.write { try $0.execute(sql: "INSERT INTO chatMessages (\(cols)) VALUES (\(marks))", arguments: StatementArguments(r.pairs.map(\.1))) }
    }

    private static func withSearchText(_ row: ColumnValues) -> ColumnValues {
        guard let type = row.string("contentType"), let content = row.string("content") else { return row }
        var r = row
        r.set("searchText", fold.ofMessage(contentType: type, content: content))
        return r
    }

    func setSendState(_ accountId: String, _ gid: String, _ state: SendState) async throws {
        try await db.writer.write { try $0.execute(sql: "UPDATE chatMessages SET sendState=? WHERE accountId=? AND gid=?", arguments: [state.rawValue, accountId, gid]) }
    }

    func setContent(_ accountId: String, _ gid: String, contentType: String, content: String) async throws {
        try await db.writer.write { try $0.execute(sql: "UPDATE chatMessages SET contentType=?, content=?, searchText=? WHERE accountId=? AND gid=?",
                                                    arguments: [contentType, content, Self.fold.ofMessage(contentType: contentType, content: content), accountId, gid]) }
    }

    func deleteMessage(_ accountId: String, _ gid: String) async throws {
        try await db.writer.write { try $0.execute(sql: "DELETE FROM chatMessages WHERE accountId=? AND gid=?", arguments: [accountId, gid]) }
    }

    /// Marks messages stuck pending since before `before` as failed (the app died mid-send).
    @discardableResult
    func failStalePending(_ accountId: String, before: Date) async throws -> Int {
        try await db.writer.write { d in
            try d.execute(sql: "UPDATE chatMessages SET sendState='failed' WHERE accountId=? AND sendState='pending' AND sentAt<?", arguments: [accountId, before])
            return d.changesCount
        }
    }

    // MARK: reads

    func message(_ accountId: String, _ gid: String) async throws -> ChatMessageRow? {
        try await db.writer.read { d in try Row.fetchOne(d, sql: "SELECT * FROM chatMessages WHERE accountId=? AND gid=?", arguments: [accountId, gid]).map { ChatMessageRow(row: $0) } }
    }

    func oldestServerId(_ accountId: String, _ cgid: String) async throws -> Int? {
        try await db.writer.read { try Int.fetchOne($0, sql: "SELECT MIN(serverId) FROM chatMessages WHERE accountId=? AND cgid=?", arguments: [accountId, cgid]) }
    }

    func countOlder(_ accountId: String, _ cgid: String, before: Date) async throws -> Int {
        try await db.writer.read { try Int.fetchOne($0, sql: "SELECT COUNT(*) FROM chatMessages WHERE accountId=? AND cgid=? AND detached=0 AND sentAt<?", arguments: [accountId, cgid, before]) ?? 0 }
    }

    func attachmentMessages(_ accountId: String) async throws -> [(cgid: String, contentType: String, content: String)] {
        try await db.writer.read { d in
            try Row.fetchAll(d, sql: "SELECT cgid, contentType, content FROM chatMessages WHERE accountId=? AND contentType IN ('image','file')", arguments: [accountId])
                .map { ($0["cgid"], $0["contentType"], $0["content"]) }
        }
    }

    /// Case- and diacritic-folded search over the stored messages (`searchText`), newest first. Every word of the query
    /// has to be in the message, in any order; words in "quotes" as a phrase (`SearchTerms`). Narrowed to chats, senders,
    /// a kind of message and a time when `search` says so; without words it lists what those let through.
    func searchMessages(_ accountId: String, _ search: ChatMessageSearch) async throws -> [ChatMessage] {
        guard !search.asksNothing else { return [] }
        // Typed text matches literally: LIKE's own wildcards are escaped.
        let terms = SearchTerms.parse(search.query).map { Self.fold($0) }.filter { !$0.isEmpty }
            .map { folded in "%" + Self.escapeLike.replace(folded) { "\\\($0.whole)" } + "%" }
        try await fillSearchText(accountId)
        return try await db.writer.read { d in
            var sql = "SELECT * FROM chatMessages WHERE accountId=? AND deleted=0 AND \(Self.kindSQL(search.kind))"
            var args: [any DatabaseValueConvertible] = [accountId]
            for term in terms { sql += " AND searchText LIKE ? ESCAPE '\\'"; args.append(term) }
            if let chats = search.chatGids {
                sql += " AND cgid IN (\(chats.map { _ in "?" }.joined(separator: ",")))"; args += chats.map { $0 as any DatabaseValueConvertible }
            }
            if let senders = search.senderIds {
                sql += " AND senderId IN (\(senders.map { _ in "?" }.joined(separator: ",")))"; args += senders.map { $0 as any DatabaseValueConvertible }
            }
            if let since = search.since { sql += " AND sentAt>=?"; args.append(since) }
            sql += " ORDER BY sentAt DESC"
            if let limit = search.limit { sql += " LIMIT \(limit)" }
            let me = try Int.fetchOne(d, sql: "SELECT userId FROM chatAccounts WHERE accountId=?", arguments: [accountId])
            return try Row.fetchAll(d, sql: sql, arguments: StatementArguments(args)).map { ChatMappers.message(ChatMessageRow(row: $0), selfUserId: me) }
        }
    }

    /// The rows a kind of search looks at. Everything searchable but pictures when no kind is asked for: a picture has
    /// only its file name, which would answer a search for `png` with every picture there is.
    private static func kindSQL(_ kind: ChatSearchKind?) -> String {
        switch kind {
        case nil: "contentType IN ('plain','text','code','file','object')"
        case .messages: "contentType IN ('plain','text','code')"
        case .files: "contentType='file'"
        case .images: "contentType='image'"
        case .links: "(contentType='object' OR (contentType IN ('plain','text') AND (searchText LIKE '%http://%' OR searchText LIKE '%https://%')))"
        }
    }

    /// Computes `searchText` for stored rows that predate it (text first; files, links and code since they are searched
    /// too), once per account.
    private func fillSearchText(_ accountId: String) async throws {
        if searchReady.current.contains(accountId) { return }
        while true {
            let count = try await db.writer.write { d -> Int in
                let rows = try Row.fetchAll(d, sql: "SELECT gid, contentType, content FROM chatMessages WHERE accountId=? AND searchText IS NULL AND contentType IN ('plain','text','file','image','code','object') LIMIT 500", arguments: [accountId])
                for r in rows {
                    let t: String = r["contentType"], c: String = r["content"], gid: String = r["gid"]
                    // A row that folds to nothing keeps NULL; mark it with '' so it is not picked again.
                    try d.execute(sql: "UPDATE chatMessages SET searchText=? WHERE accountId=? AND gid=?", arguments: [Self.fold.ofMessage(contentType: t, content: c) ?? "", accountId, gid])
                }
                return rows.count
            }
            if count < 500 { break }
        }
        searchReady.with { _ = $0.insert(accountId) }
    }

    // MARK: watches (entities are mapped inside the observation, with the chat account's own user id)

    private func watchRows(_ accountId: String, sql: String, args: [any DatabaseValueConvertible], hideReactions: Bool = false,
                           reverse: Bool = false) -> AsyncStream<[ChatMessage]> {
        db.observe { d in
            let me = try Int.fetchOne(d, sql: "SELECT userId FROM chatAccounts WHERE accountId=?", arguments: [accountId])
            var rows = try Row.fetchAll(d, sql: sql, arguments: StatementArguments(args)).map { ChatMessageRow(row: $0) }
            if reverse { rows.reverse() }
            return rows.map { ChatMappers.message($0, selfUserId: me) }.filter { !(hideReactions && $0.isReaction) }
        }.removingDuplicates()
    }

    /// The newest `limit` timeline messages, oldest first.
    func watchMessages(_ accountId: String, _ cgid: String, limit: Int, reactions: Bool) -> AsyncStream<[ChatMessage]> {
        watchRows(accountId, sql: "SELECT * FROM chatMessages WHERE accountId=? AND cgid=? AND detached=0 ORDER BY sentAt DESC LIMIT \(limit)",
                  args: [accountId, cgid], hideReactions: reactions, reverse: true)
    }

    func watchMessagesInRange(_ accountId: String, _ cgid: String, from: Int, to: Int, reactions: Bool) -> AsyncStream<[ChatMessage]> {
        watchRows(accountId, sql: "SELECT * FROM chatMessages WHERE accountId=? AND cgid=? AND messageIndex BETWEEN ? AND ? ORDER BY messageIndex ASC, sentAt ASC",
                  args: [accountId, cgid, from, to], hideReactions: reactions)
    }

    func watchMessageByServerId(_ accountId: String, _ cgid: String, _ serverId: Int) -> AsyncStream<ChatMessage?> {
        db.observe { d -> ChatMessage? in
            let me = try Int.fetchOne(d, sql: "SELECT userId FROM chatAccounts WHERE accountId=?", arguments: [accountId])
            return try Row.fetchOne(d, sql: "SELECT * FROM chatMessages WHERE accountId=? AND cgid=? AND serverId=?", arguments: [accountId, cgid, serverId])
                .map { ChatMappers.message(ChatMessageRow(row: $0), selfUserId: me) }
        }.removingDuplicates()
    }

    func watchReplies(_ accountId: String, _ cgid: String) -> AsyncStream<[ChatMessage]> {
        watchRows(accountId, sql: "SELECT * FROM chatMessages WHERE accountId=? AND cgid=? AND replyToId IS NOT NULL ORDER BY sentAt ASC", args: [accountId, cgid])
    }

    func watchAttachments(_ accountId: String, _ cgid: String) -> AsyncStream<[ChatMessage]> {
        watchRows(accountId, sql: "SELECT * FROM chatMessages WHERE accountId=? AND cgid=? AND contentType IN ('image','file') AND deleted=0 ORDER BY sentAt DESC", args: [accountId, cgid])
    }
}
