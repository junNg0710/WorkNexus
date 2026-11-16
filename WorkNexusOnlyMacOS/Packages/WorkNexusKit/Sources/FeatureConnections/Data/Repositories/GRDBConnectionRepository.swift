import CoreDomain
import CorePersistence
import Foundation
import GRDB

/// Ported from: lib/features/connections/data/local_connection_repository.dart
/// Accounts and workspaces over the core tables, with the cascade the Flutter app does by hand: removing an
/// account (or a whole workspace) also drops its projects, tickets, the tickets' comments / activity /
/// translations and the account's ZenTao profile. Tables owned by a module that is not registered are skipped.
public final class GRDBConnectionRepository: ConnectionRepository {
    private let db: AppDatabase
    public init(db: AppDatabase) { self.db = db }

    public func addAccount(_ account: Account) async -> Outcome<Void> {
        await guarded {
            try await self.db.writer.write { d in
                try d.execute(sql: """
                    INSERT INTO accounts (id, workspaceId, providerType, handle, baseUrl, credentialsRef) VALUES (?, ?, ?, ?, ?, ?)
                    ON CONFLICT(id) DO UPDATE SET workspaceId = excluded.workspaceId, providerType = excluded.providerType,
                        handle = excluded.handle, baseUrl = excluded.baseUrl, credentialsRef = excluded.credentialsRef
                    """, arguments: [account.id, account.workspaceId, account.providerType.rawValue, account.handle,
                                     account.baseUrl, account.credentialsRef])
            }
        }
    }

    public func addWorkspace(_ w: Workspace) async -> Outcome<Void> {
        await guarded {
            try await self.db.writer.write { d in
                // A new workspace goes last (sortOrder = how many there are); an existing id keeps its place.
                let count = try Int.fetchOne(d, sql: "SELECT COUNT(*) FROM workspaces") ?? 0
                try d.execute(sql: """
                    INSERT INTO workspaces (id, name, shortCode, colorValue, iconKey, isPersonal, sortOrder) VALUES (?, ?, ?, ?, ?, ?, ?)
                    ON CONFLICT(id) DO UPDATE SET name = excluded.name, shortCode = excluded.shortCode,
                        colorValue = excluded.colorValue, iconKey = excluded.iconKey, isPersonal = excluded.isPersonal
                    """, arguments: [w.id, w.name, w.shortCode, w.colorValue, w.iconKey, w.isPersonal, count])
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

    public func removeAccount(id: String) async -> Outcome<Void> {
        await guarded { try await self.db.writer.write { d in try Self.purge(accountIds: [id], in: d) } }
    }

    public func deleteWorkspace(id: String) async -> Outcome<[String]> {
        await guarded {
            try await self.db.writer.write { d in
                let rows = try Row.fetchAll(d, sql: "SELECT id, credentialsRef FROM accounts WHERE workspaceId = ?", arguments: [id])
                let ids: [String] = rows.map { $0["id"] }
                let refs: [String] = rows.compactMap { $0["credentialsRef"] }
                try Self.purge(accountIds: ids, in: d)
                try d.execute(sql: "DELETE FROM workspaces WHERE id = ?", arguments: [id])
                return refs
            }
        }
    }

    /// Everything the accounts own, children first; one transaction (the caller's `write`).
    private static func purge(accountIds: [String], in d: Database) throws {
        guard !accountIds.isEmpty else { return }
        let marks = databaseQuestionMarks(count: accountIds.count)
        let args = StatementArguments(accountIds)
        if try d.tableExists("zenTaoProfiles") {
            try d.execute(sql: "DELETE FROM zenTaoProfiles WHERE accountId IN (\(marks))", arguments: args)
        }
        let ticketIds = "SELECT id FROM tickets WHERE accountId IN (\(marks))"
        for table in ["comments", "activities", "translations"] {
            try d.execute(sql: "DELETE FROM \(table) WHERE ticketId IN (\(ticketIds))", arguments: args)
        }
        try d.execute(sql: "DELETE FROM tickets WHERE accountId IN (\(marks))", arguments: args)
        try d.execute(sql: "DELETE FROM projects WHERE accountId IN (\(marks))", arguments: args)
        try d.execute(sql: "DELETE FROM accounts WHERE id IN (\(marks))", arguments: args)
    }
}
