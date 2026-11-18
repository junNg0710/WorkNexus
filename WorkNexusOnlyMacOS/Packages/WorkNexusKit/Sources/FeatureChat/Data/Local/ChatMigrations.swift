import CorePersistence
import GRDB

/// The chat tables (`ChatAccounts`, `ChatConversations`, `ChatMessages` (+3 indexes), `ChatMessageTranslations`,
/// `ChatUsers`, `ChatLinkPreviews`, `ChatSavedFiles`). The module owns its schema: the composition root passes
/// `ChatMigrations.registrar` to `AppDatabase.open(registrars:)`.
/// Ported from: lib/core/database/database.dart (chat tables)
public enum ChatMigrations {
    public static let migrationId = "chat_v1"

    public static let registrar: MigrationRegistrar = { migrator in
        migrator.registerMigration(migrationId) { db in
            try db.create(table: "chatAccounts") { t in
                t.primaryKey("accountId", .text)
                t.column("serverUrl", .text)
                t.column("pinnedFingerprint", .text)
                t.column("userId", .integer)
            }
            // Unread = lastMessageIndex − lastReadIndex (xxd's per-chat message indexes).
            try db.create(table: "chatConversations") { t in
                t.column("accountId", .text).notNull()
                t.column("gid", .text).notNull()
                t.column("type", .text).notNull()
                t.column("name", .text).notNull()
                t.column("lastActiveAt", .datetime)
                t.column("lastMessageId", .integer)
                t.column("lastMessageIndex", .integer).notNull().defaults(to: 0)
                t.column("lastReadIndex", .integer).notNull().defaults(to: 0)
                t.column("hidden", .boolean).notNull().defaults(to: false)
                t.column("archived", .boolean).notNull().defaults(to: false)
                t.column("pinnedJson", .text).notNull().defaults(to: "[]")
                t.column("avatarJson", .text)
                t.column("starred", .boolean).notNull().defaults(to: false)
                t.column("muted", .boolean).notNull().defaults(to: false)
                t.column("adminsJson", .text).notNull().defaults(to: "[]")
                t.column("committers", .text).notNull().defaults(to: "")
                t.column("ownedBy", .text)
                t.column("createdAt", .datetime)
                t.primaryKey(["accountId", "gid"])
            }
            try db.create(table: "chatMessages") { t in
                t.column("accountId", .text).notNull()
                t.column("gid", .text).notNull()
                t.column("cgid", .text).notNull()
                t.column("serverId", .integer)
                t.column("messageIndex", .integer)
                t.column("senderId", .integer).notNull()
                t.column("sentAt", .datetime).notNull()
                t.column("contentType", .text).notNull()
                t.column("content", .text).notNull()
                t.column("sendState", .text).notNull().defaults(to: "sent")
                t.column("replyToId", .integer)
                t.column("deleted", .boolean).notNull().defaults(to: false)
                // Part of a window around a jumped-to message, not (yet) of the run that reaches the newest message.
                t.column("detached", .boolean).notNull().defaults(to: false)
                // A notice the server posted about the chat (invites, renames).
                t.column("broadcast", .boolean).notNull().defaults(to: false)
                // Folded text for search (see `FoldSearchText`); nil until computed.
                t.column("searchText", .text)
                t.primaryKey(["accountId", "gid"])
            }
            try db.create(index: "chat_messages_by_chat", on: "chatMessages", columns: ["accountId", "cgid", "sentAt"])
            // The chat list joins each conversation to its last message by server id; jump windows and history paging look
            // messages up by their per-chat index.
            try db.create(index: "chat_messages_by_server_id", on: "chatMessages", columns: ["accountId", "cgid", "serverId"])
            try db.create(index: "chat_messages_by_index", on: "chatMessages", columns: ["accountId", "cgid", "messageIndex"])
            try db.create(table: "chatMessageTranslations") { t in
                t.column("accountId", .text).notNull()
                t.column("gid", .text).notNull()
                t.column("targetLang", .text).notNull()
                t.column("translatedText", .text).notNull()
                t.column("model", .text).notNull()
                t.column("createdAt", .datetime).notNull()
                t.column("visible", .boolean).notNull().defaults(to: true)
                t.primaryKey(["accountId", "gid", "targetLang"])
            }
            try db.create(table: "chatUsers") { t in
                t.column("accountId", .text).notNull()
                t.column("userId", .integer).notNull()
                t.column("account", .text).notNull()
                t.column("realname", .text).notNull()
                t.column("avatar", .text)
                t.column("deleted", .boolean).notNull().defaults(to: false)
                t.column("email", .text)
                t.column("mobile", .text)
                t.column("phone", .text)
                t.column("role", .text)
                t.column("status", .text)
                t.primaryKey(["accountId", "userId"])
            }
            try db.create(table: "chatLinkPreviews") { t in
                t.primaryKey("url", .text)
                // The page has no preview (cached so it is not fetched again).
                t.column("empty", .boolean).notNull().defaults(to: false)
                t.column("pageUrl", .text)
                t.column("siteName", .text)
                t.column("title", .text)
                t.column("description", .text)
                t.column("imageUrl", .text)
                t.column("fetchedAt", .datetime).notNull()
            }
            try db.create(table: "chatSavedFiles") { t in
                t.column("accountId", .text).notNull()
                t.column("fileId", .integer).notNull()
                t.column("path", .text).notNull()
                t.column("savedAt", .datetime).notNull()
                t.primaryKey(["accountId", "fileId"])
            }
        }
        // Read-only views under the Flutter app's table names, for the bundled MCP server.
        McpCompatMigration.register(&migrator)
    }
}
