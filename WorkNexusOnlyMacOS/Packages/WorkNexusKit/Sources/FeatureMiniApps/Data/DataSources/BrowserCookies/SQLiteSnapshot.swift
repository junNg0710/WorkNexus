import Foundation
import GRDB

/// Ported from: lib/features/mini_apps/data/datasources/browser_cookies/sqlite_snapshot.dart
/// Runs `read` over a copy of the SQLite file at `path`. The browser may be running and holding its file locked, and a copy
/// also keeps us from ever touching the original. The write-ahead log goes along, so what the browser wrote last is there too.
func readSQLiteSnapshot<T>(_ path: String, _ read: (Database) throws -> T) throws -> T {
    let fm = FileManager.default
    let dir = fm.temporaryDirectory.appendingPathComponent("worknexus_cookies_\(UUID().uuidString)", isDirectory: true)
    try fm.createDirectory(at: dir, withIntermediateDirectories: true)
    defer { try? fm.removeItem(at: dir) }
    let copy = dir.appendingPathComponent("db.sqlite").path
    try fm.copyItem(atPath: path, toPath: copy)
    for suffix in ["-wal", "-journal"] where fm.fileExists(atPath: path + suffix) { try fm.copyItem(atPath: path + suffix, toPath: copy + suffix) }
    let queue = try DatabaseQueue(path: copy)
    defer { try? queue.close() }
    return try queue.read(read)
}
