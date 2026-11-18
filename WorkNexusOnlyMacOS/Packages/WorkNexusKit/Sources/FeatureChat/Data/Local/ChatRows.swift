import Foundation
import GRDB

/// Flat rows of the chat tables (data-layer DTOs; they never leave `Data/`). Decoded by column name from raw SQL.
struct ChatConversationRow: Equatable, Sendable {
    var accountId: String, gid: String, type: String, name: String
    var lastActiveAt: Date?
    var lastMessageId: Int?
    var lastMessageIndex: Int, lastReadIndex: Int
    var hidden: Bool, archived: Bool
    var pinnedJson: String
    var avatarJson: String?
    var starred: Bool, muted: Bool
    var adminsJson: String, committers: String
    var category: String
    var adminInvite: Bool, isPublic: Bool
    var ownedBy: String?
    var createdAt: Date?

    init(row r: Row, prefix: String = "") {
        accountId = r[prefix + "accountId"]; gid = r[prefix + "gid"]; type = r[prefix + "type"]; name = r[prefix + "name"]
        lastActiveAt = r[prefix + "lastActiveAt"]; lastMessageId = r[prefix + "lastMessageId"]
        lastMessageIndex = r[prefix + "lastMessageIndex"]; lastReadIndex = r[prefix + "lastReadIndex"]
        hidden = r[prefix + "hidden"]; archived = r[prefix + "archived"]; pinnedJson = r[prefix + "pinnedJson"]
        avatarJson = r[prefix + "avatarJson"]; starred = r[prefix + "starred"]; muted = r[prefix + "muted"]
        adminsJson = r[prefix + "adminsJson"]; committers = r[prefix + "committers"]
        category = r[prefix + "category"]; adminInvite = r[prefix + "adminInvite"]; isPublic = r[prefix + "isPublic"]
        ownedBy = r[prefix + "ownedBy"]; createdAt = r[prefix + "createdAt"]
    }
}

struct ChatMessageRow: Equatable, Sendable {
    var accountId: String, gid: String, cgid: String
    var serverId: Int?, messageIndex: Int?
    var senderId: Int
    var sentAt: Date
    var contentType: String, content: String, sendState: String
    var replyToId: Int?
    var deleted: Bool, detached: Bool, broadcast: Bool
    var searchText: String?

    init(row r: Row, prefix: String = "") {
        accountId = r[prefix + "accountId"]; gid = r[prefix + "gid"]; cgid = r[prefix + "cgid"]
        serverId = r[prefix + "serverId"]; messageIndex = r[prefix + "messageIndex"]; senderId = r[prefix + "senderId"]
        sentAt = r[prefix + "sentAt"]; contentType = r[prefix + "contentType"]; content = r[prefix + "content"]
        sendState = r[prefix + "sendState"]; replyToId = r[prefix + "replyToId"]
        deleted = r[prefix + "deleted"]; detached = r[prefix + "detached"]; broadcast = r[prefix + "broadcast"]
        searchText = r[prefix + "searchText"]
    }
}

struct ChatUserRow: Equatable, Sendable {
    var accountId: String
    var userId: Int
    var account: String, realname: String
    var avatar: String?
    var deleted: Bool
    var email: String?, mobile: String?, phone: String?, role: String?, status: String?

    init(row r: Row) {
        accountId = r["accountId"]; userId = r["userId"]; account = r["account"]; realname = r["realname"]
        avatar = r["avatar"]; deleted = r["deleted"]; email = r["email"]; mobile = r["mobile"]
        phone = r["phone"]; role = r["role"]; status = r["status"]
    }
}

struct ChatAccountRow: Equatable, Sendable {
    var accountId: String
    var serverUrl: String?, pinnedFingerprint: String?
    var userId: Int?
    init(row r: Row) { accountId = r["accountId"]; serverUrl = r["serverUrl"]; pinnedFingerprint = r["pinnedFingerprint"]; userId = r["userId"] }
}

/// A set of column values to write; `nil` array elements are not present (Dart `Value.absent`), `.null` writes SQL NULL.
struct ColumnValues {
    private(set) var pairs: [(String, DatabaseValue)] = []
    private var raw: [String: Any] = [:]

    mutating func set(_ column: String, _ value: (any DatabaseValueConvertible)?) {
        pairs.removeAll { $0.0 == column }
        pairs.append((column, value?.databaseValue ?? .null))
        raw[column] = value
    }
    func has(_ column: String) -> Bool { raw.keys.contains(column) }
    func string(_ c: String) -> String? { raw[c] as? String }
    func int(_ c: String) -> Int? { raw[c] as? Int }
    func date(_ c: String) -> Date? { raw[c] as? Date }
    func bool(_ c: String) -> Bool? { raw[c] as? Bool }

    /// `INSERT … ON CONFLICT(keys) DO UPDATE SET <present non-key columns>`; `merge` overrides a column's update expression.
    func upsertSQL(table: String, keys: [String], merge: [String: String] = [:], insertOrIgnore: Bool = false) -> (sql: String, args: StatementArguments) {
        let cols = pairs.map(\.0)
        let marks = cols.map { _ in "?" }.joined(separator: ",")
        if insertOrIgnore {
            return ("INSERT OR IGNORE INTO \(table) (\(cols.joined(separator: ","))) VALUES (\(marks))", StatementArguments(pairs.map(\.1)))
        }
        let updates = cols.filter { !keys.contains($0) }.map { c in "\(c) = \(merge[c] ?? "excluded.\(c)")" }
        let tail = updates.isEmpty ? "DO NOTHING" : "DO UPDATE SET \(updates.joined(separator: ", "))"
        return ("INSERT INTO \(table) (\(cols.joined(separator: ","))) VALUES (\(marks)) ON CONFLICT(\(keys.joined(separator: ","))) \(tail)",
                StatementArguments(pairs.map(\.1)))
    }
}
