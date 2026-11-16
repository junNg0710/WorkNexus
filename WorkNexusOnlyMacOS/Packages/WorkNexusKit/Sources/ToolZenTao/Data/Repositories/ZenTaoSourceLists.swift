import CoreDomain
import Foundation

/// Ported from: lib/tools/zentao/data/repositories/zentao_source_lists.dart
/// The containers an account's sidebar lists - products and projects - with ZenTao's own grouping: a product's
/// program and line, a project's program. Never a made-up one: when the grouping is not to be had, the lists
/// come back without it and the sidebar shows them flat.
struct ZenTaoSourceLists {
    let client: ZenTaoClient
    let accountId: String
    static let pageLimit = 500

    /// Every product, filed under program and line from ZenTao's merged tree; an older server without it (or
    /// failing on it) gets the plain list.
    func products() async throws -> [ProviderProduct] {
        do { return try await allProducts(merged: true) } catch { return try await allProducts(merged: false) }
    }

    /// Every product, page by page (the tree may be paged like the list).
    private func allProducts(merged: Bool) async throws -> [ProviderProduct] {
        var out: [ProviderProduct] = []
        var seen = Set<String>()
        var total = 0
        for page in 1...50 {
            let res = try await client.products(page: page, limit: Self.pageLimit, merged: merged)
            if res.total > 0 { total = res.total }
            var added = 0
            for p in res.products where !p.id.isEmpty && seen.insert(p.id).inserted {
                out.append(ProviderProduct(id: p.id, name: p.name.isEmpty ? p.id : p.name, accountId: accountId,
                                           programId: p.programId, programName: p.programName,
                                           lineId: p.lineId, lineName: p.lineName))
                added += 1
            }
            if added == 0 { break }
            if total > 0 && out.count >= total { break }
        }
        return out
    }

    /// Every project, each with its program (its `parent`), named from `/programs`.
    func projects() async throws -> [ProviderProject] {
        var out: [ProviderProject] = []
        var seen = Set<String>()
        var total = 0
        for page in 1...50 {
            let res = try await client.projects(page: page, limit: Self.pageLimit)
            if res.total > 0 { total = res.total }
            var added = 0
            for p in res.projects where !p.id.isEmpty && seen.insert(p.id).inserted {
                out.append(ProviderProject(id: p.id, name: p.name.isEmpty ? p.id : p.name, accountId: accountId,
                                           programId: p.programId, programName: p.programName))
                added += 1
            }
            if added == 0 { break }
            if total > 0 && out.count >= total { break }
        }
        return await withProgramNames(out)
    }

    /// Names `projects`' programs from `/programs`. Without it (an older server, or the call failing) they stay
    /// unnamed, and the sidebar shows the projects flat.
    private func withProgramNames(_ projects: [ProviderProject]) async -> [ProviderProject] {
        guard projects.contains(where: { $0.programId != nil && $0.programName == nil }) else { return projects }
        var names: [String: String] = [:]
        do {
            for page in 1...20 {
                let res = try await client.programs(page: page, limit: Self.pageLimit)
                let before = names.count
                for (id, name) in res.names where names[id] == nil { names[id] = name }
                if names.count == before { break }
                if res.total > 0 && names.count >= res.total { break }
            }
        } catch {
            // `/programs` unavailable: the projects stay unnamed.
        }
        return projects.map {
            ProviderProject(id: $0.id, name: $0.name, accountId: $0.accountId, programId: $0.programId,
                            programName: $0.programName ?? $0.programId.flatMap { names[$0] })
        }
    }
}
