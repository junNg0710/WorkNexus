import CoreDomain
import CorePersistence
import Foundation
import GRDB

/// Ported from: lib/features/ticket_editor/data/{mappers/ticket_draft_mapper,repositories/local_ticket_draft_repository,datasources/ticket_draft_local_datasource}.dart
/// `ZenTaoTicketDraftRepository` over the `ticketDrafts` table. A draft's added files are left out: only their
/// bytes exist, and a repro video would bloat the database.
public final class GRDBZenTaoTicketDraftRepository: ZenTaoTicketDraftRepository, @unchecked Sendable {
    private let db: AppDatabase
    public init(db: AppDatabase) { self.db = db }

    public func watchAll() -> AsyncStream<[ZenTaoSavedDraft]> {
        db.observe { d in try TicketDraftRow.order(Column("updatedAt").desc).fetchAll(d).compactMap(TicketDraftMapper.fromRow) }
    }

    public func read(id: String) async -> Outcome<ZenTaoSavedDraft?> {
        await storage { try await self.db.writer.read { try TicketDraftRow.fetchOne($0, key: id) }.flatMap(TicketDraftMapper.fromRow) }
    }

    public func save(_ draft: ZenTaoSavedDraft) async -> Outcome<Void> {
        let row = TicketDraftMapper.toRow(draft)
        return await storage { try await self.db.writer.write { try row.save($0) } }
    }

    public func delete(id: String) async -> Outcome<Void> {
        await storage { _ = try await self.db.writer.write { try TicketDraftRow.deleteOne($0, key: id) } }
    }

    private func storage<T>(_ run: () async throws -> T) async -> Outcome<T> {
        do { return .success(try await run()) } catch { return .failure(.storage("Could not keep the draft")) }
    }
}

/// `ZenTaoSavedDraft` <-> `TicketDraftRow`.
enum TicketDraftMapper {
    private static let bug = "bug", task = "task"

    private static let encoder: JSONEncoder = { let e = JSONEncoder(); e.dateEncodingStrategy = .iso8601; return e }()
    private static let decoder: JSONDecoder = { let d = JSONDecoder(); d.dateDecodingStrategy = .iso8601; return d }()

    static func toRow(_ draft: ZenTaoSavedDraft) -> TicketDraftRow {
        let (kind, json): (String, JSON)
        switch draft.content {
        case .bug(let d): (kind, json) = (bug, bugJson(d))
        case .task(let d): (kind, json) = (task, taskJson(d))
        }
        return TicketDraftRow(id: draft.id, accountId: draft.accountId, kind: kind, uid: draft.uid, json: jsonEncode(json), updatedAt: draft.updatedAt)
    }

    /// Nil for a row this build cannot read (an unknown kind, broken JSON).
    static func fromRow(_ row: TicketDraftRow) -> ZenTaoSavedDraft? {
        guard let json = asMap(try? jsonDecode(row.json)) else { return nil }
        let content: ZenTaoSavedDraft.Content
        switch row.kind {
        case bug: content = .bug(bugFrom(json))
        case task: content = .task(taskFrom(json))
        default: return nil
        }
        return ZenTaoSavedDraft(id: row.id, accountId: row.accountId, uid: row.uid, updatedAt: row.updatedAt, content: content)
    }

    private static func filesJson(_ files: [TicketAttachment]) -> [Any] {
        files.compactMap { (try? encoder.encode($0)).flatMap { try? jsonDecode($0) } }
    }

    private static func files(_ v: Any?) -> [TicketAttachment] {
        (v as? [Any] ?? []).compactMap { item in
            guard asMap(item) != nil else { return nil }
            return try? decoder.decode(TicketAttachment.self, from: Data(jsonEncode(item).utf8))
        }
    }

