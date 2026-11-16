import CoreDomain
import CoreTools
import Foundation
import Observation
import SharedKit

/// The project whose dedicated board is open (Dart `GitLabProjectSelection`).
struct GitlabProjectSelection: Equatable {
    var accountId: String
    /// The project's numeric id (`ProviderProject.id`).
    var projectId: String
    var projectName: String
    /// The account-wide "my merge requests" board (all projects) rather than one project.
    var mine = false
}

/// What decides when the open project's items are fetched again.
struct GitlabSliceKey: Equatable { var selection: GitlabProjectSelection?; var kind: GitLabItemKind; var generation: Int }

/// Everything the GitLab views share: the app services, the nav controller, the MR service and the UI state that the Dart
/// app kept in Riverpod notifiers (`selectedGitLabProjectProvider`, the slice providers, `gitlabGroupsCollapsedProvider`,
/// `gitlabMrChipFilterProvider`) plus the pinned projects and remembered view modes from the settings.
@MainActor @Observable
final class GitlabContext {
    let services: AppServices
    let nav: AppNavController
    let registry: ToolRegistry
    let mrService: GitLabMrService

    /// The project whose board is open (nil off a project).
    private(set) var selection: GitlabProjectSelection?
    /// The merge-request list chip (All open / Draft / In review / Assigned to me).
    var chip: GitlabMrChip = .allOpen
    /// Namespace groups (`accountId:fullPath`) collapsed in the nav tree; empty by default, so every group starts open.
    private(set) var collapsedGroups: Set<String> = []
    private(set) var sliceLoading = false
    private(set) var sliceError: String?
    private(set) var sliceGeneration = 0
    private(set) var pinnedProjects: Set<String> = []
    private(set) var rememberedViewModes: [String: String] = [:]
    private(set) var dateFormat = "iso"
    private(set) var accounts: [String: Account] = [:]
    /// Every ticket in the local DB (the open counts of the project tree).
    private(set) var tickets: [Ticket] = []
    private var projectModels: [String: GitlabProjectsModel] = [:]
    private var sliceRun = 0
    private var tasks: [Task<Void, Never>] = []

    init(services: AppServices, nav: AppNavController, registry: ToolRegistry, mrService: GitLabMrService) {
        self.services = services; self.nav = nav; self.registry = registry; self.mrService = mrService
    }

    /// Starts watching the settings (pinned projects, remembered view modes), the accounts and the tickets. Idempotent.
    func start() {
        guard tasks.isEmpty else { return }
        let settings = services.settings.watch(), tickets = services.tickets.watchTickets(), accounts = services.workspaces.watchAccounts()
        tasks = [
            Task { [weak self] in
                for await s in settings { self?.pinnedProjects = Set(s.pinnedProjects); self?.rememberedViewModes = s.viewModes; self?.dateFormat = s.dateFormat }
            },
            Task { [weak self] in for await t in tickets { self?.tickets = t } },
            Task { [weak self] in for await a in accounts { self?.accounts = Dictionary(a.map { ($0.id, $0) }, uniquingKeysWith: { x, _ in x }) } },
        ]
    }

    func stop() { tasks.forEach { $0.cancel() }; tasks = [] }

    func projects(for accountId: String) -> GitlabProjectsModel {
        if let m = projectModels[accountId] { return m }
        let coordinator = services.sync as? SyncCoordinator
        let m = GitlabProjectsModel(accountId: accountId, service: mrService,
                                    cached: coordinator.map { c in { @Sendable id in await c.cachedProjects(accountId: id) } })
        projectModels[accountId] = m
        return m
    }

    // MARK: Selection

    /// What the section of `kind` re-fetches on (the section on screen decides the kind, not a global as in Dart).
    func sliceKey(kind: GitLabItemKind) -> GitlabSliceKey { GitlabSliceKey(selection: selection, kind: kind, generation: sliceGeneration) }

    /// Selecting the project (not only the scope) is what syncs its items.
    func selectProject(_ project: ProviderProject) {
        nav.setScope(project.id, accountId: project.accountId)
        selection = GitlabProjectSelection(accountId: project.accountId, projectId: project.id, projectName: project.name)
    }

    func selectMine(accountId: String) {
        selection = GitlabProjectSelection(accountId: accountId, projectId: "", projectName: "", mine: true)
    }

    /// "All projects": no scope, no quick scope, no selection.
    func selectAll(accountId: String) {
        nav.setScope(nil, accountId: accountId)
        nav.setQuickScope(.none, accountId: accountId)
        selection = nil
    }

    func selectAssignedToMe(accountId: String) { nav.setQuickScope(.assignedToMe, accountId: accountId) }

    func toggleGroup(_ key: String) {
        if collapsedGroups.contains(key) { collapsedGroups.remove(key) } else { collapsedGroups.insert(key) }
    }

    // MARK: Slice sync

    func refreshSlice() { sliceGeneration += 1 }

    /// Fetches the selected project + kind's items into the local DB (the list and board read them from there).
    func syncSlice(kind: GitLabItemKind) async {
        guard let selection else { return }
        sliceRun += 1
        let run = sliceRun
        sliceLoading = true; sliceError = nil
        let result: Outcome<[String]>
        if selection.mine { result = await mrService.syncGitLabMine(accountId: selection.accountId) }
        else {
            result = await mrService.syncGitLabProjectItems(accountId: selection.accountId, projectId: selection.projectId,
                                                            mergeRequests: kind == .mergeRequest)
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
