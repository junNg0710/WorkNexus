import CorePersistence
import GRDB

/// Lets the bundled MCP server (`assets/mcp/worknexus-mcp.mjs`, unchanged from the Flutter app) read this app's chats.
///
/// The server reads ZenTao chats straight from the app's SQLite file, with the Flutter app's (drift) schema: snake_case
/// tables and columns, times in Unix seconds. This app's tables are camelCase with GRDB date strings, so this migration
/// adds read-only views under the drift names, converting on the fly:
/// `chat_accounts`, `chat_conversations`, `chat_messages`, `chat_users` (the columns the server selects, plus their
/// neighbours), and — because the server joins the core `accounts` table for `base_url` — a virtual generated column
/// `accounts.base_url` (a copy of `baseUrl`; virtual, so nothing is stored and GRDB records, which name their columns,
/// never write it). Nothing in this app reads them.
/// Ported from: mcp/src/worknexus.js (the queries these views answer)
enum McpCompatMigration {
    static let migrationId = "chat_mcp_compat_v1"

    /// Unix seconds of a GRDB date column (`YYYY-MM-DD HH:MM:SS.SSS`, UTC); NULL stays NULL.
    private static func unixSeconds(_ column: String) -> String { "CAST(strftime('%s', \(column)) AS INTEGER)" }

    static func register(_ migrator: inout DatabaseMigrator) {
        migrator.registerMigration(migrationId) { db in
            try db.execute(sql: """
                CREATE VIEW chat_accounts AS
                  SELECT accountId AS account_id, serverUrl AS server_url, userId AS user_id FROM chatAccounts;
                CREATE VIEW chat_conversations AS
                  SELECT accountId AS account_id, gid, type, name, \(unixSeconds("lastActiveAt")) AS last_active_at,
                         lastMessageId AS last_message_id, lastMessageIndex AS last_message_index, lastReadIndex AS last_read_index,
                         hidden, archived, starred, muted
                  FROM chatConversations;
                CREATE VIEW chat_messages AS
                  SELECT accountId AS account_id, gid, cgid, serverId AS server_id, messageIndex AS message_index,
                         senderId AS sender_id, \(unixSeconds("sentAt")) AS sent_at, contentType AS content_type, content,
                         sendState AS send_state, replyToId AS reply_to_id, deleted, detached, broadcast, searchText AS search_text
                  FROM chatMessages;
                CREATE VIEW chat_users AS
                  SELECT accountId AS account_id, userId AS user_id, account, realname, avatar, deleted FROM chatUsers;
                ALTER TABLE accounts ADD COLUMN base_url TEXT GENERATED ALWAYS AS (baseUrl) VIRTUAL;
                """)
        }
    }
}
