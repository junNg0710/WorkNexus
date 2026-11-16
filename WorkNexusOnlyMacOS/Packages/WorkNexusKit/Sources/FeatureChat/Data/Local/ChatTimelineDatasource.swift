import Foundation
import CorePersistence
import GRDB

/// How a batch of stored messages relates to the timeline (the run of history reaching the newest message).
/// Ported from: lib/features/chat/data/datasources/chat_timeline_datasource.dart
enum MessageLink {
    /// Rows keep whatever `detached` they have (new rows start in the timeline).
    case keep
    /// Rows join the timeline.
    case linked
    /// New rows start detached (a jump window); one already in the timeline stays there.
    case detached
}

/// Timeline / jump-window bookkeeping over `chatMessages.detached`.
struct ChatTimelineDatasource: Sendable {
    let db: AppDatabase

    /// A page that does not touch the stored timeline at `index - 1` is cut off from it: everything below goes detached.
    func detachIfCutOffBelow(_ accountId: String, _ cgid: String, _ index: Int) async throws {
        try await db.writer.write { d in
            let joined = try Int.fetchOne(d, sql: "SELECT 1 FROM chatMessages WHERE accountId=? AND cgid=? AND detached=0 AND messageIndex=? LIMIT 1",
                                          arguments: [accountId, cgid, index - 1])
            if joined != nil { return }
            try d.execute(sql: "UPDATE chatMessages SET detached=1 WHERE accountId=? AND cgid=? AND detached=0 AND messageIndex<?",
                          arguments: [accountId, cgid, index])
        }
    }

    /// Joins the window [from, to] to the timeline when the timeline starts right above it (or is empty); returns the
    /// number of timeline messages from `from` up, nil when the window cannot join yet.
    func joinWindow(_ accountId: String, _ cgid: String, from: Int, to: Int) async throws -> Int? {
        try await db.writer.write { d in
            let newer = try Int.fetchAll(d, sql: "SELECT messageIndex FROM chatMessages WHERE accountId=? AND cgid=? AND detached=0 AND messageIndex>?",
                                         arguments: [accountId, cgid, to])
            let reaches = newer.isEmpty || newer.contains(to + 1)
            guard reaches else { return nil }
            try d.execute(sql: "UPDATE chatMessages SET detached=0 WHERE accountId=? AND cgid=? AND messageIndex>=?", arguments: [accountId, cgid, from])
            return try Int.fetchOne(d, sql: "SELECT COUNT(*) FROM chatMessages WHERE accountId=? AND cgid=? AND detached=0 AND (messageIndex>=? OR messageIndex IS NULL)",
                                    arguments: [accountId, cgid, from]) ?? 0
        }
    }

    struct Extent: Sendable { var count: Int; var oldestServerId: Int?; var oldestSentAt: Date?; var reachesStart: Bool }

    func extent(_ accountId: String, _ cgid: String) async throws -> Extent {
        try await db.writer.read { d in
            let args: StatementArguments = [accountId, cgid]
            let count = try Int.fetchOne(d, sql: "SELECT COUNT(*) FROM chatMessages WHERE accountId=? AND cgid=? AND detached=0 AND serverId IS NOT NULL", arguments: args) ?? 0
            let oldest = try Row.fetchOne(d, sql: "SELECT serverId, sentAt, messageIndex FROM chatMessages WHERE accountId=? AND cgid=? AND detached=0 AND serverId IS NOT NULL ORDER BY serverId ASC LIMIT 1", arguments: args)
            let index: Int? = oldest?["messageIndex"]
            return Extent(count: count, oldestServerId: oldest?["serverId"], oldestSentAt: oldest?["sentAt"], reachesStart: (index ?? Int.max) <= 1)
        }
    }

    /// How many consecutive stored messages (up to `limit`) sit right next to `index`, older or newer.
    func countAdjacent(_ accountId: String, _ cgid: String, index: Int, older: Bool, limit: Int) async throws -> Int {
        try await db.writer.read { d in
            let (lo, hi) = older ? (index - limit, index - 1) : (index + 1, index + limit)
            let stored = Set(try Int.fetchAll(d, sql: "SELECT DISTINCT messageIndex FROM chatMessages WHERE accountId=? AND cgid=? AND messageIndex BETWEEN ? AND ?",
                                              arguments: [accountId, cgid, lo, hi]))
            let step = older ? -1 : 1
            var n = 0
            while n < limit, stored.contains(index + step * (n + 1)) { n += 1 }
            return n
        }
    }
}
