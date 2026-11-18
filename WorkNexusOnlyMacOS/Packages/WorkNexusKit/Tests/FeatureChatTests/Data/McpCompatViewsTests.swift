import CoreDomain
import CorePersistence
import GRDB
import XCTest
@testable import FeatureChat

/// The views the bundled MCP server reads (Flutter's table names over this app's chat tables), filled the way the app fills
/// them: a fake xxd server's chats and history, ingested by the real repository. The queries are the server's own
/// (mcp/src/worknexus.js).
final class McpCompatViewsTests: RepositoryTestCase {
    func testTheServersQueriesReadTheNativeChatTables() async throws {
        try await connectAndWait()
        let v1 = (await repo.refreshMessages(accountId: acc, chatGid: "g1")).value
        XCTAssertNotNil(v1)
        try await db.writer.read { db in
            let accounts = try Row.fetchAll(db, sql: """
                SELECT ca.account_id AS id, ca.user_id AS userId, a.handle, a.base_url AS baseUrl,
                       (SELECT COUNT(*) FROM chat_conversations c WHERE c.account_id = ca.account_id) AS chats
                FROM chat_accounts ca LEFT JOIN accounts a ON a.id = ca.account_id ORDER BY chats DESC
                """)
            XCTAssertEqual(accounts.count, 1)
            XCTAssertEqual(accounts[0]["id"], "acc")
            XCTAssertEqual(accounts[0]["handle"], "demo")
            XCTAssertEqual(accounts[0]["baseUrl"], "https://zt.test:4433/zentao")
            XCTAssertEqual(accounts[0]["chats"], 2)
            XCTAssertNotNil(accounts[0]["userId"] as Int?)

            let chats = try Row.fetchAll(db, sql: """
                SELECT gid, type, name, last_active_at AS lastActive, hidden, archived, starred
                FROM chat_conversations WHERE account_id = ? ORDER BY last_active_at DESC
                """, arguments: [acc])
            XCTAssertEqual(chats.map { $0["gid"] as String }, ["g1", "31&40"])
            XCTAssertEqual(chats[0]["lastActive"], t0Server + 120, "Unix seconds (of the newest message), as drift stores them")
            XCTAssertEqual(chats[0]["hidden"], false)

            let messages = try Row.fetchAll(db, sql: """
                SELECT gid, cgid, server_id AS serverId, sender_id AS senderId, sent_at AS sentAt,
                  content_type AS contentType, content, deleted, send_state AS sendState FROM chat_messages
                WHERE account_id = ? AND cgid = ? AND sent_at < ? ORDER BY sent_at DESC, server_id DESC LIMIT ?
                """, arguments: [acc, "g1", Int.max, 5])
            XCTAssertEqual(messages.map { $0["serverId"] as Int }, [120, 119, 118, 117, 116])
            XCTAssertEqual(messages[0]["sentAt"], t0Server + 120)
            XCTAssertEqual(messages[0]["sendState"], "sent")
            XCTAssertEqual(messages[0]["content"], "hi")

            let timeline = try XCTUnwrap(Row.fetchOne(db, sql: """
                SELECT COUNT(*) FILTER (WHERE sent_at < ?) AS n, MIN(message_index) AS first
                FROM chat_messages WHERE account_id = ? AND cgid = ? AND detached = 0
                """, arguments: [t0Server + 100, acc, "g1"]))
            XCTAssertGreaterThan(timeline["n"] as Int, 0)
            XCTAssertGreaterThan(timeline["first"] as Int, 1)

            let users = try Row.fetchAll(db, sql: "SELECT user_id AS id, account, realname FROM chat_users WHERE account_id = ?", arguments: [acc])
            XCTAssertFalse(users.isEmpty)
            let newest = try Int.fetchOne(db, sql: "SELECT MAX(sent_at) AS t FROM chat_messages WHERE account_id = ?", arguments: [acc])
            XCTAssertEqual(newest, t0Server + 120)
        }
    }

    /// The generated `accounts.base_url` must not get in the way of the app's own account writes.
    func testAccountsStayWritableWithTheGeneratedColumn() async throws {
        let workspaces = GRDBWorkspaceRepository(db: db)
        let account = Account(id: "c", workspaceId: "ws", providerType: .zentao, handle: "x", baseUrl: "https://c.test")
        let v2 = (await workspaces.upsertAccount(account)).value
        XCTAssertNotNil(v2)
        var renamed = account; renamed.handle = "y"
        let v3 = (await workspaces.upsertAccount(renamed)).value
        XCTAssertNotNil(v3, "GRDB records update an account with base_url present")
        var it = workspaces.watchAccounts().makeAsyncIterator()
        let v4 = await it.next()?.first { $0.id == "c" }?.handle
        XCTAssertEqual(v4, "y")
        try await db.writer.write { db in
            try db.execute(sql: "UPDATE accounts SET baseUrl = 'https://other.test/zentao' WHERE id = 'acc'")
            try db.execute(sql: "INSERT INTO accounts (id, workspaceId, providerType, handle, baseUrl) VALUES ('b','ws','gitlab','me',NULL)")
            XCTAssertEqual(try String.fetchOne(db, sql: "SELECT base_url FROM accounts WHERE id = 'acc'"), "https://other.test/zentao")
            XCTAssertNil(try String.fetchOne(db, sql: "SELECT base_url FROM accounts WHERE id = 'b'"))
        }
    }
}