    private static func bugJson(_ d: BugDraft) -> JSON {
        ["product": d.product, "branch": d.branch, "module": d.module, "project": d.project, "execution": d.execution,
         "plan": d.plan, "openedBuilds": d.openedBuilds, "assignedTo": d.assignedTo, "deadline": d.deadline,
         "type": d.type, "os": d.os, "browser": d.browser, "title": d.title, "color": d.color, "severity": d.severity,
         "pri": d.pri, "steps": d.steps, "story": d.story, "task": d.task, "mailto": d.mailto, "keywords": d.keywords,
         "files": filesJson(d.files)]
    }

    private static func bugFrom(_ j: JSON) -> BugDraft {
        var d = BugDraft(product: string(j["product"]) ?? "0")
        d.branch = string(j["branch"]) ?? d.branch
        d.module = string(j["module"]) ?? d.module
        d.project = string(j["project"]) ?? d.project
        d.execution = string(j["execution"]) ?? d.execution
        d.plan = string(j["plan"]) ?? d.plan
        d.openedBuilds = strings(j["openedBuilds"]) ?? d.openedBuilds
        d.assignedTo = string(j["assignedTo"]) ?? d.assignedTo
        d.deadline = string(j["deadline"]) ?? d.deadline
        d.type = string(j["type"]) ?? d.type
        d.os = strings(j["os"]) ?? d.os
        d.browser = strings(j["browser"]) ?? d.browser
        d.title = string(j["title"]) ?? d.title
        d.color = string(j["color"]) ?? d.color
        d.severity = int(j["severity"]) ?? d.severity
        d.pri = int(j["pri"]) ?? d.pri
        d.steps = string(j["steps"]) ?? d.steps
        d.story = string(j["story"]) ?? d.story
        d.task = string(j["task"]) ?? d.task
        d.mailto = strings(j["mailto"]) ?? d.mailto
        d.keywords = string(j["keywords"]) ?? d.keywords
        d.files = files(j["files"])
        return d
    }

    private static func taskJson(_ d: TaskDraft) -> JSON {
        ["execution": d.execution, "module": d.module, "story": d.story, "parent": d.parent, "name": d.name,
         "type": d.type, "pri": d.pri, "estimate": d.estimate, "left": d.left, "consumed": d.consumed,
         "status": d.status, "assignedTo": d.assignedTo, "estStarted": d.estStarted, "deadline": d.deadline,
         "desc": d.desc, "color": d.color, "mailto": d.mailto, "keywords": d.keywords, "files": filesJson(d.files)]
    }

    private static func taskFrom(_ j: JSON) -> TaskDraft {
        var d = TaskDraft(execution: string(j["execution"]) ?? "0")
        d.module = string(j["module"]) ?? d.module
        d.story = string(j["story"]) ?? d.story
        d.parent = string(j["parent"]) ?? d.parent
        d.name = string(j["name"]) ?? d.name
        d.type = string(j["type"]) ?? d.type
        d.pri = int(j["pri"]) ?? d.pri
        d.estimate = double(j["estimate"]) ?? d.estimate
        d.left = double(j["left"]) ?? d.left
        d.consumed = double(j["consumed"]) ?? d.consumed
        d.status = string(j["status"]) ?? d.status
        d.assignedTo = string(j["assignedTo"]) ?? d.assignedTo
        d.estStarted = string(j["estStarted"]) ?? d.estStarted
        d.deadline = string(j["deadline"]) ?? d.deadline
        d.desc = string(j["desc"]) ?? d.desc
        d.color = string(j["color"]) ?? d.color
        d.mailto = strings(j["mailto"]) ?? d.mailto
        d.keywords = string(j["keywords"]) ?? d.keywords
        d.files = files(j["files"])
        return d
    }

    private static func string(_ v: Any?) -> String? { v as? String }
    private static func int(_ v: Any?) -> Int? { (v as? NSNumber).flatMap { CFGetTypeID($0) != CFBooleanGetTypeID() ? $0.intValue : nil } }
    private static func double(_ v: Any?) -> Double? { (v as? NSNumber).flatMap { CFGetTypeID($0) != CFBooleanGetTypeID() ? $0.doubleValue : nil } }
    private static func strings(_ v: Any?) -> [String]? { (v as? [Any])?.compactMap { $0 as? String } }
}
