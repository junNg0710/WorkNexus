import CoreDomain
import GRDB

public final class GRDBWorkspaceRepository: WorkspaceRepository {
    private let db: AppDatabase
    public init(db: AppDatabase) { self.db = db }

    public func watchWorkspaces() -> AsyncStream<[Workspace]> {
        db.observe { try WorkspaceRow.order(Column("sortOrder"), Column("name")).fetchAll($0).map(\.entity) }
    }
    public func watchAccounts() -> AsyncStream<[Account]> {
        db.observe { Account.sort(try AccountRow.fetchAll($0).compactMap(\.entity)) }
    }
    public func watchProjects() -> AsyncStream<[Project]> {
        db.observe { try ProjectRow.order(Column("name")).fetchAll($0).map(\.entity) }
    }
    public func createWorkspace(_ w: Workspace) async -> Outcome<Void> {
        await guarded {
            try await self.db.writer.write { d in
                let next = (try Int.fetchOne(d, sql: "SELECT COALESCE(MAX(sortOrder), -1) + 1 FROM workspaces")) ?? 0
                try WorkspaceRow(w, sortOrder: next).insert(d)
            }
        }
    }
    public func updateWorkspace(_ w: Workspace) async -> Outcome<Void> {
        await guarded {
            try await self.db.writer.write { d in
                try d.execute(sql: "UPDATE workspaces SET name=?, shortCode=?, colorValue=?, iconKey=?, isPersonal=? WHERE id=?",
                              arguments: [w.name, w.shortCode, w.colorValue, w.iconKey, w.isPersonal, w.id])
            }
        }
    }
    public func upsertAccount(_ a: Account) async -> Outcome<Void> {
        await guarded { try await self.db.writer.write { try AccountRow(a).save($0) } }
    }
    public func deleteAccount(id: String) async -> Outcome<Void> {
        await guarded {
            try await self.db.writer.write { d in
                try d.execute(sql: "DELETE FROM tickets WHERE accountId = ?", arguments: [id])
                try d.execute(sql: "DELETE FROM projects WHERE accountId = ?", arguments: [id])
                try d.execute(sql: "DELETE FROM accounts WHERE id = ?", arguments: [id])
            }
        }
    }
    public func upsertProjects(_ projects: [Project]) async -> Outcome<Void> {
        await guarded { try await self.db.writer.write { d in for p in projects { try ProjectRow(p).save(d) } } }
    }
}
