import CoreDomain
import CoreTools
import Foundation
import Observation
import SharedKit

/// The repo whose dedicated board is open (Dart `GitHubRepoSelection`).
struct GithubRepoSelection: Equatable {
    var accountId: String
    /// The `owner/name` slug.
    var repoId: String
    var repoName: String
    /// The account-wide "my pull requests" board (assigned + review across all repos) rather than one repo.
    var mine = false
}

/// What decides when the open repo's items are fetched again.
struct GithubSliceKey: Equatable { var selection: GithubRepoSelection?; var kind: GitHubItemKind; var generation: Int }

/// Everything the GitHub views share: the app services, the nav controller, the PR service and the UI state that the
/// Dart app kept in Riverpod notifiers (`selectedGitHubRepoProvider`, `githubKindProvider`, the slice provider, the
/// Review-requested quick scope — `QuickScope` has no such case in Swift — and the pinned repositories).
@MainActor @Observable
final class GithubContext {
    let services: AppServices
    let nav: AppNavController
    let registry: ToolRegistry
    let prService: GitHubPrService

    /// The repo whose board is open (nil off a repo).
    private(set) var selection: GithubRepoSelection?
    /// Accounts whose "Review requested" quick scope is on.
    private(set) var reviewRequested: Set<String> = []
    private(set) var sliceLoading = false
    private(set) var sliceError: String?
    private(set) var sliceGeneration = 0
    private(set) var pinnedProjects: Set<String> = []
    private(set) var rememberedViewModes: [String: String] = [:]
    private(set) var dateFormat = "iso"
    private var repoModels: [String: GithubReposModel] = [:]
    private var sliceRun = 0
    /// Every ticket in the local DB (the open counts of the repo tree).
    private(set) var tickets: [Ticket] = []
    private var tasks: [Task<Void, Never>] = []

    init(services: AppServices, nav: AppNavController, registry: ToolRegistry, prService: GitHubPrService) {
        self.services = services; self.nav = nav; self.registry = registry; self.prService = prService
    }

    /// Starts watching the settings (pinned repos, remembered view modes) and the tickets. Idempotent.
    func start() {
        guard tasks.isEmpty else { return }
        let settings = services.settings.watch(), tickets = services.tickets.watchTickets()
        tasks = [
            Task { [weak self] in
                for await s in settings { self?.pinnedProjects = Set(s.pinnedProjects); self?.rememberedViewModes = s.viewModes; self?.dateFormat = s.dateFormat }
            },
            Task { [weak self] in for await t in tickets { self?.tickets = t } },
        ]
    }

    func stop() { tasks.forEach { $0.cancel() }; tasks = [] }

    func repos(for accountId: String) -> GithubReposModel {
        if let m = repoModels[accountId] { return m }
        let coordinator = services.sync as? SyncCoordinator
        let m = GithubReposModel(accountId: accountId, service: prService,
                                 cached: coordinator.map { c in { @Sendable id in await c.cachedProjects(accountId: id) } })
        repoModels[accountId] = m
        return m
    }

    // MARK: Selection

    /// What the section of `kind` re-fetches on (the section on screen decides the kind, not a global as in Dart).
    func sliceKey(kind: GitHubItemKind) -> GithubSliceKey { GithubSliceKey(selection: selection, kind: kind, generation: sliceGeneration) }

    /// Selecting the repo (not only the scope) is what syncs its items.
    func selectRepo(_ repo: ProviderProject) {
        nav.setScope(repo.id, accountId: repo.accountId)
        reviewRequested.remove(repo.accountId)
        selection = GithubRepoSelection(accountId: repo.accountId, repoId: repo.id, repoName: repo.name)
    }

    /// Opens a repo's board from the tree: Issues kind, Issues section (Dart `GitHubRepoRow._select`).
    func openRepoBoard(_ repo: ProviderProject) {
        nav.select(.account(repo.accountId))
        nav.setSection("github.issues", accountId: repo.accountId)
        selectRepo(repo)
    }

    func selectMine(accountId: String) {
        selection = GithubRepoSelection(accountId: accountId, repoId: "", repoName: "", mine: true)
    }

    /// "All repositories": no scope, no quick scope, no selection.
    func selectAll(accountId: String) {
        nav.setScope(nil, accountId: accountId)
        nav.setQuickScope(.none, accountId: accountId)
        reviewRequested.remove(accountId)
        selection = nil
    }

    func setReviewRequested(_ on: Bool, accountId: String) {
        if on { reviewRequested.insert(accountId) } else { reviewRequested.remove(accountId) }
    }

    func isReviewRequested(_ accountId: String) -> Bool { reviewRequested.contains(accountId) }

    // MARK: Slice sync

    func refreshSlice() { sliceGeneration += 1 }

    /// Fetches the selected repo + kind's items into the local DB (the list and board read them from there).
    func syncSlice(kind: GitHubItemKind) async {
        guard let selection else { return }
        sliceRun += 1
        let run = sliceRun
        sliceLoading = true; sliceError = nil
        let result: Outcome<[String]>
        if selection.mine { result = await prService.syncGitHubMine(accountId: selection.accountId) }
        else {
            result = await prService.syncGitHubRepoItems(accountId: selection.accountId, repoId: selection.repoId,
                                                         pullRequests: kind == .pullRequest)
        }
        guard run == sliceRun else { return }
        sliceLoading = false
        if case .failure(let f) = result { sliceError = f.message }
    }

    // MARK: Settings writes

    func togglePinnedProject(_ key: String) {
        if pinnedProjects.contains(key) { pinnedProjects.remove(key) } else { pinnedProjects.insert(key) }
        let settings = services.settings
        Task {
            var s = await settings.load()
            if let i = s.pinnedProjects.firstIndex(of: key) { s.pinnedProjects.remove(at: i) } else { s.pinnedProjects.append(key) }
            _ = await settings.save(s)
        }
    }

    func rememberViewMode(_ mode: ViewModeID, section: SectionID, accountId: String) {
        nav.setViewMode(mode, section: section, accountId: accountId)
        rememberedViewModes[section.rawValue] = mode.rawValue
        let settings = services.settings
        Task {
            var s = await settings.load()
            s.viewModes[section.rawValue] = mode.rawValue
            _ = await settings.save(s)
        }
    }

    /// The view mode on screen: the location's, else the remembered one, else `fallback`.
    func viewMode(accountId: String, section: SectionID, fallback: ViewModeID) -> ViewModeID {
        nav.location(for: accountId).viewModes[section] ?? rememberedViewModes[section.rawValue].map { ViewModeID(rawValue: $0) } ?? fallback
    }
}
