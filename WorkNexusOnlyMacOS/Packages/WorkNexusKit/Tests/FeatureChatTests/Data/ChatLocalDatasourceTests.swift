import CorePersistence
import GRDB
import XCTest
@testable import FeatureChat

/// Ports of test/data/chat/{record_messages,reaction_unread,chat_timeline}_test.dart and the migration/unread-mapper checks.
final class ChatLocalDatasourceTests: XCTestCase {
    var db: AppDatabase!
    var local: ChatLocalDatasource!
    let day = Date(timeIntervalSince1970: 1_790_000_000)

    override func setUp() async throws {
        db = try AppDatabase.inMemory(registrars: [ChatMigrations.registrar])
        local = ChatLocalDatasource(db: db)
        try await local.upsertConversations([conv(lastId: 1003, lastIndex: 3, lastRead: 2)])
    }

    private func conv(lastId: Int, lastIndex: Int, lastRead: Int, gid: String = "g1") -> ColumnValues {
        var v = ColumnValues()
        v.set("accountId", "acc"); v.set("gid", gid); v.set("type", "group"); v.set("name", "Team")
        v.set("lastMessageId", lastId); v.set("lastMessageIndex", lastIndex); v.set("lastReadIndex", lastRead)
        return v
    }

    private func rec(_ index: Int, fromSelf: Bool = false, reaction: Bool = false, serverId: Int? = nil) -> RecordedMessage {
        RecordedMessage(serverId: serverId ?? 1000 + index, index: index, sentAt: day.addingTimeInterval(Double(index) * 60), fromSelf: fromSelf, reaction: reaction)
    }

    private func chat() async throws -> ChatConversationRow { try await local.conversation("acc", "g1")! }

    func testMigrationCreatesTablesAndIndexes() async throws {
        let (tables, indexes) = try await db.writer.read { d in
            (try String.fetchAll(d, sql: "SELECT name FROM sqlite_master WHERE type='table' AND name LIKE 'chat%'"),
             try String.fetchAll(d, sql: "SELECT name FROM sqlite_master WHERE type='index' AND name LIKE 'chat_messages_by_%'"))
        }
        XCTAssertEqual(Set(tables), ["chatAccounts", "chatConversations", "chatMessages", "chatMessageTranslations", "chatUsers", "chatLinkPreviews", "chatSavedFiles"])
        XCTAssertEqual(Set(indexes), ["chat_messages_by_chat", "chat_messages_by_server_id", "chat_messages_by_index", "chat_messages_by_reply"])
        XCTAssertEqual(ChatMigrations.migrationId, "chat_v1")
    }

    /// `chat_v2_groups` adds the group flags and the category to chats stored before it (Dart schema 64–65).
    func testGroupsMigrationAddsColumnsWithDefaultsToExistingChats() throws {
        let queue = try DatabaseQueue()
        var migrator = DatabaseMigrator()
        ChatMigrations.registrar(&migrator)
        try migrator.migrate(queue, upTo: ChatMigrations.migrationId)
        try queue.write { try $0.execute(sql: "INSERT INTO chatConversations (accountId, gid, type, name) VALUES ('acc', 'old', 'group', 'Old')") }
        // Only up to the groups step: later chat migrations (the MCP views) need the core tables this database lacks.
        try migrator.migrate(queue, upTo: ChatMigrations.groupsMigrationId)
        let row = try queue.read { try Row.fetchOne($0, sql: "SELECT * FROM chatConversations WHERE gid='old'") }
        let chat = ChatConversationRow(row: try XCTUnwrap(row))
        XCTAssertEqual(chat.category, ""); XCTAssertFalse(chat.adminInvite); XCTAssertFalse(chat.isPublic)
        XCTAssertEqual(try queue.read { try migrator.appliedIdentifiers($0) }, [ChatMigrations.migrationId, ChatMigrations.groupsMigrationId])
    }

    func testGroupSettingsAndCategoryWrites() async throws {
        try await local.upsertConversations([conv(lastId: 1, lastIndex: 1, lastRead: 1, gid: "g2")])
        try await local.setGroupSettings("acc", "g1", isPublic: true)
        try await local.setGroupSettings("acc", "g1", committers: "$ADMINS", adminInvite: true)
        try await local.setCategory("acc", ["g1", "g2"], "Work")
        var row = try await chat()
        XCTAssertTrue(row.isPublic); XCTAssertTrue(row.adminInvite); XCTAssertEqual(row.committers, "$ADMINS"); XCTAssertEqual(row.category, "Work")
        let other = try await local.conversation("acc", "g2")
        XCTAssertEqual(other?.category, "Work")
        try await local.setChatName("acc", "g1", "Renamed")
        try await local.setArchived("acc", "g1", archived: true)
        try await local.setAdmins("acc", "g1", json: "[41]")
        row = try await chat()
        XCTAssertEqual(row.name, "Renamed"); XCTAssertTrue(row.archived); XCTAssertEqual(row.adminsJson, "[41]")
    }

