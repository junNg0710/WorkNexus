import CorePersistence
import GRDB

/// Ported from: lib/core/database/database.dart (`MiniApps`, `MiniAppPermissions`)
/// The feature's own tables, registered by the composition root through `AppDatabase.open(registrars:)`.
public enum MiniAppsMigrations {
    public static let migrationId = "miniapps_v1"
    public static let nativeAppsMigrationId = "miniapps_v2"

    public static let registrar: MigrationRegistrar = { migrator in
        migrator.registerMigration(migrationId) { db in
            // Web pages the user added to the app rail, in rail order.
            try db.create(table: "miniApps") { t in
                t.primaryKey("id", .text)
                t.column("name", .text).notNull()
                t.column("url", .text).notNull()
                t.column("iconPath", .text)
                t.column("lastUrl", .text)
                t.column("position", .integer).notNull().defaults(to: 0)
            }
            // What the user allowed or blocked for a mini app's page: one row per app and kind; no row means ask.
            try db.create(table: "miniAppPermissions") { t in
                t.column("miniAppId", .text).notNull()
                t.column("kind", .text).notNull()
                t.column("allowed", .boolean).notNull()
                t.primaryKey(["miniAppId", "kind"])
            }
        }
        // New feature, no Dart counterpart: Mac apps the user put on the rail, in rail order.
        migrator.registerMigration(nativeAppsMigrationId) { db in
            try db.create(table: "nativeApps") { t in
                t.primaryKey("id", .text)
                t.column("name", .text).notNull()
                t.column("bundleId", .text).notNull().unique()
                t.column("path", .text).notNull()
                t.column("position", .integer).notNull().defaults(to: 0)
            }
        }
    }
}
