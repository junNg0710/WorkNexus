import CoreDomain
import Foundation

/// Ported from: lib/shared/sync/data/source_list_cache.dart
/// The last-fetched provider container lists (ZenTao products / projects), so the sidebar tree can paint from
/// disk on launch and refresh from the network behind it. Storage is the injected `SourceListSnapshotStore`.
public struct SourceListCache: Sendable {
    private static let products = "products", projects = "projects"
    private let store: SourceListSnapshotStore
    public init(store: SourceListSnapshotStore = InMemorySourceListSnapshotStore()) { self.store = store }

    public func readProducts(_ accountId: String) async -> [ProviderProduct]? {
        await read(accountId, Self.products)?.map {
            ProviderProduct(id: $0.id, name: $0.name, accountId: accountId, programId: $0.extra["programId"],
                            programName: $0.extra["programName"], lineId: $0.extra["lineId"], lineName: $0.extra["lineName"])
        }
    }

    public func readProjects(_ accountId: String) async -> [ProviderProject]? {
        await read(accountId, Self.projects)?.map {
            ProviderProject(id: $0.id, name: $0.name, accountId: accountId, programId: $0.extra["programId"],
                            programName: $0.extra["programName"])
        }
    }

    /// Program names a fetch could not get (`/programs` failing this time) from the last list that had them.
    public func withKnownProgramNames(_ accountId: String, _ projects: [ProviderProject]) async -> [ProviderProject] {
        guard projects.contains(where: { $0.programId != nil && $0.programName == nil }) else { return projects }
        let cached = await readProjects(accountId) ?? []
        var known: [String: String] = [:]
        for p in cached { if let id = p.programId, let n = p.programName { known[id] = n } }
        return projects.map {
            ProviderProject(id: $0.id, name: $0.name, accountId: $0.accountId, programId: $0.programId,
                            programName: $0.programName ?? $0.programId.flatMap { known[$0] })
        }
    }

    public func saveProducts(_ accountId: String, _ items: [ProviderProduct]) async {
        await save(accountId, Self.products, items.map { p in
            clean(["id": p.id, "name": p.name, "programId": p.programId, "programName": p.programName,
                   "lineId": p.lineId, "lineName": p.lineName])
        })
    }

    public func saveProjects(_ accountId: String, _ items: [ProviderProject]) async {
        await save(accountId, Self.projects, items.map { p in
            clean(["id": p.id, "name": p.name, "programId": p.programId, "programName": p.programName])
        })
    }

    private func clean(_ m: [String: String?]) -> [String: String] { m.compactMapValues { $0 } }

    private func read(_ accountId: String, _ kind: String) async -> [(id: String, name: String, extra: [String: String])]? {
        guard let json = await store.read(accountId: accountId, kind: kind) else { return nil }
        // A snapshot is only a head start for the network fetch that follows: an unreadable one is a cache miss.
        guard let arr = (try? JSONSerialization.jsonObject(with: Data(json.utf8))) as? [[String: Any]] else { return nil }
        var out: [(String, String, [String: String])] = []
        for e in arr {
            guard let id = e["id"] as? String, let name = e["name"] as? String else { return nil }
            var extra: [String: String] = [:]
            for (k, v) in e { if let s = v as? String, k != "id", k != "name" { extra[k] = s } }
            out.append((id, name, extra))
        }
        return out
    }

    private func save(_ accountId: String, _ kind: String, _ items: [[String: String]]) async {
        guard let data = try? JSONSerialization.data(withJSONObject: items, options: [.sortedKeys]) else { return }
        await store.write(accountId: accountId, kind: kind, json: String(decoding: data, as: UTF8.self))
    }
}
