import CoreDomain
import CorePersistence
import GRDB

/// Ported from: lib/core/database/database.dart (ZenTaoProfiles, DashboardSnapshots, SourceListSnapshots,
/// ZenTaoDocSnapshots, ZenTaoNotifications, TicketDrafts).
///
/// The tables this module owns, registered at the composition root (`AppDatabase.open(registrars: [ZenTaoMigrations.registrar])`)
/// under the migration id `zentao_v1`. Naming follows the drift originals, camelCase columns like `core_v1`.
public enum ZenTaoMigrations {
    public static let migrationId = "zentao_v1"

    public static let registrar: MigrationRegistrar = { migrator in
        migrator.registerMigration(migrationId) { db in
            // The raw `GET /user` profile (plus departments) per account.
            try db.create(table: "zenTaoProfiles") { t in
                t.primaryKey("accountId", .text)
                t.column("profileJson", .text).notNull()
            }
            // The last ZenTao dashboard reply (`GET /user?fields=...`) per account, stored raw so the dashboard
            // opens instantly and offline; parsed on read.
            try db.create(table: "dashboardSnapshots") { t in
                t.primaryKey("accountId", .text)
                t.column("json", .text).notNull()
                t.column("fetchedAt", .datetime).notNull()
            }
            // The last provider container list (ZenTao products / projects) per account and kind.
            try db.create(table: "sourceListSnapshots") { t in
                t.column("accountId", .text).notNull()
                t.column("kind", .text).notNull()
                t.column("json", .text).notNull()
                t.column("fetchedAt", .datetime).notNull()
                t.primaryKey(["accountId", "kind"])
            }
            // ZenTao documents, cached raw per account; `key` is `libs`, `lib:<id>`, `doc:<id>`, `history:<id>`, `pins`.
            try db.create(table: "zenTaoDocSnapshots") { t in
                t.column("accountId", .text).notNull()
                t.column("key", .text).notNull()
                t.column("json", .text).notNull()
                t.column("fetchedAt", .datetime).notNull()
                t.primaryKey(["accountId", "key"])
            }
            // ZenTao web notifications (the bell menu), per account. The server's list replaces an account's rows.
            try db.create(table: "zenTaoNotifications") { t in
                t.column("accountId", .text).notNull()
                t.column("id", .text).notNull()
                t.column("summary", .text).notNull()
                t.column("objectType", .text)
                t.column("objectId", .text)
                t.column("objectTitle", .text)
                t.column("url", .text)
                t.column("read", .boolean).notNull().defaults(to: false)
                t.column("createdAt", .datetime)
                t.primaryKey(["accountId", "id"])
            }
            // New ZenTao bugs and tasks still being written, as JSON of the draft; kind is `bug` or `task`.
            try db.create(table: "ticketDrafts") { t in
                t.primaryKey("id", .text)
                t.column("accountId", .text).notNull()
                t.column("kind", .text).notNull()
                t.column("uid", .text).notNull()
                t.column("json", .text).notNull()
                t.column("updatedAt", .datetime).notNull()
            }
        }
        // Team groups a leader follows (macOS only): the people as JSON of `[ZenTaoTeamMember]`.
        migrator.registerMigration("zentao_v2") { db in
            try db.create(table: "zenTaoTeamGroups") { t in
                t.primaryKey("id", .text)
                t.column("accountId", .text).notNull().indexed()
                t.column("name", .text).notNull()
                t.column("membersJson", .text).notNull()
                t.column("createdAt", .datetime).notNull()
            }
        }
    }
}