    func testPageMovesChatToNewestMessage() async throws {
        try await local.recordMessages("acc", "g1", [rec(4), rec(5), rec(6)])
        let row = try await chat()
        XCTAssertEqual(row.lastMessageId, 1006); XCTAssertEqual(row.lastMessageIndex, 6)
        XCTAssertEqual(row.lastActiveAt?.timeIntervalSince1970 ?? 0, day.addingTimeInterval(360).timeIntervalSince1970, accuracy: 0.01)
        XCTAssertEqual(row.lastReadIndex, 2, "nothing of ours: still unread")
    }

    func testOwnMessageMarksChatRead() async throws {
        try await local.recordMessages("acc", "g1", [rec(4), rec(5, fromSelf: true), rec(6)])
        let row = try await chat()
        XCTAssertEqual(row.lastReadIndex, 5); XCTAssertEqual(row.lastMessageIndex, 6)
    }

    func testReactionMovesLastMessageButNotUnread() async throws {
        try await local.setLastReadIndex("acc", "g1", 3)
        try await local.recordMessages("acc", "g1", [rec(4, reaction: true)])
        var row = try await chat()
        XCTAssertEqual(row.lastMessageId, 1004); XCTAssertEqual(row.lastMessageIndex, 4); XCTAssertEqual(row.lastReadIndex, 4, "a read chat stays read")
        try await local.upsertConversations([conv(lastId: 1004, lastIndex: 4, lastRead: 3)])   // the server's mark is older: never backwards
        row = try await chat()
        XCTAssertEqual(row.lastReadIndex, 4)
    }

    func testReactionInUnreadChatAddsNone() async throws {
        try await local.recordMessages("acc", "g1", [rec(4, reaction: true)])
        let row = try await chat()
        XCTAssertEqual(row.lastMessageIndex - row.lastReadIndex, 1, "only #3")
    }

    func testPageReadNewestFirstStillLeavesMessagesUnread() async throws {
        try await local.setLastReadIndex("acc", "g1", 3)
        try await local.recordMessages("acc", "g1", [rec(6, reaction: true), rec(4), rec(5)])
        let row = try await chat()
        XCTAssertEqual(row.lastMessageIndex, 6); XCTAssertEqual(row.lastMessageIndex - row.lastReadIndex, 2, "#4 and #5")
    }

    func testAlreadyRecordedPageAndOlderServerIdLeaveChatUntouched() async throws {
        let before = try await chat()
        try await local.recordMessages("acc", "g1", [rec(2), rec(3)])
        let after = try await chat()
        XCTAssertEqual(after, before)
        try await local.recordMessages("acc", "g1", [rec(1, serverId: 900)])
        let row = try await chat()
        XCTAssertEqual(row.lastMessageId, 1003); XCTAssertNil(row.lastActiveAt)
    }

