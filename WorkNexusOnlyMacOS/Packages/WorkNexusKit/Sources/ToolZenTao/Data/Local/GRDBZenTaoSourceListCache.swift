import CoreDomain
import CorePersistence
import Foundation
import GRDB

/// Ported from: lib/shared/sync/data/source_list_cache.dart
/// Drift/GRDB access to the last-fetched ZenTao container lists (`sourceListSnapshots`), so the sidebar tree can
/// paint from disk on launch and refresh from the network behind it.
public final class GRDBZenTaoSourceListCache: ZenTaoSourceListCache, @unchecked Sendable {
    private static let productsKind = "products"
    private static let projectsKind = "projects"
    private let db: AppDatabase

    public init(db: AppDatabase) { self.db = db }

    public func readProducts(accountId: String) async -> [ProviderProduct]? {
        // Snapshots saved before the grouping was kept have no program / line: those products read back
        // ungrouped until the next fetch.
        await read(accountId, Self.productsKind)?.map {
            ProviderProduct(id: $0.id, name: $0.name, accountId: accountId, programId: $0.extra["programId"],
                            programName: $0.extra["programName"], lineId: $0.extra["lineId"], lineName: $0.extra["lineName"])
        }
    }

    public func readProjects(accountId: String) async -> [ProviderProject]? {
        // Older snapshots have no program: read back ungrouped.
        await read(accountId, Self.projectsKind)?.map {
            ProviderProject(id: $0.id, name: $0.name, accountId: accountId, programId: $0.extra["programId"], programName: $0.extra["programName"])
        }
    }

    /// Program names a fetch could not get (`/programs` failing this time) from the last list that had them, so
    /// the grouping does not come and go.
    public func withKnownProgramNames(accountId: String, projects: [ProviderProject]) async -> [ProviderProject] {
        guard projects.contains(where: { $0.programId != nil && $0.programName == nil }) else { return projects }
        let cached = await readProjects(accountId: accountId) ?? []
        var known: [String: String] = [:]
        for p in cached { if let id = p.programId, let name = p.programName { known[id] = name } }
        return projects.map {
            ProviderProject(id: $0.id, name: $0.name, accountId: $0.accountId, programId: $0.programId,
                            programName: $0.programName ?? $0.programId.flatMap { known[$0] })
        }
    }

    public func saveProducts(accountId: String, items: [ProviderProduct]) async {
        await save(accountId, Self.productsKind, items.map { p in
            var j: [String: String] = ["id": p.id, "name": p.name]
            if let v = p.programId { j["programId"] = v }
            if let v = p.programName { j["programName"] = v }
            if let v = p.lineId { j["lineId"] = v }
            if let v = p.lineName { j["lineName"] = v }
            return j
        })
    }

    public func saveProjects(accountId: String, items: [ProviderProject]) async {
        await save(accountId, Self.projectsKind, items.map { p in
            var j: [String: String] = ["id": p.id, "name": p.name]
            if let v = p.programId { j["programId"] = v }
            if let v = p.programName { j["programName"] = v }
            return j
        })
    }

    private func read(_ accountId: String, _ kind: String) async -> [(id: String, name: String, extra: [String: String])]? {
        guard let row = try? await db.writer.read({ try SourceListSnapshotRow.fetchOne($0, key: ["accountId": accountId, "kind": kind]) }) else { return nil }
        // A snapshot is only a head start for the network fetch that follows, so an unreadable one is a cache
        // miss rather than an error.
        guard let list = try? jsonDecode(row.json) as? [Any] else { return nil }
        var out: [(String, String, [String: String])] = []
        for item in list {
            guard let e = asMap(item), let id = e["id"] as? String, let name = e["name"] as? String else { return nil }
            var extra: [String: String] = [:]
            for (k, v) in e where k != "id" && k != "name" { if let s = v as? String { extra[k] = s } }
            out.append((id, name, extra))
        }
        return out
    }

    private func save(_ accountId: String, _ kind: String, _ items: [[String: String]]) async {
        let row = SourceListSnapshotRow(accountId: accountId, kind: kind, json: jsonEncode(items), fetchedAt: Date())
        try? await db.writer.write { try row.save($0) }
    }
}
