/// Ported from: lib/core/database/database.dart (ZenTaoProfiles ... TicketDrafts rows)
import CoreDomain
import Foundation
import GRDB

// DB rows of the tables `ZenTaoMigrations` creates. Rows never leave the Data layer (rule 3.3).

struct ZenTaoProfileRow: Codable, FetchableRecord, PersistableRecord, Sendable {
    static let databaseTableName = "zenTaoProfiles"
    var accountId: String
    var profileJson: String
}

struct DashboardSnapshotRow: Codable, FetchableRecord, PersistableRecord, Sendable {
    static let databaseTableName = "dashboardSnapshots"
    var accountId: String
    var json: String
    var fetchedAt: Date
}

struct SourceListSnapshotRow: Codable, FetchableRecord, PersistableRecord, Sendable {
    static let databaseTableName = "sourceListSnapshots"
    var accountId: String
    var kind: String
    var json: String
    var fetchedAt: Date
}

struct ZenTaoDocSnapshotRow: Codable, FetchableRecord, PersistableRecord, Sendable {
    static let databaseTableName = "zenTaoDocSnapshots"
    var accountId: String
    var key: String
    var json: String
    var fetchedAt: Date
}

struct ZenTaoNotificationRow: Codable, FetchableRecord, PersistableRecord, Sendable {
    static let databaseTableName = "zenTaoNotifications"
    var accountId: String
    var id: String
    var summary: String
    var objectType: String?
    var objectId: String?
    var objectTitle: String?
    var url: String?
    var read: Bool
    var createdAt: Date?

    init(_ n: ZenTaoNotification) {
        accountId = n.accountId; id = n.id; summary = n.summary; objectType = n.objectType; objectId = n.objectId
        objectTitle = n.objectTitle; url = n.url; read = n.read; createdAt = n.createdAt
    }

    var entity: ZenTaoNotification {
        ZenTaoNotification(accountId: accountId, id: id, summary: summary, objectType: objectType, objectId: objectId,
                           objectTitle: objectTitle, url: url, read: read, createdAt: createdAt)
    }
}

struct TicketDraftRow: Codable, FetchableRecord, PersistableRecord, Sendable {
    static let databaseTableName = "ticketDrafts"
    var id: String
    var accountId: String
    var kind: String
    var uid: String
    var json: String
    var updatedAt: Date
}
