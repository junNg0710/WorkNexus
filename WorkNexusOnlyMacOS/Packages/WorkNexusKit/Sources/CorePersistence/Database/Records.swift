import CoreDomain
import Foundation
import GRDB

// DB rows ↔ entities (lib/core/data/mappers/mappers.dart). DTOs never leave this module (rule 3.3).

struct WorkspaceRow: Codable, FetchableRecord, PersistableRecord {
    static let databaseTableName = "workspaces"
    var id: String, name: String, shortCode: String, colorValue: Int, iconKey: String, isPersonal: Bool, sortOrder: Int
    init(_ w: Workspace, sortOrder: Int = 0) {
        id = w.id; name = w.name; shortCode = w.shortCode; colorValue = w.colorValue
        iconKey = w.iconKey; isPersonal = w.isPersonal; self.sortOrder = sortOrder
    }
    var entity: Workspace { Workspace(id: id, name: name, shortCode: shortCode, colorValue: colorValue, iconKey: iconKey, isPersonal: isPersonal) }
}

struct AccountRow: Codable, FetchableRecord, PersistableRecord {
    static let databaseTableName = "accounts"
    var id: String, workspaceId: String, providerType: String, handle: String, baseUrl: String?, credentialsRef: String?
    init(_ a: Account) {
        id = a.id; workspaceId = a.workspaceId; providerType = a.providerType.rawValue
        handle = a.handle; baseUrl = a.baseUrl; credentialsRef = a.credentialsRef
    }
    var entity: Account? {
        guard let p = ProviderType(rawValue: providerType) else { return nil }
        return Account(id: id, workspaceId: workspaceId, providerType: p, handle: handle, baseUrl: baseUrl, credentialsRef: credentialsRef)
    }
}

struct ProjectRow: Codable, FetchableRecord, PersistableRecord {
    static let databaseTableName = "projects"
    var id: String, accountId: String, name: String, externalId: String?
    init(_ p: Project) { id = p.id; accountId = p.accountId; name = p.name; externalId = p.externalId }
    var entity: Project { Project(id: id, accountId: accountId, name: name, externalId: externalId) }
}

struct TicketRow: Codable, FetchableRecord, PersistableRecord {
    static let databaseTableName = "tickets"
    var id: String, accountId: String, projectId: String, providerType: String, externalKey: String
    var externalType: String?, title: String, body: String, priorityLevel: Int, statusNorm: String
    var providerStatus: String, labelsJson: String, assignee: String?, url: String?, severity: Int?
    var createdAt: Date?, updatedAt: Date?, providerEntityJson: String?, sourceHash: String

    private static let encoder: JSONEncoder = { let e = JSONEncoder(); e.dateEncodingStrategy = .iso8601; return e }()
    private static let decoder: JSONDecoder = { let d = JSONDecoder(); d.dateDecodingStrategy = .iso8601; return d }()

    init(_ t: Ticket) {
        id = t.id; accountId = t.accountId; projectId = t.projectId; providerType = t.providerType.rawValue
        externalKey = t.externalKey; externalType = t.externalType; title = t.title; body = t.body
        priorityLevel = t.priority.level; statusNorm = t.status.rawValue; providerStatus = t.providerStatus
        labelsJson = (try? String(data: Self.encoder.encode(t.labels), encoding: .utf8)) ?? "[]"
        assignee = t.assignee; url = t.url; severity = t.severity; createdAt = t.createdAt; updatedAt = t.updatedAt
        providerEntityJson = t.providerEntity.flatMap { try? Self.encoder.encode($0) }.flatMap { String(data: $0, encoding: .utf8) }
        sourceHash = t.sourceHash
    }

    var entity: Ticket? {
        guard let p = ProviderType(rawValue: providerType), let s = UnifiedStatus(rawValue: statusNorm) else { return nil }
        let labels = labelsJson.data(using: .utf8).flatMap { try? Self.decoder.decode([String].self, from: $0) } ?? []
        let entity = providerEntityJson?.data(using: .utf8).flatMap { try? Self.decoder.decode(TicketProviderEntity.self, from: $0) }
        return Ticket(id: id, accountId: accountId, projectId: projectId, providerType: p, externalKey: externalKey,
                      title: title, body: body, priority: .fromLevel(priorityLevel), status: s, providerStatus: providerStatus,
                      sourceHash: sourceHash, externalType: externalType, labels: labels, assignee: assignee, url: url,
                      severity: severity, createdAt: createdAt, updatedAt: updatedAt, providerEntity: entity)
    }
}

struct CommentRow: Codable, FetchableRecord, PersistableRecord {
    static let databaseTableName = "comments"
    var id: String, ticketId: String, authorName: String, body: String, createdAt: Date, origin: String, synced: Bool
    init(_ c: Comment) {
        id = c.id; ticketId = c.ticketId; authorName = c.authorName; body = c.body
        createdAt = c.createdAt; origin = c.origin.rawValue; synced = c.synced
    }
    var entity: Comment {
        Comment(id: id, ticketId: ticketId, authorName: authorName, body: body, createdAt: createdAt,
                origin: CommentOrigin(rawValue: origin) ?? .provider, synced: synced)
    }
}

struct ActivityRow: Codable, FetchableRecord, PersistableRecord {
    static let databaseTableName = "activities"
    var id: String, ticketId: String, actor: String, action: String, at: Date, detail: String?, attachmentsJson: String?
    init(_ e: ActivityEvent) {
        id = e.id; ticketId = e.ticketId; actor = e.actor; action = e.action; at = e.at; detail = e.detail
        attachmentsJson = e.attachments.isEmpty ? nil : (try? JSONEncoder().encode(e.attachments)).flatMap { String(data: $0, encoding: .utf8) }
    }
    var entity: ActivityEvent {
        let att = attachmentsJson?.data(using: .utf8).flatMap { try? JSONDecoder().decode([String].self, from: $0) } ?? []
        return ActivityEvent(id: id, ticketId: ticketId, actor: actor, action: action, at: at, detail: detail, attachments: att)
    }
}
