import CoreDomain
import Foundation
import Observation
import SharedKit

/// Ported from: lib/tools/gitlab/presentation/providers/gitlab_board_providers.dart (`gitlabProjectsProvider`,
/// `_cachedThenFresh`). The projects an account is a member of (the sidebar tree): painted from the sync layer's disk
/// cache when there is one, then replaced by the fresh list; a failure only shows when nothing was cached.
@MainActor @Observable
final class GitlabProjectsModel {
    enum Phase: Equatable { case loading, loaded([ProviderProject]), failed(String) }

    private(set) var phase: Phase = .loading
    private let accountId: String
    private let service: GitLabMrService
    private let cached: (@Sendable (String) async -> [ProviderProject]?)?
    private var loading = false

    init(accountId: String, service: GitLabMrService, cached: (@Sendable (String) async -> [ProviderProject]?)? = nil) {
        self.accountId = accountId; self.service = service; self.cached = cached
    }

    var projects: [ProviderProject] { if case .loaded(let p) = phase { p } else { [] } }

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
        var stored: [ProviderProject]? = projects.isEmpty ? nil : projects
        if phase == .loading, let cached, let hit = await cached(accountId) { stored = hit; phase = .loaded(hit) }
        switch await service.listProjects(accountId: accountId) {
        case .success(let fresh): phase = .loaded(fresh)
        case .failure(let f): if stored == nil { phase = .failed(f.message) }
        }
    }
}

/// Splits `projects` for the scope list: name filter, pinned (by `accountId:id` key), recent (unpinned ones in
/// `recentIds`), and the unpinned rest (the namespace tree is built from it).
struct GitlabProjectGroups {
    var pinned: [ProviderProject]
    var recent: [ProviderProject]
    var rest: [ProviderProject]

    static func key(_ p: ProviderProject) -> String { "\(p.accountId):\(p.id)" }

    init(projects: [ProviderProject], filter: String, pinnedKeys: Set<String>, recentIds: Set<String>) {
        let query = filter.trimmingCharacters(in: .whitespaces).lowercased()
        let filtered = query.isEmpty ? projects : projects.filter { $0.name.lowercased().contains(query) }
        pinned = filtered.filter { pinnedKeys.contains(Self.key($0)) }
        rest = filtered.filter { !pinnedKeys.contains(Self.key($0)) }
        recent = rest.filter { recentIds.contains($0.id) }
    }
}

/// Open (not done) tickets of `accountId` in project `projectId` — the count badge of a project row.
func gitlabOpenCount(_ tickets: [Ticket], accountId: String, projectId: String) -> Int {
    tickets.reduce(0) { $0 + ($1.accountId == accountId && $1.status != .done && gitlabTicketInProject($1, projectId) ? 1 : 0) }
}

/// The open count of a group: its projects plus every subgroup's (`_aggregateCount` of the Dart group node).
func gitlabGroupCount(_ node: GitLabGroupNode, _ openCountOf: (String) -> Int) -> Int {
    node.projects.reduce(0) { $0 + openCountOf($1.id) } + node.subgroups.reduce(0) { $0 + gitlabGroupCount($1, openCountOf) }
}
