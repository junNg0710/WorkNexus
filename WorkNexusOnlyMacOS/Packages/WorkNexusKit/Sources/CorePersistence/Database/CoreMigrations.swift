import GRDB

/// Core tables (Workspaces, Accounts, Projects, Tickets, Comments, Activities, Translations, SavedFilters, Settings).
/// Naming follows the drift originals; Settings is a single JSON row instead of ~40 columns.
enum CoreMigrations {
    static func register(_ m: inout DatabaseMigrator) {
        m.registerMigration("core_v1") { db in
            try db.create(table: "workspaces") { t in
                t.primaryKey("id", .text)
                t.column("name", .text).notNull()
                t.column("shortCode", .text).notNull()
                t.column("colorValue", .integer).notNull()
                t.column("iconKey", .text).notNull().defaults(to: "briefcase")
                t.column("isPersonal", .boolean).notNull().defaults(to: false)
                t.column("sortOrder", .integer).notNull().defaults(to: 0)
            }
            try db.create(table: "accounts") { t in
                t.primaryKey("id", .text)
                t.column("workspaceId", .text).notNull()
                t.column("providerType", .text).notNull()
                t.column("handle", .text).notNull()
                t.column("baseUrl", .text)
                t.column("credentialsRef", .text)
            }
            try db.create(table: "projects") { t in
                t.primaryKey("id", .text)
                t.column("accountId", .text).notNull()
                t.column("name", .text).notNull()
                t.column("externalId", .text)
            }
            try db.create(table: "tickets") { t in
                t.primaryKey("id", .text)
                t.column("accountId", .text).notNull().indexed()
                t.column("projectId", .text).notNull()
                t.column("providerType", .text).notNull()
                t.column("externalKey", .text).notNull()
                t.column("externalType", .text)
                t.column("title", .text).notNull()
                t.column("body", .text).notNull()
                t.column("priorityLevel", .integer).notNull()
                t.column("statusNorm", .text).notNull()
                t.column("providerStatus", .text).notNull()
                t.column("labelsJson", .text).notNull().defaults(to: "[]")
                t.column("assignee", .text)
                t.column("url", .text)
                t.column("severity", .integer)
                t.column("createdAt", .datetime)
                t.column("updatedAt", .datetime)
                t.column("providerEntityJson", .text)
                t.column("sourceHash", .text).notNull()
            }
            try db.create(table: "comments") { t in
                t.primaryKey("id", .text)
                t.column("ticketId", .text).notNull().indexed()
                t.column("authorName", .text).notNull()
                t.column("body", .text).notNull()
                t.column("createdAt", .datetime).notNull()
                t.column("origin", .text).notNull().defaults(to: "provider")
                t.column("synced", .boolean).notNull().defaults(to: true)
            }
            try db.create(table: "activities") { t in
                t.primaryKey("id", .text)
                t.column("ticketId", .text).notNull()
                t.column("actor", .text).notNull()
                t.column("action", .text).notNull()
                t.column("at", .datetime).notNull()
                t.column("detail", .text)
                t.column("attachmentsJson", .text)
            }
            try db.create(index: "activities_by_ticket", on: "activities", columns: ["ticketId", "at"])
            try db.create(table: "translations") { t in
                t.primaryKey("ticketId", .text)
                t.column("sourceHash", .text).notNull()
                t.column("targetLang", .text).notNull()
                t.column("translatedTitle", .text).notNull()
                t.column("translatedBody", .text).notNull()
                t.column("model", .text).notNull()
                t.column("templateVersion", .text).notNull()
                t.column("createdAt", .datetime).notNull()
            }
            try db.create(table: "savedFilters") { t in
                t.primaryKey("id", .text)
                t.column("name", .text).notNull()
                t.column("filterJson", .text).notNull()
                t.column("createdAt", .datetime).notNull()
            }
            try db.create(table: "settings") { t in
                t.primaryKey("id", .integer)
                t.column("json", .text).notNull()
            }
        }
        // core_v2: when each account last synced (Dart: settings_sync_status_repository.dart). A table of its own, so the
        // account rows stay as they are for every module that writes them.
        m.registerMigration("core_v2") { db in
            try db.create(table: "accountSyncState") { t in
                t.primaryKey("accountId", .text)
                t.column("lastSyncedAt", .datetime)
            }
        }
    }
}