    func testReactionUnreadViaIngestorFlag() async throws {
        let ingestor = ChatPacketIngestor(local: local)
        try await local.setLastReadIndex("acc", "g1", 3)
        let emojiReply: JSONObject = ["gid": "r1", "cgid": "g1", "id": 1004, "index": 4, "user": 9, "contentType": "image",
                                      "content": #"{"type":"emoji","content":":thumbsup:"}"#, "data": #"{"replyTo":1003}"#]
        ingestor.reactions = true
        _ = try await ingestor.storeMessages("acc", [emojiReply], selfUserId: 40)
        var row = try await chat()
        XCTAssertEqual(row.lastMessageIndex, 4); XCTAssertEqual(row.lastReadIndex, 4)
        // With reactions off (the default) an emoji reply is unread like any message.
        try await local.upsertConversations([conv(lastId: 1003, lastIndex: 3, lastRead: 3, gid: "g2")])
        var other = emojiReply; other["cgid"] = "g2"; other["gid"] = "r2"
        ingestor.reactions = false
        _ = try await ingestor.storeMessages("acc", [other], selfUserId: 40)
        row = try await local.conversation("acc", "g2")!
        XCTAssertEqual(row.lastMessageIndex, 4); XCTAssertEqual(row.lastReadIndex, 3)
    }

    // MARK: unread mapping (chat_unread_mapper_test)

    func testUnreadMapping() {
        func row(lastIndex: Int, lastRead: Int, gid: String = "g1", type: String = "group") -> ChatConversationRow {
            let r = Row(["accountId": "a", "gid": gid, "type": type, "name": "n", "lastActiveAt": nil, "lastMessageId": 9, "lastMessageIndex": lastIndex,
                         "lastReadIndex": lastRead, "hidden": false, "archived": false, "pinnedJson": "[]", "avatarJson": nil, "starred": false, "muted": false,
                         "adminsJson": "[]", "committers": "", "category": "", "adminInvite": false, "isPublic": false, "ownedBy": nil, "createdAt": nil] as [String: DatabaseValueConvertible?])
            return ChatConversationRow(row: r)
        }
        func msg(sender: Int) -> ChatMessageRow {
            ChatMessageRow(row: Row(["accountId": "a", "gid": "m", "cgid": "g1", "serverId": 9, "messageIndex": 5, "senderId": sender, "sentAt": day, "contentType": "plain",
                                     "content": "x", "sendState": "sent", "replyToId": nil, "deleted": false, "detached": false, "broadcast": false, "searchText": nil] as [String: DatabaseValueConvertible?]))
        }
        XCTAssertEqual(ChatMappers.conversation(row(lastIndex: 5, lastRead: 3), last: msg(sender: 7), selfUserId: 40).unreadCount, 2)
        XCTAssertEqual(ChatMappers.conversation(row(lastIndex: 5, lastRead: 3), last: msg(sender: 40), selfUserId: 40).unreadCount, 0, "your own last message is never unread")
        XCTAssertTrue(ChatMappers.conversation(row(lastIndex: 0, lastRead: 0, gid: "31&40", type: "one2one"), last: nil, selfUserId: 31).peerUserId == 40)
        XCTAssertTrue(ChatMappers.conversation(row(lastIndex: 0, lastRead: 0, gid: "40&40", type: "one2one"), last: nil, selfUserId: 40).isMyCloud)
        XCTAssertFalse(ChatMappers.conversation(row(lastIndex: 0, lastRead: 0, gid: "31&40", type: "one2one"), last: nil, selfUserId: 40).isMyCloud)
        XCTAssertFalse(ChatMappers.conversation(row(lastIndex: 0, lastRead: 0, gid: "40&40", type: "one2one"), last: nil, selfUserId: nil).isMyCloud)
    }

    // MARK: timeline (chat_timeline_test)

    private func msgValues(_ id: Int, cgid: String = "g1") -> ColumnValues {
        ChatMappers.messageValues("acc", ["gid": .string("m\(id)"), "cgid": .string(cgid), "id": .int(id), "index": .int(id), "user": 7, "date": .int(1_790_000_000 + id),
                                          "content": "x", "contentType": "plain", "deleted": false])
    }

    private func timelineIds() async throws -> [Int] {
        try await db.writer.read { try Int.fetchAll($0, sql: "SELECT serverId FROM chatMessages WHERE detached=0 ORDER BY serverId") }
    }

    func testRefreshingTheSamePageOnlyWritesChangedMessages() async throws {
        let row = msgValues(1)
        let changes = try await db.writer.write { d in
            try ChatLocalDatasource.upsertMessages(d, [row], link: .linked)
            try ChatLocalDatasource.upsertMessages(d, [row], link: .linked)
            let unchanged = d.changesCount

            var reply = row
            reply.set("replyToId", 99)
            try ChatLocalDatasource.upsertMessages(d, [reply], link: .linked)
            let addedReply = d.changesCount

            reply.set("replyToId", nil)
            try ChatLocalDatasource.upsertMessages(d, [reply], link: .linked)
            return [unchanged, addedReply, d.changesCount]
        }
        XCTAssertEqual(changes, [0, 1, 1])
    }

    func testDetachedWindowsStayOutOfTheTimelineUntilJoined() async throws {
        try await local.upsertMessages((71...120).map { msgValues($0) }, link: .linked)
        try await local.upsertMessages((1...52).map { msgValues($0) }, link: .detached)
        var ids = try await timelineIds()
        XCTAssertEqual(ids.first, 71)
        let adjacent = try await local.timeline.countAdjacent("acc", "g1", index: 52, older: false, limit: 50)
        XCTAssertEqual(adjacent, 0)
        let notYet = try await local.timeline.joinWindow("acc", "g1", from: 1, to: 52)
        XCTAssertNil(notYet, "the timeline does not start right above the window")
        try await local.upsertMessages((53...70).map { msgValues($0) }, link: .detached)
        let joined = try await local.timeline.joinWindow("acc", "g1", from: 1, to: 70)
        XCTAssertEqual(joined, 120)
        ids = try await timelineIds()
        XCTAssertEqual(ids, Array(1...120))
    }

    func testRowAlreadyInTimelineStaysThereWhenFetchedDetached() async throws {
        try await local.upsertMessages([msgValues(80)], link: .linked)
        try await local.upsertMessages([msgValues(80), msgValues(3)], link: .detached)
        let ids = try await timelineIds()
        XCTAssertEqual(ids, [80])
    }

    func testNewestPageThatSkipsAheadDetachesStaleHistory() async throws {
        try await local.upsertMessages((1...50).map { msgValues($0) }, link: .linked)
        try await local.upsertMessages((71...120).map { msgValues($0) }, link: .linked)
        try await local.timeline.detachIfCutOffBelow("acc", "g1", 71)
        let ids = try await timelineIds()
        XCTAssertEqual(ids, Array(71...120))
        try await local.upsertMessages((51...70).map { msgValues($0) }, link: .linked)
        try await local.timeline.detachIfCutOffBelow("acc", "g1", 51)   // continues the stored history: nothing is cut
        let kept = try await timelineIds()
        XCTAssertEqual(kept.first, 51)
    }

    func testTimelineExtent() async throws {
        try await local.upsertMessages((1...5).map { msgValues($0) }, link: .linked)
        let e = try await local.timeline.extent("acc", "g1")
        XCTAssertEqual(e.count, 5); XCTAssertEqual(e.oldestServerId, 1); XCTAssertTrue(e.reachesStart)
    }
}
