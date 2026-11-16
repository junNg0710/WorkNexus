import CoreDomain
import Foundation
import Observation
import SharedKit

/// Ported from: lib/tools/github/presentation/providers/github_board_providers.dart (`githubReposProvider`,
/// `_cachedThenFresh`). The repositories an account can access (the sidebar tree): painted from the sync layer's
/// disk cache when there is one, then replaced by the fresh list; a failure only shows when nothing was cached.
@MainActor @Observable
final class GithubReposModel {
    enum Phase: Equatable { case loading, loaded([ProviderProject]), failed(String) }

    private(set) var phase: Phase = .loading
    private let accountId: String
    private let service: GitHubPrService
    private let cached: (@Sendable (String) async -> [ProviderProject]?)?
    private var loading = false

    init(accountId: String, service: GitHubPrService, cached: (@Sendable (String) async -> [ProviderProject]?)? = nil) {
        self.accountId = accountId; self.service = service; self.cached = cached
    }

    var repos: [ProviderProject] { if case .loaded(let r) = phase { r } else { [] } }

    /// Loads once (idempotent); `reload()` forces a fresh fetch.
    func load() async {
        guard !loading, phase == .loading else { return }
        await fetch()
    }

    func reload() async {
        guard !loading else { return }
        if case .failed = phase { phase = .loading }
        await fetch()
    }

    private func fetch() async {
        loading = true
        defer { loading = false }
        var stored: [ProviderProject]? = repos.isEmpty ? nil : repos
        if phase == .loading, let cached, let hit = await cached(accountId) { stored = hit; phase = .loaded(hit) }
        switch await service.listProjects(accountId: accountId) {
        case .success(let fresh): phase = .loaded(fresh)
        case .failure(let f): if stored == nil { phase = .failed(f.message) }
        }
    }
}

/// Splits `repos` for the scope list: name filter, pinned (by `accountId:id` key), recent (unpinned ones in `recentIds`),
/// and the unpinned rest.
struct GithubRepoGroups {
    var pinned: [ProviderProject]
    var recent: [ProviderProject]
    var rest: [ProviderProject]

    static func key(_ p: ProviderProject) -> String { "\(p.accountId):\(p.id)" }

    init(repos: [ProviderProject], filter: String, pinnedKeys: Set<String>, recentIds: Set<String>) {
        let query = filter.trimmingCharacters(in: .whitespaces).lowercased()
        let filtered = query.isEmpty ? repos : repos.filter { $0.name.lowercased().contains(query) }
        pinned = filtered.filter { pinnedKeys.contains(Self.key($0)) }
        rest = filtered.filter { !pinnedKeys.contains(Self.key($0)) }
        recent = rest.filter { recentIds.contains($0.id) }
    }
}

/// Open (not done) tickets of `accountId` in repository `repoId` — the count badge of a repo row.
func githubOpenCount(_ tickets: [Ticket], accountId: String, repoId: String) -> Int {
    var n = 0
    for t in tickets where t.accountId == accountId && t.status != .done {
        var repo: String?
        if case .githubItem(let g)? = t.providerEntity { repo = g.repo }
        if repo == repoId || t.projectId == repoId { n += 1 }
    }
    return n
}
