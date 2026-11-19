import Foundation
import GRDB

/// Ported from: lib/core/database/database.dart. SQLite (WAL) is the single source of truth (rule 16).
/// Feature/tool modules own their tables and register them via `MigrationRegistrar` at the composition root.
public typealias MigrationRegistrar = @Sendable (inout DatabaseMigrator) -> Void

public final class AppDatabase: @unchecked Sendable {
    public let writer: any DatabaseWriter

    public init(writer: any DatabaseWriter, registrars: [MigrationRegistrar] = []) throws {
        self.writer = writer
        var migrator = DatabaseMigrator()
        CoreMigrations.register(&migrator)
        for r in registrars { r(&migrator) }
        try migrator.migrate(writer)
    }

    /// `~/Library/Application Support/<bundle>/<name>.sqlite`
    public static func open(name: String = "worknexus", registrars: [MigrationRegistrar] = []) throws -> AppDatabase {
        let dir = try FileManager.default.url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
            .appendingPathComponent(Bundle.main.bundleIdentifier ?? "com.worknexus.macos", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        var config = Configuration()
        config.prepareDatabase { db in
            try db.execute(sql: "PRAGMA synchronous=NORMAL")
        }
        let pool = try DatabasePool(path: dir.appendingPathComponent("\(name).sqlite").path, configuration: config)
        return try AppDatabase(writer: pool, registrars: registrars)
    }

    /// A database at an explicit file (tests, demo runs: `WN_DB_PATH`); its folder is created on demand.
    public static func open(path: URL, registrars: [MigrationRegistrar] = []) throws -> AppDatabase {
        try FileManager.default.createDirectory(at: path.deletingLastPathComponent(), withIntermediateDirectories: true)
        var config = Configuration()
        config.prepareDatabase { db in try db.execute(sql: "PRAGMA synchronous=NORMAL") }
        return try AppDatabase(writer: try DatabasePool(path: path.path, configuration: config), registrars: registrars)
    }

    /// The database file; nil for an in-memory database.
    public var fileURL: URL? {
        let path = writer.path
        return path.isEmpty || path == ":memory:" || path.hasPrefix("file::memory:") ? nil : URL(fileURLWithPath: path)
    }

    public static func inMemory(registrars: [MigrationRegistrar] = []) throws -> AppDatabase {
        try AppDatabase(writer: try DatabaseQueue(), registrars: registrars)
    }
}

public extension AppDatabase {
    /// Re-runs `fetch` whenever the tables it reads change; ends when the consumer cancels.
    func observe<T: Sendable>(_ fetch: @escaping @Sendable (Database) throws -> T) -> AsyncStream<T> {
        stream(ValueObservation.tracking(fetch))
    }

    /// `observe` for a fetch that always reads the same tables (no query that depends on what an earlier one found): it
    /// reads beside the writes instead of holding them up while it runs, which a large read (every ticket) otherwise
    /// does after each write, so a burst of small writes waited for one whole read each.
    func observeConstantRegion<T: Sendable>(_ fetch: @escaping @Sendable (Database) throws -> T) -> AsyncStream<T> {
        stream(ValueObservation.trackingConstantRegion(fetch))
    }

    private func stream<T: Sendable>(_ obs: ValueObservation<ValueReducers.Fetch<T>>) -> AsyncStream<T> {
        AsyncStream { cont in
            let task = Task {
                do { for try await v in obs.values(in: writer) { cont.yield(v) } } catch {}
                cont.finish()
            }
            cont.onTermination = { _ in task.cancel() }
        }
    }
}
