import CoreDomain
import CorePersistence
import Foundation
import GRDB

/// `ZenTaoTeamGroupRepository` over the `zenTaoTeamGroups` table. Not in the Flutter app.
public final class GRDBZenTaoTeamGroupRepository: ZenTaoTeamGroupRepository, @unchecked Sendable {
    private let db: AppDatabase
    public init(db: AppDatabase) { self.db = db }

    private static func group(_ row: ZenTaoTeamGroupRow) -> ZenTaoTeamGroup? {
        guard let data = row.membersJson.data(using: .utf8), let members = try? JSONDecoder().decode([ZenTaoTeamMember].self, from: data) else { return nil }
        return ZenTaoTeamGroup(id: row.id, accountId: row.accountId, name: row.name, members: members, createdAt: row.createdAt)
    }

    public func watchGroups(accountId: String) -> AsyncStream<[ZenTaoTeamGroup]> {
        db.observe { d in
            try ZenTaoTeamGroupRow.filter(Column("accountId") == accountId).order(Column("createdAt")).fetchAll(d).compactMap(Self.group)
        }
    }

    public func save(_ group: ZenTaoTeamGroup) async -> Outcome<Void> {
        guard let data = try? JSONEncoder().encode(group.members), let json = String(data: data, encoding: .utf8) else {
            return .failure(.storage("Could not store the team group"))
        }
        let row = ZenTaoTeamGroupRow(id: group.id, accountId: group.accountId, name: group.name, membersJson: json, createdAt: group.createdAt)
        do { try await db.writer.write { try row.save($0) }; return .success(()) }
        catch { return .failure(.storage("Could not store the team group")) }
    }

    public func delete(id: String) async -> Outcome<Void> {
        do { _ = try await db.writer.write { try ZenTaoTeamGroupRow.deleteOne($0, key: id) }; return .success(()) }
        catch { return .failure(.storage("Could not delete the team group")) }
    }
}
